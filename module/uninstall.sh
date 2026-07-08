#!/system/bin/sh
#====================================================
# 卸载清理脚本
#====================================================

BASE="/data/adb/tricky_store"
PIDS_FILE="$BASE/.ts_daemon_pids.list"

# 停止已记录的守护进程
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        # 验证进程是否仍然存活
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.1
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi

# 关闭可能存在的在后台挂起的 inotify 进程
pkill -f "inotifyd.*$BASE" 2>/dev/null
pkill -f "inotifywait.*$BASE" 2>/dev/null

# 移除模块生成的运行文件和目录
rm -rf "$BASE/.ts_lock" "$BASE/.ts_debounce" "$BASE/.ts_tmp" 2>/dev/null
rm -f "$BASE/.last_month" "$BASE/security_patch.txt.bak" 2>/dev/null
rm -f "/data/local/tmp/ts_auto.log" 2>/dev/null
rm -f "$BASE/taa_sys.txt" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0