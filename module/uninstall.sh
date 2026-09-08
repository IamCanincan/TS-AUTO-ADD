#!/system/bin/sh
# 停止守护进程与 watcher，清理运行时文件
RUNDIR="/data/adb/ts_auto_runtime"

for f in "$RUNDIR/daemon.pid" "$RUNDIR/watcher.pid"; do
    [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null
done
rm -rf "$RUNDIR" 2>/dev/null
rm -f "/data/adb/ts_auto.log" "/data/adb/ts_auto.log.old" "/data/adb/ts-sync" 2>/dev/null

ui_print "✅ TS-AUTO-ADD 已卸载"
exit 0
