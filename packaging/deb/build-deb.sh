#!/bin/bash
# packaging/deb/build-deb.sh — assemble a .deb from the already-built
# artifacts (Rust CLI in target/release, Flutter GUI bundle, nfqws fetched
# by scripts/fetch-zapret.sh). Mirrors the /usr layout of the AppImage.
#
# Usage: packaging/deb/build-deb.sh [--out dist]
set -euo pipefail

cd "$(dirname "$0")/../.."

OUT_DIR="dist"
while [ $# -gt 0 ]; do
    case "$1" in
        --out=*) OUT_DIR="${1#--out=}" ;;
        --out)   OUT_DIR="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

[ -f target/release/unblocker ] || { echo "✗ build Rust first: cargo build --release" >&2; exit 1; }
# GUI: either a freshly built Flutter bundle or a prebuilt one
# (NUKERA_GUI_BUNDLE=/path/to/bundle with lib/ + data/ + unblocker-gui).
if [ -n "${NUKERA_GUI_BUNDLE:-}" ]; then
    BUNDLE="${NUKERA_GUI_BUNDLE}"
    [ -d "$BUNDLE/lib" ] && [ -x "$BUNDLE/unblocker-gui" ] || {
        echo "✗ NUKERA_GUI_BUNDLE must be a Flutter linux bundle (lib/, data/, unblocker-gui)" >&2; exit 1; }
    echo "Using prebuilt GUI bundle: $BUNDLE"
elif [ -d unblocker_gui/build/linux/x64/release/bundle ]; then
    BUNDLE="unblocker_gui/build/linux/x64/release/bundle"
else
    echo "✗ build GUI first: (cd unblocker_gui && flutter build linux --release) or set NUKERA_GUI_BUNDLE" >&2
    exit 1
fi
[ -f vendor/zapret/nfqws ] || { echo "✗ fetch nfqws first: scripts/fetch-zapret.sh" >&2; exit 1; }

VER="$(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)"
VER="${VER#v}"
# dpkg requires a version starting with a digit; git short-sha starts with a letter
case "$VER" in
    [0-9]*) : ;;
    *) VER="0.0+$VER" ;;
esac
PKG="nukera_${VER}_amd64"
STAGE="$(mktemp -d /tmp/nukera-deb.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

CTRL="$STAGE/$PKG/DEBIAN"
mkdir -p "$CTRL" "$STAGE/$PKG/usr/lib/nukera" "$STAGE/$PKG/usr/lib/unblocker" \
    "$STAGE/$PKG/usr/bin" "$STAGE/$PKG/usr/lib/systemd/system" \
    "$STAGE/$PKG/etc/polkit-1/rules.d" "$STAGE/$PKG/usr/share/applications" \
    "$STAGE/$PKG/usr/share/pixmaps" "$STAGE/$PKG/etc/unblocker/strategies/pool/byebyedpi" \
    "$STAGE/$PKG/etc/unblocker/hostlists" "$STAGE/$PKG/etc/unblocker/sites"

# ── payload (same layout as the AppImage) ───────────────────────────────
cp -r "$BUNDLE/." "$STAGE/$PKG/usr/lib/nukera/"
install -m755 target/release/unblocker "$STAGE/$PKG/usr/lib/nukera/unblocker"
ln -sf /usr/lib/nukera/unblocker "$STAGE/$PKG/usr/bin/unblocker"
install -m755 scripts/unblocker-kill.sh "$STAGE/$PKG/usr/lib/nukera/unblocker-kill.sh"
install -m755 scripts/unblocker-root-cleanup.sh "$STAGE/$PKG/usr/lib/nukera/unblocker-root-cleanup.sh"
install -m755 scripts/unblocker-kill.sh "$STAGE/$PKG/usr/bin/unblocker-kill"
# init-system helpers (systemd / SysV+busybox / runit / OpenRC / manual)
install -m755 scripts/nukera-service.sh "$STAGE/$PKG/usr/bin/nukera-service"
install -m755 scripts/detect-init.sh "$STAGE/$PKG/usr/bin/nukera-detect-init"
install -m755 scripts/hybrid-build.sh "$STAGE/$PKG/usr/bin/nukera-hybrid-build"
install -m755 vendor/zapret/nfqws "$STAGE/$PKG/usr/lib/unblocker/nfqws"

