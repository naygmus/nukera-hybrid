#!/bin/sh
# hybrid-build.sh — build a hybrid strategy for Linux from a simple spec.
#
# A hybrid strategy lets different sites use different DPI-bypass profiles
# inside ONE nfqws process (nfqws supports --new profile separation — same
# codebase as winws on Windows). Override groups are SNI-scoped via per-group
# hostlists and placed BEFORE the base profiles; base profiles get a
# combined --hostlist-exclude so they never touch override sites.
#
# Spec file (default /etc/unblocker/hybrid.conf), line format:
#   base     = /etc/unblocker/strategies/general-hostfakesplit.strat
#   override = rutor.is,example.org : /etc/unblocker/strategies/pool/05_disorder_fake.strat
#   override = youtube.com         : /etc/unblocker/strategies/pool/03_multisplit_md5sig.strat
#
# Usage:
#   hybrid-build.sh [--conf=/etc/unblocker/hybrid.conf] [--root=/etc/unblocker]
#                   [--nfqws=/usr/lib/unblocker/nfqws] [--restore]
#   hybrid-build.sh --check    (verify the installed nfqws supports --new)
#
# After building, restart the daemon to apply:
#   nukera-service.sh restart   (or: systemctl restart unblocker)
set -eu

CONF="/etc/unblocker/hybrid.conf"
ROOT="/etc/unblocker"
NFQWS=""
RESTORE=0
CHECK=0

for arg in "$@"; do
    case "$arg" in
        --conf=*)  CONF="${arg#--conf=}" ;;
        --root=*)  ROOT="${arg#--root=}" ;;
        --nfqws=*) NFQWS="${arg#--nfqws=}" ;;
        --restore) RESTORE=1 ;;
        --check)   CHECK=1 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

HOSTLISTS="$ROOT/hostlists"
OUT="$ROOT/strategy.conf"
BACKUP="$OUT.pre-hybrid"

log()  { printf '%s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

if [ "$CHECK" = 1 ]; then
    for c in /usr/lib/unblocker/nfqws /usr/local/bin/nfqws /usr/bin/nfqws; do
        [ -x "$c" ] && NFQWS="$c" && break
    done
    [ -n "$NFQWS" ] || die "nfqws binary not found"
    if "$NFQWS" --help 2>&1 | grep -q -- '--new'; then
        log "OK: nfqws supports --new profiles"
        exit 0
    fi
    die "installed nfqws does NOT support --new — update zapret to build hybrids"
fi

if [ "$RESTORE" = 1 ]; then
    [ -f "$BACKUP" ] || die "no backup: $BACKUP"
    cp "$BACKUP" "$OUT"
    rm -f "$HOSTLISTS"/hybrid_*.txt
    log "restored $OUT from $BACKUP (restart the daemon to apply)"
    exit 0
fi

[ -f "$CONF" ] || die "spec not found: $CONF (see header for format)"
[ -x "$NFQWS" ] || {
    for c in /usr/lib/unblocker/nfqws /usr/local/bin/nfqws /usr/bin/nfqws; do
        [ -x "$c" ] && NFQWS="$c" && break
    done
}
[ -x "$NFQWS" ] || die "nfqws binary not found (pass --nfqws=)"
"$NFQWS" --help 2>&1 | grep -q -- '--new' \
    || die "installed nfqws does NOT support --new profiles — cannot build hybrid"

mkdir -p "$HOSTLISTS"

# ── parse spec ─────────────────────────────────────────────────────────
BASE=""
OVR_LINES=""
while IFS= read -r line; do
    line="${line%%\#*}"
    case "$line" in
        *\=*) ;;
        *) continue ;;
    esac
    key="$(printf '%s' "${line%%=*}" | tr -d ' \t')"
    val="$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$val" ] || continue
    case "$key" in
        base)     BASE="$val" ;;
        override) OVR_LINES="$OVR_LINES
$val" ;;
    esac
done < "$CONF"

[ -n "$BASE" ] || die "spec has no 'base =' line"
[ -f "$BASE" ] || die "base strategy not found: $BASE"
[ -n "$OVR_LINES" ] || die "spec has no 'override =' lines"

