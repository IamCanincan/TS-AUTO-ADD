#!/system/bin/sh
#====================================================
# 卸载清理脚本
# 功能：终止后台进程，删除 PID 文件和临时文件
#====================================================
BASE="/data/adb/tricky_store"
MAIN_PID_FILE="$BASE/.ts_daemon_main.pid"

# 终止主进程并等待退出
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

# 清理残留 PID 文件
for item in b1 b2 patch; do
    PID_FILE="$BASE/.ts_daemon_${item}.pid"
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
done

# 删除锁、临时文件和备份
rm -rf "$BASE/.ts_lock" "$BASE/.ts_pending" "$BASE/.ts_tmp" "$BASE/.last_month"
rm -f "$BASE/security_patch.txt.bak" "/data/adb/service.d/taa_resetprop.sh"

exit 0