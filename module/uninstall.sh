#!/system/bin/sh

# 终止可能正在运行的守护进程（主监控进程）
PID_FILE="/data/adb/tricky_store/.ts_daemon.pid"
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null
    sleep 0.3
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
fi

# 终止补丁更新进程（独立的后台循环）
PATCH_PID_FILE="/data/adb/tricky_store/.ts_patch.pid"
if [ -f "$PATCH_PID_FILE" ]; then
    pid=$(cat "$PATCH_PID_FILE")
    kill "$pid" 2>/dev/null
    sleep 0.3
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    rm -f "$PATCH_PID_FILE"
fi

# 清理所有运行时产生的临时文件及锁
rm -rf /data/adb/tricky_store/.ts_lock
rm -f /data/adb/tricky_store/.ts_pending
rm -f /data/adb/tricky_store/.ts_tmp

# 清理补丁日期抓取产生的缓存与备份文件
rm -f /data/adb/tricky_store/.last_month
rm -f /data/adb/tricky_store/security_patch.txt.bak

# 清理写入 service.d 的 resetprop 脚本
if [ -f "/data/adb/service.d/taa_resetprop.sh" ]; then
    rm -f /data/adb/service.d/taa_resetprop.sh
fi

exit 0