# clean previous generated files
rm -f "$HOSTLISTS"/hybrid_*.txt

# ── load strategy file: strip comments, drop blank lines ──────────────
load_strat() {
    sed 's/#.*//' "$1" | sed '/^[[:space:]]*$/d'
}

# ── combined exclude list of all override domains ──────────────────────
OVR_LIST="$HOSTLISTS/hybrid_overrides.txt"
: > "$OVR_LIST"
printf '%s\n' "$OVR_LINES" | while IFS= read -r g; do
    [ -n "$g" ] || continue
    domains="$(printf '%s' "${g%%:*}" | sed 's/[[:space:]]*$//')"
    printf '%s\n' "$domains" | tr ',' '\n' | sed '/^[[:space:]]*$/d' >> "$OVR_LIST"
done
sort -u "$OVR_LIST" > "$OVR_LIST.tmp" && mv "$OVR_LIST.tmp" "$OVR_LIST"

EXCL="--hostlist-exclude=$OVR_LIST"
BASE_OUT="$ROOT/.hybrid_base.tmp"
: > "$BASE_OUT"
load_strat "$BASE" | while IFS= read -r line; do
    # insert the exclude right after the last --hostlist* token
    set -- $line
    last=0; i=0
    for tok in "$@"; do
        i=$((i + 1))
        case "$tok" in --hostlist|--hostlist-exclude|--hostlist-domains) last=$i ;; esac
    done
    if [ "$last" -gt 0 ]; then
        printf '%s\n' "$(printf '%s' "$line" | awk -v n="$last" -v ex="$EXCL" '{
            for (i = 1; i <= NF; i++) { printf "%s ", $i; if (i == n) printf "%s ", ex }
        }')" >> "$BASE_OUT"
    else
        printf '%s %s\n' "$EXCL" "$line" >> "$BASE_OUT"
    fi
done

# ── override groups: SNI-scoped profiles, first in the final file ──────
FINAL="$ROOT/.hybrid_final.tmp"
: > "$FINAL"
gi=0
printf '%s\n' "$OVR_LINES" | while IFS= read -r g; do
    [ -n "$g" ] || continue
    domains="$(printf '%s' "${g%%:*}" | sed 's/[[:space:]]*$//')"
    strat="$(printf '%s' "${g#*:}" | sed 's/^[[:space:]]*//')"
    gi=$((gi + 1))
    gl="$HOSTLISTS/hybrid_$gi.txt"
    printf '%s\n' "$domains" | tr ',' '\n' | sed '/^[[:space:]]*$/d' > "$gl"
    [ -f "$strat" ] || { echo "⚠ override strategy missing: $strat (skipped)" >&2; continue; }
    load_strat "$strat" | while IFS= read -r line; do
        # drop stock hostlists, insert the group one in their place
        out=""; inserted=0
        for tok in $line; do
            case "$tok" in
                --hostlist=*) if [ "$inserted" = 0 ]; then out="$out --hostlist=$gl"; inserted=1; fi ;;
                *) out="$out $tok" ;;
            esac
        done
        [ "$inserted" = 0 ] && out="--hostlist=$gl $out"
        printf '%s\n' "$out" >> "$FINAL"
    done
done

# ── assemble: overrides first, then base, separated by --new ───────────
{
    cat "$FINAL"
    echo "--new"
    cat "$BASE_OUT"
} > "$OUT"
rm -f "$FINAL" "$BASE_OUT"

log "hybrid strategy written: $OUT"
log "  base: $BASE"
printf '%s\n' "$OVR_LINES" | while IFS= read -r g; do
    domains="$(printf '%s' "${g%%:*}" | sed 's/[[:space:]]*$//')"
    [ -n "$g" ] || continue
    log "  override: $domains -> $(printf '%s' "${g#*:}" | sed 's/^[[:space:]]*//')"
done
log "Apply: restart the daemon (nukera-service.sh restart, or"
log "       systemctl restart unblocker). Undo: $0 --restore"
