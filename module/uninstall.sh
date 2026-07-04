#!/system/bin/sh

# 终止可能正在运行的守护进程
PID_FILE="/data/adb/tricky_store/.ts_daemon.pid"
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null
    # 确保进程被终止
    sleep 0.3
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
fi

# 清理所有运行时产生的临时文件
rm -rf /data/adb/tricky_store/.ts_lock
rm -f /data/adb/tricky_store/.ts_daemon.pid
rm -f /data/adb/tricky_store/.ts_pending
rm -f /data/adb/tricky_store/.ts_tmp

# 注意：不要删除 target.txt，它是 Tricky Store 主模块的核心配置，
# 只清理本模块产生的辅助文件。

# 清理写入 service.d 的 resetprop 脚本
if [ -f "/data/adb/service.d/taa_resetprop.sh" ]; then
    rm -f /data/adb/service.d/taa_resetprop.sh
fi

exit 0