install -d "$STAGE/$PKG/etc/unblocker"
install -m644 config/zapret/strategies/*.strat "$STAGE/$PKG/etc/unblocker/strategies/"
install -m644 config/zapret/strategies/pool/*.strat "$STAGE/$PKG/etc/unblocker/strategies/pool/"
install -m644 config/zapret/strategies/pool/byebyedpi/*.strat "$STAGE/$PKG/etc/unblocker/strategies/pool/byebyedpi/"
ln -s strategies/general-hostfakesplit.strat "$STAGE/$PKG/etc/unblocker/strategy.conf"
install -m644 config/zapret/hostlists/*.sites "$STAGE/$PKG/etc/unblocker/hostlists/"
install -m644 config/zapret/hostlists/ig-fb-known-good.txt "$STAGE/$PKG/etc/unblocker/hostlists/"
install -m644 config/hosts/telegram-web.txt "$STAGE/$PKG/etc/unblocker/hostlists/telegram-web.txt"
install -m644 config/hosts/magila-cdn.txt "$STAGE/$PKG/etc/unblocker/hostlists/magila-cdn.txt"
touch "$STAGE/$PKG/etc/unblocker/hostlists/auto.txt"

install -m644 packaging/systemd/unblocker.service "$STAGE/$PKG/usr/lib/systemd/system/unblocker.service"
install -m644 packaging/polkit/50-unblocker.rules "$STAGE/$PKG/etc/polkit-1/rules.d/50-unblocker.rules"
install -m644 packaging/desktop/unblocker.desktop "$STAGE/$PKG/usr/share/applications/unblocker.desktop"
install -m644 assets/icons/nukera_icon.png "$STAGE/$PKG/usr/share/pixmaps/nukera.png"

printf '%s\n' "$VER" > "$STAGE/$PKG/usr/lib/nukera/version"

# ── control files ───────────────────────────────────────────────────────
cat > "$CTRL/control" << EOF
Package: nukera
Version: $VER
Section: net
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.31), libgtk-3-0, nftables, curl, iptables, iproute2
Suggests: policykit-1
Maintainer: naygmus <naygmus@users.noreply.github.com>
Homepage: https://github.com/naygmus/nukera-hybrid
Description: Nukera — DPI + IP-block bypass (GUI + daemon)
 Hybrid strategies, selective routing and per-site strategy selection on
 top of zapret (nfqws). Includes the Flutter GUI, the unblocker daemon,
 the nfqws engine and strategy/config files.
EOF

cat > "$CTRL/postinst" << 'EOF'
#!/bin/sh
setcap cap_net_admin,cap_net_raw,cap_dac_override,cap_setuid,cap_setgid,cap_setpcap,cap_sys_admin=+ep \
    /usr/lib/unblocker/nfqws 2>/dev/null || true
setcap cap_net_admin,cap_net_raw,cap_dac_override=+ep /usr/lib/nukera/unblocker 2>/dev/null || true
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
fi

# The reestr blocklist is fetched, not bundled (16 MB, updated daily).
# Without it every strategy referencing it fails and nfqws aborts on start.
REESTR=/etc/unblocker/hostlists/reestr.txt
if [ ! -s "$REESTR" ] || [ "$(stat -c %s "$REESTR" 2>/dev/null || echo 0)" -lt 102400 ]; then
    echo "Downloading reestr blocklist (required by the strategies)…"
    curl -fL --max-time 120 \
        "https://raw.githubusercontent.com/bol-van/rulist/main/reestr_hostname_resolvable.txt" \
        -o "$REESTR" 2>/dev/null \
        || echo "WARNING: download failed — fetch it manually, the bypass won't start without it"
fi

# On hosts without a global IPv6 route, AAAA-first resolution hangs apps.
# Prefer A records (standard zapret recommendation; harmless elsewhere).
if [ -f /etc/gai.conf ] || : > /etc/gai.conf 2>/dev/null; then
    grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null \
        || echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
fi

# Minimal systems (Puppy/busybox) don't auto-load the NFQUEUE module.
modprobe nfnetlink_queue 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
    echo "Nukera installed. Start: systemctl start unblocker (or run 'unblocker daemon')."
else
    echo "Nukera installed (non-systemd system). Start: 'unblocker daemon'"
    echo "or manage the service with 'nukera-service start'."
fi
exit 0
EOF
cat > "$CTRL/postrm" << 'EOF'
#!/bin/sh
rm -f /var/run/unblocker.pid
exit 0
EOF
chmod 755 "$CTRL/postinst" "$CTRL/postrm"

mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group --build "$STAGE/$PKG" "$OUT_DIR/$PKG.deb"
echo "✓ Built: $OUT_DIR/$PKG.deb ($(du -h "$OUT_DIR/$PKG.deb" | cut -f1))"
