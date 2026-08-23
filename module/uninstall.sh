#!/system/bin/sh
MODDIR="${0%/*}"
RUNDIR="/data/adb/ts_auto_runtime"
PID_FILE="${RUNDIR}/daemon.pid"

[ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
rm -rf "$RUNDIR" 2>/dev/null
rm -f "/data/adb/ts_auto.log" "/data/adb/ts_auto.log.old" "/data/adb/ts-sync" 2>/dev/null

ui_print "✅ TS-AUTO-ADD 已卸载"
exit 0