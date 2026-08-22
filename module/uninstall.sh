#!/system/bin/sh
MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
if [ -f "$MODDIR/lib/common.sh" ]; then
    . "$MODDIR/lib/common.sh" 2>/dev/null
fi

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"

pkill -f "inotifyd.*$TS_BASE" 2>/dev/null
pkill -f "inotifywait.*$TS_BASE" 2>/dev/null
pkill -f "inotifyd.*$TEESIM_BASE" 2>/dev/null
pkill -f "inotifywait.*$TEESIM_BASE" 2>/dev/null
pkill -f "ts-auto-add" 2>/dev/null

if type update_module_prop >/dev/null 2>&1 && [ -f "$PROP_FILE" ]; then
    uninstall_time="$(date '+%H:%M')"
    update_module_prop "$PROP_FILE" "🗑️ 已卸载 (时间: ${uninstall_time})"
fi

rm -rf "$TS_BASE/.ts_lock" "$TS_BASE/.ts_debounce" "$TS_BASE/.ts_tmp" "$TS_BASE/taa_sys.txt" "$TS_BASE/.ts_daemon_pids.list" 2>/dev/null
rm -rf "$TEESIM_BASE/.ts_lock" "$TEESIM_BASE/.ts_debounce" "$TEESIM_BASE/.ts_tmp" "$TEESIM_BASE/taa_sys.txt" "$TEESIM_BASE/.ts_daemon_pids.list" 2>/dev/null
rm -f "/data/adb/ts_auto.log" "/data/adb/ts_auto.log.old" 2>/dev/null
rm -f "/data/adb/ts-sync" 2>/dev/null
rm -f "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
exit 0