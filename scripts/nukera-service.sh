#!/bin/sh
# nukera-service.sh — unified service manager for the unblocker daemon
# across init systems. Works on systemd distros, SysV/busybox init
# (Puppy Linux), runit, OpenRC, and with no daemon manager at all.
#
# Usage:
#   nukera-service.sh [--init=auto|systemd|sysv|runit|openrc|none] action
#
# Actions: install | remove | start | stop | restart | status |
#          enable | disable
#
# Everything is idempotent; missing tools degrade gracefully. Root is
# required except for status.

INIT_MODE="auto"
while [ $# -gt 0 ]; do
    case "$1" in
        --init=*) INIT_MODE="${1#--init=}" ;;
        *) break ;;
    esac
    shift
done
ACTION="${1:-status}"

DAEMON_DIR="/usr/lib/nukera"
EXEC_BIN="$DAEMON_DIR/unblocker"
PIDFILE="/var/run/unblocker.pid"
LOGFILE="/var/log/unblocker.log"
SVDIR="/etc/init.d"
UNIT="/etc/systemd/system/unblocker.service"

log()  { printf '%s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*"; }
die()  { printf '✗ %s\n' "$*"; exit 1; }

# ── init detection (unless overridden) ─────────────────────────────────
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ "$INIT_MODE" = "auto" ]; then
    if [ -n "$HERE" ] && [ -f "$HERE/detect-init.sh" ]; then
        INIT_MODE="$(sh "$HERE/detect-init.sh" --quiet)"
    else
        # require a RUNNING systemd, not merely the systemctl binary (Puppy ships one on busybox init)
        command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && INIT_MODE="systemd"
        [ "$INIT_MODE" = "systemd" ] || [ -d /etc/init.d ] && INIT_MODE="${INIT_MODE:-sysvinit}"
        INIT_MODE="${INIT_MODE:-none}"
    fi
fi

have_systemctl() { command -v systemctl >/dev/null 2>&1; }

# ── manual backend helpers (nohup + pidfile), used by sysv/none ────────
manual_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}
manual_start() {
    if manual_running; then
        log "already running (pid $(cat "$PIDFILE"))"
        return 0
    fi
    [ -x "$EXEC_BIN" ] || die "daemon binary missing: $EXEC_BIN"
    RUST_LOG="${RUST_LOG:-info}" \
    nohup "$EXEC_BIN" daemon >>"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1
    if manual_running; then
        log "started (pid $(cat "$PIDFILE"), log: $LOGFILE)"
    else
        warn "daemon exited immediately — see $LOGFILE"
        return 1
    fi
}
manual_stop() {
    if manual_running; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        i=0
        while manual_running && [ "$i" -lt 20 ]; do
            sleep 0.5; i=$((i + 1))
        done
        kill -9 "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        log "stopped"
    else
        rm -f "$PIDFILE"
        log "not running"
    fi
}

# ── backend: systemd ───────────────────────────────────────────────────
sv_systemd() {
    case "$ACTION" in
        install)
            [ -f "$UNIT" ] || die "unit file missing: $UNIT (install package first)"
            systemctl daemon-reload
            systemctl enable unblocker.service
            log "systemd service installed and enabled"
            ;;
        remove)
            systemctl disable --now unblocker.service 2>/dev/null
            rm -f "$UNIT"
            systemctl daemon-reload 2>/dev/null
            log "systemd service removed"
            ;;
        start)    systemctl start unblocker.service ;;
        stop)     systemctl stop unblocker.service ;;
        restart)  systemctl restart unblocker.service ;;
        status)   systemctl status unblocker.service --no-pager ;;
        enable)   systemctl enable unblocker.service ;;
        disable)  systemctl disable unblocker.service ;;
    esac
}

# ── backend: sysvinit / busybox init (Puppy Linux) ─────────────────────
sv_sysv() {
    RC="$SVDIR/unblocker"
    case "$ACTION" in
        install)
            cat > "$RC" << 'EOF'
#!/bin/sh
# /etc/init.d/unblocker — managed by nukera-service.sh
DAEMON="/usr/lib/nukera/unblocker"
PIDFILE="/var/run/unblocker.pid"
LOGFILE="/var/log/unblocker.log"
STATEFILE="/tmp/unblocker.state"
case "$1" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "unblocker already running"
            exit 0
        fi
        rm -f "$STATEFILE"
        nohup "$DAEMON" daemon >>"$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        echo "unblocker started (pid $(cat "$PIDFILE"))"
        ;;
    stop)
        if [ -f "$PIDFILE" ]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            i=0
            while kill -0 "$(cat "$PIDFILE")" 2>/dev/null && [ "$i" -lt 3 ]; do
                sleep 1; i=$((i+1))
            done
            kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
                && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
        fi
        # orphaned engine processes survive a SIGKILLed/crashed daemon
        pkill -x nfqws 2>/dev/null
        rm -f "$PIDFILE" "$STATEFILE"
        echo "unblocker stopped"
        ;;
    restart) "$0" stop; sleep 1; "$0" start ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "unblocker running (pid $(cat "$PIDFILE"))"
            exit 0
        else
            echo "unblocker not running"
            exit 3
        fi
        ;;
