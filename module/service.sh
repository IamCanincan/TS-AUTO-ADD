#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 后台守护进程
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
WATCH_DIR="/data/system"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || exit 1

# 环境检测
detect_target_env
env_status=$?
case $env_status in
    2) log_err "冲突：TrickyStore 与 TeeSimulator 同时存在" ; exit 1 ;;
    3) log_err "未检测到目标环境" ; exit 1 ;;
esac

tmp_file="$TARGET_BASE/.ts_tmp"
lock_dir="$TARGET_BASE/.ts_lock"
debounce_lock="$TARGET_BASE/.ts_debounce"
pids_file="$TARGET_BASE/.ts_daemon_pids.list"

inotify_info="$(find_inotify_cmd)"
[ -z "$inotify_info" ] && { log_err "inotify 工具不可用" ; exit 1; }
inotify_mode="${inotify_info%%:*}"
inotify_cmd="${inotify_info#*:}"
log_info "目标环境: $TARGET_TYPE，监控工具: ${inotify_cmd%% *}"

# 清理残留
rm -rf "$tmp_file" "$lock_dir" "$debounce_lock" 2>/dev/null
[ -f "$pids_file" ] && {
    while read -r pid; do
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    done < "$pids_file"
    rm -f "$pids_file" 2>/dev/null
}

# ---------- 同步核心函数 ----------
do_sync() {
    log_info "开始同步包列表"
    ensure_taa_sys "$TAA_SYS_FILE"
    local user_list="$(get_installed_packages)"
    local user_count="$(echo "$user_list" | wc -l)"
    local sys_count="$( [ -f "$TAA_SYS_FILE" ] && cat "$TAA_SYS_FILE" | sed '/^$/d' | wc -l || echo 0 )"

    merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
    if [ -s "$tmp_file" ]; then
        write_target_config "$tmp_file"
        log_info "同步完成，系统白名单: $sys_count，第三方应用: $user_count"
    else
        log_warn "同步失败：应用列表为空"
    fi
    rm -f "$tmp_file" 2>/dev/null

    local current_time="$(date '+%H:%M')"
    update_module_prop "$PROP_FILE" "[环境: ${TARGET_TYPE} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
}

# ---------- 防抖调度 ----------
with_debounce() {
    if mkdir "$debounce_lock" 2>/dev/null; then
        (
            acquire_lock "$lock_dir" || exit 1
            do_sync
            release_lock "$lock_dir"
            rmdir "$debounce_lock" 2>/dev/null
        ) &
    else
        log_info "同步已在排队，忽略本次事件"
    fi
}

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
log_info "系统已启动，执行首次同步"
with_debounce

# ---------- 启动 inotify 监控（两个任务） ----------
# 任务1：监听 /data/system/packages.list 变化
(
    while true; do
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e modify -e create -e delete "$WATCH_DIR" 2>/dev/null | while read -r line; do
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

# 任务2：监听 taa_sys.txt 变化
(
    while true; do
        ensure_taa_sys "$TAA_SYS_FILE"
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e modify -e create -e delete "$TAA_SYS_FILE" 2>/dev/null | while read -r line; do
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