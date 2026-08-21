#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 卸载清理脚本
#=============================================================================

ts_base="/data/adb/tricky_store"
teesim_base="/data/adb/teesim"

# 终止所有相关后台进程（包括 inotify 及子进程）
pkill -f "inotifyd.*$ts_base" 2>/dev/null
pkill -f "inotifywait.*$ts_base" 2>/dev/null
pkill -f "inotifyd.*$teesim_base" 2>/dev/null
pkill -f "inotifywait.*$teesim_base" 2>/dev/null
pkill -f "ts-auto-add" 2>/dev/null

# 删除模块生成的临时文件及配置文件（保留用户数据？根据原始脚本，这些是模块产生的，应删除）
rm -rf "$ts_base/.ts_lock" "$ts_base/.ts_debounce" "$ts_base/.ts_tmp" "$ts_base/taa_sys.txt" "$ts_base/.ts_daemon_pids.list" 2>/dev/null
rm -rf "$teesim_base/.ts_lock" "$teesim_base/.ts_debounce" "$teesim_base/.ts_tmp" "$teesim_base/taa_sys.txt" "$teesim_base/.ts_daemon_pids.list" 2>/dev/null

# 删除日志文件及部署的 resetprop 脚本
rm -f "/data/adb/ts_auto.log" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0