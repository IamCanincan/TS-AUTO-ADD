#!/system/bin/sh
#====================================================
# 卸载清理脚本
# 功能：终止后台守护进程，删除PID文件和临时文件
#====================================================

BASE="/data/adb/tricky_store"

for item in b1 b2 patch; do
    PID_FILE="$BASE/.ts_daemon_${item}.pid"
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            sleep 0.1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
done

# 清理锁文件、临时文件和缓存
rm -rf "$BASE/.ts_lock" "$BASE/.ts_pending" "$BASE/.ts_tmp" "$BASE/.last_month"
rm -f "$BASE/security_patch.txt.bak" "/data/adb/service.d/taa_resetprop.sh"

exit 0