esac
EOF
            chmod 755 "$RC"
            # standard SysV runlevel links (best effort — Puppy/OpenWrt vary)
            for rl in 2 3 4 5; do
                [ -d "/etc/rc${rl}.d" ] && ln -sf "$RC" "/etc/rc${rl}.d/S99unblocker"
            done
            [ -d /etc/rc.d ] && ln -sf "$RC" /etc/rc.d/S99unblocker 2>/dev/null
            log "sysv init script installed: $RC"
            ;;
        remove)
            rm -f "$RC" /etc/rc.d/S99unblocker
            for rl in 2 3 4 5; do rm -f "/etc/rc${rl}.d/S99unblocker"; done
            log "sysv init script removed"
            ;;
        start|stop|restart|status) "$RC" "$ACTION" ;;
        enable)  log "sysv: enabled by default (S99 link). Nothing to do." ;;
        disable) for rl in 2 3 4 5; do rm -f "/etc/rc${rl}.d/S99unblocker"; done
                 log "sysv: autostart links removed" ;;
    esac
}

# ── backend: runit ─────────────────────────────────────────────────────
sv_runit() {
    SV=""; for d in /run/runit/service /var/service /service; do
        [ -d "$d" ] && SV="$d" && break
    done
    [ -n "$SV" ] || die "runit service dir not found"
    RC="/etc/sv/unblocker/run"
    case "$ACTION" in
        install)
            mkdir -p /etc/sv/unblocker
            printf '#!/bin/sh\nexec %s daemon 2>&1\n' "$EXEC_BIN" > "$RC"
            chmod 755 "$RC"
            ln -sf /etc/sv/unblocker "$SV/unblocker"
            log "runit service installed and started: $SV/unblocker"
            ;;
        remove)  rm -f "$SV/unblocker" /etc/sv/unblocker/run
                 log "runit service removed" ;;
        start)   [ -d "$SV/unblocker" ] || ln -sf /etc/sv/unblocker "$SV/unblocker" ;;
        stop)    rm -f "$SV/unblocker" ;;
        status)  [ -d "$SV/unblocker" ] && log "enabled" || log "not enabled" ;;
        enable)  ln -sf /etc/sv/unblocker "$SV/unblocker" ;;
        disable) rm -f "$SV/unblocker" ;;
    esac
}

# ── backend: OpenRC ────────────────────────────────────────────────────
sv_openrc() {
    RC="/etc/init.d/unblocker"
    case "$ACTION" in
        install)
            cat > "$RC" << 'EOF'
#!/sbin/openrc-run
name="unblocker"
command="/usr/lib/nukera/unblocker"
command_args="daemon"
command_background="yes"
pidfile="/var/run/unblocker.pid"
output_log="/var/log/unblocker.log"
error_log="/var/log/unblocker.log"
depend() { need net; }
EOF
            chmod 755 "$RC"
            rc-update add unblocker default 2>/dev/null
            log "openrc service installed and added to default runlevel"
            ;;
        remove)  rc-update del unblocker default 2>/dev/null; rm -f "$RC"
                 log "openrc service removed" ;;
        start)   rc-service unblocker start ;;
        stop)    rc-service unblocker stop ;;
        restart) rc-service unblocker restart ;;
        status)  rc-service unblocker status ;;
        enable)  rc-update add unblocker default ;;
        disable) rc-update del unblocker default ;;
    esac
}

# ── backend: none (manual) ─────────────────────────────────────────────
sv_none() {
    case "$ACTION" in
        install) log "no service manager selected — daemon is started manually:"
                 log "  RUST_LOG=info $EXEC_BIN daemon &" ;;
        start)   manual_start ;;
        stop)    manual_stop ;;
        restart) manual_stop; manual_start ;;
        status)  if manual_running; then log "running (pid $(cat "$PIDFILE"))"
                 else log "not running"; fi ;;
        enable|disable|remove)
                 warn "mode 'none': use manual start/stop" ;;
    esac
}

# ── dispatch ───────────────────────────────────────────────────────────
case "$INIT_MODE" in
    systemd) sv_systemd ;;
    sysvinit|puppy) sv_sysv ;;
    runit)   sv_runit ;;
    openrc)  sv_openrc ;;
    none)    sv_none ;;
    auto)    die "auto-detection failed; pass --init=systemd|sysv|runit|openrc|none" ;;
    *)       die "unknown init mode: $INIT_MODE" ;;
esac
