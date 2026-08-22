#!/system/bin/sh
#==============================================================================
# 文件: uninstall.sh
# 描述: 卸载 TS-AUTO-ADD 模块时的清理脚本，终止进程并删除临时文件
#==============================================================================

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"

# 终止所有与此模块相关的后台进程
pkill -f "inotifyd.*$TS_BASE" 2>/dev/null
pkill -f "inotifywait.*$TS_BASE" 2>/dev/null
pkill -f "inotifyd.*$TEESIM_BASE" 2>/dev/null
pkill -f "inotifywait.*$TEESIM_BASE" 2>/dev/null
pkill -f "ts-auto-add" 2>/dev/null

# 删除模块生成的临时文件和配置文件（保留用户自定义的 target.txt 或 config.json？但根据设计，taa_sys.txt 和锁文件是模块生成的，仅移除这些）
rm -rf "$TS_BASE/.ts_lock" "$TS_BASE/.ts_debounce" "$TS_BASE/.ts_tmp" "$TS_BASE/taa_sys.txt" "$TS_BASE/.ts_daemon_pids.list" 2>/dev/null
rm -rf "$TEESIM_BASE/.ts_lock" "$TEESIM_BASE/.ts_debounce" "$TEESIM_BASE/.ts_tmp" "$TEESIM_BASE/taa_sys.txt" "$TEESIM_BASE/.ts_daemon_pids.list" 2>/dev/null

# 删除日志文件和软链接
rm -f "/data/adb/ts_auto.log" "/data/adb/ts_auto.log.old" 2>/dev/null
rm -f "/data/adb/ts-sync" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null

exit 0