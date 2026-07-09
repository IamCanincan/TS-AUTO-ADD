#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 卸载清理脚本
#=============================================================================

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
PIDS_FILE="$TS_BASE/.ts_daemon_pids.list"

# 终止已建立的后台守护进程
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.1
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi

# 清理挂起的进程实例
pkill -f "inotifyd.*$TS_BASE" 2>/dev/null
pkill -f "inotifywait.*$TS_BASE" 2>/dev/null
pkill -f "inotifyd.*$TEESIM_BASE" 2>/dev/null
pkill -f "inotifywait.*$TEESIM_BASE" 2>/dev/null

# 移除运行锁及数据缓存文件
rm -rf "$TS_BASE/.ts_lock" "$TS_BASE/.ts_debounce" "$TS_BASE/.ts_tmp" 2>/dev/null
rm -f "$TS_BASE/target.txt" "$TS_BASE/taa_sys.txt" 2>/dev/null
rm -f "$TEESIM_BASE/config.json" 2>/dev/null
rm -f "/data/adb/ts_auto.log" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0