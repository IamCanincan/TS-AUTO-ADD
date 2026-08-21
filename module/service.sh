#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 后台守护进程（监控包变化并自动同步）
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

tmp_file="$target_base/.ts_tmp"
lock_dir="$target_base/.ts_lock"
debounce_lock="$target_base/.ts_debounce"
pids_file="$target_base/.ts_daemon_pids.list"

inotify_info=$(find_inotify_cmd)
[ -z "$inotify_info" ] && { log_err "inotify 工具不可用" ; exit 1; }
inotify_mode="${inotify_info%%:*}"
inotify_cmd="${inotify_info#*:}"
log_info "目标环境: $target_type，监控工具: ${inotify_cmd%% *}"

# 清理残留文件
rm -rf "$tmp_file" "$lock_dir" "$debounce_lock" 2>/dev/null
# 清理旧的后台进程（如果存在记录）
if [ -f "$pids_file" ]; then
    while read -r pid; do
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    done < "$pids_file"
    rm -f "$pids_file" 2>/dev/null
fi

# ---------- 核心同步函数 ----------
do_sync() {
    log_info "开始同步包列表"
    mkdir -p "$target_base" 2>/dev/null
    ensure_taa_sys "$taa_sys_file"

    local apps_raw
    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    local user_list
    user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
    local user_count
    user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
    local sys_count
    sys_count=$(cat "$taa_sys_file" 2>/dev/null | sed '/^$/d' | wc -l)

    {
        cat "$taa_sys_file" 2>/dev/null
        echo "$user_list"
    } | sort -u | sed '/^$/d' > "$tmp_file" 2>/dev/null

    if [ -s "$tmp_file" ]; then
        write_target_config "$tmp_file"
        log_info "同步完成，系统白名单: $sys_count，第三方应用: $user_count"
    else
        log_warn "同步失败：应用列表为空"
    fi
    rm -f "$tmp_file" 2>/dev/null

    local current_time
    current_time=$(date '+%H:%M')
    update_module_prop "$PROP_FILE" "[环境: ${target_type} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
}

# ---------- 带防抖的同步调度 ----------
dispatch_sync() {
    # 尝试获取防抖锁，如果已存在则忽略本次事件
    if mkdir "$debounce_lock" 2>/dev/null; then
        (
            # 在子进程中执行同步，并释放防抖锁
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
until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do
    sleep 2
done

log_info "系统已启动，执行首次同步"
dispatch_sync

# ---------- 启动 inotify 监控 ----------
# 使用 while 循环确保 inotify 进程崩溃后自动重启
(
    while true; do
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e modify -e create -e delete "$WATCH_DIR" 2>/dev/null | while read -r line; do
                case "$line" in *packages.list*) dispatch_sync ;; esac
            done
        else
            $inotify_cmd - "$WATCH_DIR:wc" 2>/dev/null | while read -r event file; do
                case "$file" in *packages.list*) dispatch_sync ;; esac
            done
        fi
        sleep 3
    done
) &
pid1=$!

(
    while true; do
        ensure_taa_sys "$taa_sys_file"
        if [ "$inotify_mode" = "inotifywait" ]; then
            $inotify_cmd -m -e modify -e create -e delete "$taa_sys_file" 2>/dev/null | while read -r line; do
                dispatch_sync
            done
        else
            $inotify_cmd - "$taa_sys_file:wc" 2>/dev/null | while read -r line; do
                dispatch_sync
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