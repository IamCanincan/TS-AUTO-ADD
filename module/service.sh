#!/system/bin/sh
MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || exit 1

detect_target_env
env_status=$?
case $env_status in
    2) log_err "冲突：TrickyStore 与 TeeSimulator 同时存在"; update_module_prop "$PROP_FILE" "⛔ 已停止: 冲突"; exit 1 ;;
    3) log_err "未检测到目标环境"; update_module_prop "$PROP_FILE" "⛔ 已停止: 无环境"; exit 1 ;;
esac
[ "$TARGET_TYPE" = "TEESIM" ] && [ ! -f "$TARGET_BASE/config.json" ] && {
    log_err "TeeSimulator config.json 不存在"
    update_module_prop "$PROP_FILE" "⛔ 已停止: 缺少 config.json"
    exit 1
}

inotify_info="$(find_inotify_cmd)"
[ -z "$inotify_info" ] && { log_err "inotify 工具不可用"; update_module_prop "$PROP_FILE" "⛔ 已停止: inotify 不可用"; exit 1; }
inotify_mode="${inotify_info%%:*}"
inotify_cmd="${inotify_info#*:}"

# 清理残留
rm -f "$TARGET_BASE/.ts_tmp" "$TARGET_BASE/.lock" "$TARGET_BASE/.debounce" 2>/dev/null
pids_file="$TARGET_BASE/.ts_daemon_pids.list"
[ -f "$pids_file" ] && { while read -r pid; do kill -9 "$pid" 2>/dev/null; done < "$pids_file"; rm -f "$pids_file"; }

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
log_info "系统已启动，执行首次同步"
with_debounce

# 监控 packages.list 变化
(
    while true; do
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e close_write --exclude ".*\\.tmp$" "$WATCH_DIR" 2>/dev/null | while read -r line; do
                case "$line" in *packages.list*) with_debounce ;; esac
            done
        else
            $inotify_cmd - "$WATCH_DIR:wc" 2>/dev/null | while read -r event file; do
                case "$file" in *packages.list*) with_debounce ;; esac
            done
        fi
        sleep 3
    done
) &
pid1=$!

# 监控 taa_sys.txt 变化
(
    while true; do
        ensure_taa_sys "$TAA_SYS_FILE"
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e close_write "$TAA_SYS_FILE" 2>/dev/null | while read -r line; do
                with_debounce
            done
        else
            $inotify_cmd - "$TAA_SYS_FILE:wc" 2>/dev/null | while read -r line; do
                with_debounce
            done
        fi
        sleep 3
    done
) &
pid2=$!

echo "$pid1" > "$pids_file"
echo "$pid2" >> "$pids_file"
log_info "守护进程已启动 (PID: $pid1, $pid2)"
exit 0