#!/system/bin/sh
#====================================================
# 卸载清理脚本（双后端）
# 只删除本模块自己的文件；target.txt / config.json 属于后端，保持不动。
#====================================================

TS="/data/adb/tricky_store"
SIM="/data/adb/teesim"

# 停止已记录的守护进程（两个后端目录都可能存在 PID 文件）
for f in "$TS/.ts_daemon_pids.list" "$SIM/.ts_daemon_pids.list"; do
    [ -f "$f" ] || continue
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.1
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$f"
    rm -f "$f" 2>/dev/null
done

# 关闭可能存在的在后台挂起的 inotify 进程（命令行含 rules.txt）
pkill -f "inotifyd.*rules.txt" 2>/dev/null
pkill -f "inotifywait.*rules.txt" 2>/dev/null

# 移除模块自身的运行文件与常驻列表
rm -rf "$TS/.ts_lock" "$TS/.ts_debounce" "$TS/.ts_tmp" \
       "$SIM/.ts_lock" "$SIM/.ts_debounce" "$SIM/.ts_tmp" 2>/dev/null
rm -f "$TS/.ts_fingerprint" "$SIM/.ts_fingerprint" 2>/dev/null
rm -f "$TS/.last_month" "$TS/security_patch.txt.bak" 2>/dev/null
rm -f "$TS/rules.txt" "$SIM/rules.txt" "$TS/taa_sys.txt" 2>/dev/null
rm -f "/data/adb/ts_auto.log" "/data/local/tmp/ts_auto.log" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0
