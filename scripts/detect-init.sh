#!/bin/sh
# detect-init.sh — determine the system's init/service manager and distro
# quirks. Portable across glibc/musl/busybox (Puppy, Alpine, Debian, OpenWrt).
#
# Usage: detect-init.sh            prints INIT=... PUPPY=... and details
#        detect-init.sh --quiet    prints only INIT value
#        detect-init.sh --sh       prints KEY=VALUE lines suitable for eval
#
# Exit code is always 0 — unknown systems are reported as INIT=unknown.

PRINT_MODE="full"
case "${1:-}" in
    --quiet) PRINT_MODE="quiet" ;;
    --sh)    PRINT_MODE="sh" ;;
esac

INIT="unknown"
DETAILS=""

pid1_exe=""
if [ -r /proc/1/exe ] && readlink /proc/1/exe >/dev/null 2>&1; then
    pid1_exe="$(readlink /proc/1/exe 2>/dev/null || echo "")"
fi
pid1_comm=""
if [ -r /proc/1/comm ]; then
    pid1_comm="$(cat /proc/1/comm 2>/dev/null || echo "")"
fi

# ── systemd ────────────────────────────────────────────────────────────
if [ "${pid1_comm}" = "systemd" ] || [ "${pid1_exe}" = "/lib/systemd/systemd" ] \
   || [ "${pid1_exe}" = "/usr/lib/systemd/systemd" ]; then
    INIT="systemd"
    DETAILS="pid1 is systemd"
elif command -v systemctl >/dev/null 2>&1 \
     && systemctl is-system-running >/dev/null 2>&1; then
    # container/chroot case: systemctl works even though pid1 differs
    INIT="systemd"
    DETAILS="systemctl is functional"
fi

# ── OpenRC ─────────────────────────────────────────────────────────────
if [ "$INIT" = "unknown" ] && [ -d /run/openrc ]; then
    INIT="openrc"
    DETAILS="found /run/openrc"
fi

# ── runit ──────────────────────────────────────────────────────────────
if [ "$INIT" = "unknown" ]; then
    if [ "${pid1_comm}" = "runit" ] || [ -x /etc/runit/2 ] \
       || [ -d /run/runit ]; then
        INIT="runit"
        DETAILS="runit pid1 or /run/runit"
    elif [ -x /etc/s6-rc ] || [ -d /run/s6-rc ]; then
        INIT="s6"
        DETAILS="s6-rc detected"
    fi
fi

# ── procd (OpenWrt) ────────────────────────────────────────────────────
if [ "$INIT" = "unknown" ] && [ "${pid1_comm}" = "procd" ]; then
    INIT="procd"
    DETAILS="OpenWrt procd"
fi

# ── sysvinit / busybox init (covers Puppy and most minimal distros) ────
if [ "$INIT" = "unknown" ] && [ -d /etc/init.d ]; then
    INIT="sysvinit"
    DETAILS="/etc/init.d present (sysvinit or busybox init)"
fi

# ── Puppy Linux marker (busybox init, root user, own startup dirs) ─────
PUPPY="no"
if [ -f /etc/puppyversion ] || [ -f /etc/DISTRO_SPECS ] \
   && grep -qi "puppy" /etc/DISTRO_SPECS /etc/DISTRO_NAME 2>/dev/null; then
    PUPPY="yes"
    DETAILS="${DETAILS:+$DETAILS; }Puppy Linux (init.d style, often no polkit)"
fi
if [ "$PUPPY" = "yes" ] && [ "$INIT" = "sysvinit" ]; then
    DETAILS="${DETAILS}; use /etc/init.d + /root/Startup for autostart"
fi

if [ "$PRINT_MODE" = "quiet" ]; then
    echo "$INIT"
elif [ "$PRINT_MODE" = "sh" ]; then
    echo "INIT=$INIT"
    echo "PUPPY=$PUPPY"
else
    echo "INIT=$INIT"
    echo "PUPPY=$PUPPY"
    [ -n "$DETAILS" ] && echo "DETAILS: $DETAILS"
    echo "systemctl available: $(command -v systemctl >/dev/null 2>&1 && echo yes || echo no)"
    echo "polkit dir present:  $([ -d /etc/polkit-1 ] && echo yes || echo no)"
    echo "init.d dir present:  $([ -d /etc/init.d ] && echo yes || echo no)"
fi
exit 0
