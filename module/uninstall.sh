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
    rm -f "$MAIN_PID_FILE" 2>/dev/null
fi

for item in b1 b2 patch; do
    PID_FILE="$BASE/.ts_daemon_${item}.pid"
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
        rm -f "$PID_FILE" 2>/dev/null
    fi
done

# 清理所有可能残留的 inotifyd 进程（针对本模块）
pkill -f "inotifyd.*$BASE" 2>/dev/null

rm -rf "$BASE/.ts_lock" "$BASE/.ts_pending" "$BASE/.ts_tmp" 2>/dev/null
rm -f "$BASE/.last_month" "$BASE/security_patch.txt.bak" 2>/dev/null

# 删除日志
rm -f "/data/local/tmp/ts_auto.log" 2>/dev/null

# 删除白名单文件
rm -f "$BASE/taa_sys.txt" 2>/dev/null

# 删除属性注入脚本
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0