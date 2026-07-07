#!/system/bin/sh
#====================================================
# 卸载清理脚本
#====================================================

BASE="/data/adb/tricky_store"
MAIN_PID_FILE="$BASE/.ts_daemon_main.pid"

if [ -f "$MAIN_PID_FILE" ]; then
    pid=$(cat "$MAIN_PID_FILE" 2>/dev/null)
    if [ -n "$pid" ]; then
        kill -TERM "$pid" 2>/dev/null
        for i in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$MAIN_PID_FILE"
fi

for item in b1 b2 patch; do
    PID_FILE="$BASE/.ts_daemon_${item}.pid"
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
done

rm -rf "$BASE/.ts_lock" "$BASE/.ts_pending" "$BASE/.ts_tmp"
rm -f "$BASE/.last_month" "$BASE/security_patch.txt.bak"

# 删除日志文件
rm -f "/data/local/tmp/ts_auto.log"

# 删除新目录下的 taa_sys.txt
rm -rf "/data/misc/ts_auto_add"
rm -f "$BASE/taa_sys.txt"

rm -f "/data/adb/service.d/taa_resetprop.sh"

exit 0