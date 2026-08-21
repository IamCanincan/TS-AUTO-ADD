#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 卸载清理脚本
#=============================================================================

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"

# 终止相关后台进程与挂起的 inotify 实例
pkill -f "inotifyd.*$TS_BASE" 2>/dev/null
pkill -f "inotifywait.*$TS_BASE" 2>/dev/null
pkill -f "inotifyd.*$TEESIM_BASE" 2>/dev/null
pkill -f "inotifywait.*$TEESIM_BASE" 2>/dev/null

# 清理模块产生的缓存及运行文件
rm -rf "$TS_BASE/.ts_lock" "$TS_BASE/.ts_debounce" "$TS_BASE/.ts_tmp" "$TS_BASE/taa_sys.txt" "$TS_BASE/.ts_daemon_pids.list" 2>/dev/null
rm -rf "$TEESIM_BASE/.ts_lock" "$TEESIM_BASE/.ts_debounce" "$TEESIM_BASE/.ts_tmp" "$TEESIM_BASE/taa_sys.txt" "$TEESIM_BASE/.ts_daemon_pids.list" 2>/dev/null

rm -f "/data/adb/ts_auto.log" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0