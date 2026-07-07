#!/system/bin/sh
#====================================================
# 卸载清理脚本 (优化版)
#====================================================

BASE="/data/adb/tricky_store"
PIDS_FILE="$BASE/.ts_daemon_pids.list"

# 优雅击杀所有记录的守护子进程
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        if [ -n "$pid" ]; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.1
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi

# 双重保险：清理残留的 inotify 进程
pkill -f "inotifyd.*$BASE" 2>/dev/null
pkill -f "inotifywait.*$BASE" 2>/dev/null

# 清理所有临时工作锁和遗留缓存
rm -rf "$BASE/.ts_lock" "$BASE/.ts_debounce" "$BASE/.ts_tmp" 2>/dev/null
rm -f "$BASE/.last_month" "$BASE/security_patch.txt.bak" 2>/dev/null

rm -f "/data/local/tmp/ts_auto.log" 2>/dev/null
rm -f "$BASE/taa_sys.txt" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0