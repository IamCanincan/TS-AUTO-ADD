#!/system/bin/sh
# 卸载清理
RUNDIR="/data/adb/ts_auto"
PID_FILE="$RUNDIR/.ts_daemon.pid"

# 停止守护进程
[ -f "$PID_FILE" ] && kill -TERM "$(cat "$PID_FILE")" 2>/dev/null

# 清理可能残留的 inotify 监听进程
pkill -f "inotifywait.*/data/system" 2>/dev/null
pkill -f "inotifywait.*$RUNDIR" 2>/dev/null
pkill -f "inotifyd.*/data/system" 2>/dev/null
pkill -f "inotifyd.*$RUNDIR" 2>/dev/null

# 清理模块运行时目录（含白名单、日志、锁、临时文件）
rm -rf "$RUNDIR" 2>/dev/null

# 清理旧版寄生在 /data/adb/tricky_store 的残留
rm -rf /data/adb/tricky_store/.ts_tmp /data/adb/tricky_store/.ts_lock /data/adb/tricky_store/.ts_debounce 2>/dev/null
rm -f /data/adb/tricky_store/.ts_daemon.pid /data/adb/tricky_store/.ts_daemon_pids.list /data/adb/tricky_store/.events.fifo 2>/dev/null
rm -f /data/local/tmp/ts_auto.log /data/adb/ts_auto.log /data/adb/service.d/taa_resetprop.sh 2>/dev/null

exit 0
