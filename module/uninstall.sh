#!/system/bin/sh
MODDIR="${0%/*}"
[ -f "$MODDIR/lib/common.sh" ] && . "$MODDIR/lib/common.sh" 2>/dev/null

pkill -f "ts-auto-add" 2>/dev/null
pkill -f "inotifywait.*tricky_store" 2>/dev/null
pkill -f "inotifyd.*tricky_store" 2>/dev/null
pkill -f "inotifywait.*teesim" 2>/dev/null
pkill -f "inotifyd.*teesim" 2>/dev/null

if type update_module_prop >/dev/null 2>&1 && [ -f "$PROP_FILE" ]; then
    uninstall_time="$(date '+%H:%M')"
    update_module_prop "$PROP_FILE" "🗑️ 已卸载 (时间: ${uninstall_time})"
fi

for base in "$TS_BASE" "$TEESIM_BASE"; do
    [ -d "$base" ] && rm -f "$base/.ts_tmp" "$base/.lock_dir" "$base/.debounce" "$base/.ts_daemon_pids.list" "$base/taa_sys.txt"
done

rm -f "/data/adb/ts_auto.log" "/data/adb/ts_auto.log.old" 2>/dev/null
rm -f "/data/adb/ts-sync" 2>/dev/null
exit 0