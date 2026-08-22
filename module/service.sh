#!/system/bin/sh
#==============================================================================
# 文件: service.sh
# 描述: TS-AUTO-ADD 后台守护进程，使用 inotify 监控文件变化并自动同步
# 启动: 由 Magisk 在系统启动后通过 service 脚本执行
#==============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
WATCH_DIR="/data/system"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || exit 1

# ----------------------------- 环境检测 ------------------------------------
detect_target_env
env_status=$?
case $env_status in
    2) log_err "冲突：TrickyStore 与 TeeSimulator 同时存在" ; exit 1 ;;
    3) log_err "未检测到目标环境" ; exit 1 ;;
esac

# 定义路径变量
tmp_file="$TARGET_BASE/.ts_tmp"
lock_dir="$TARGET_BASE/.ts_lock"
debounce_lock="$TARGET_BASE/.ts_debounce"
pids_file="$TARGET_BASE/.ts_daemon_pids.list"

# 查找 inotify 工具
inotify_info="$(find_inotify_cmd)"
[ -z "$inotify_info" ] && { log_err "inotify 工具不可用" ; exit 1; }
inotify_mode="${inotify_info%%:*}"
inotify_cmd="${inotify_info#*:}"
log_info "目标环境: $TARGET_TYPE，监控工具: ${inotify_cmd%% *}"

# 清理旧文件（避免残留影响）
rm -rf "$tmp_file" "$lock_dir" "$debounce_lock" 2>/dev/null
[ -f "$pids_file" ] && {
    while read -r pid; do
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    done < "$pids_file"
    rm -f "$pids_file" 2>/dev/null
}

# ----------------------------- 同步核心函数 --------------------------------
# 功能: 执行一次完整的同步操作，包括获取应用列表、合并、写入配置、更新描述
do_sync() {
    log_info "开始同步包列表"
    ensure_taa_sys "$TAA_SYS_FILE"
    local user_list="$(get_installed_packages)"
    local user_count="$(count_lines "$user_list")"
    local sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"

    # 若用户列表为空，跳过本次同步（避免覆盖有效配置）
    if [ "$user_count" -eq 0 ]; then
        log_warn "第三方应用列表为空，跳过本次同步（可能系统未就绪）"
        return
    fi

    merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
    if [ -s "$tmp_file" ]; then
        write_target_config "$tmp_file"
        log_info "同步完成，系统白名单: $sys_count，第三方应用: $user_count"
    else
        log_warn "同步失败：合并结果为空"
    fi
    rm -f "$tmp_file" 2>/dev/null

    local current_time="$(date '+%H:%M')"
    update_module_prop "$PROP_FILE" "[环境: ${TARGET_TYPE} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
}

# ----------------------------- 防抖调度 ------------------------------------
# 功能: 在短时间内多次触发时，仅执行一次同步（防抖），避免频繁 IO
with_debounce() {
    if mkdir "$debounce_lock" 2>/dev/null; then
        (
            # 确保在任何退出情况下删除防抖锁
            trap 'rmdir "$debounce_lock" 2>/dev/null' EXIT
            acquire_lock "$lock_dir" || exit 1
            do_sync
            release_lock "$lock_dir"
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

# ----------------------------- 启动监控任务 --------------------------------
# 任务1: 监控 /data/system/packages.list 变化
(
    error_count=0
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
        # 监控进程退出时，记录错误计数并延迟重启
        error_count=$((error_count + 1))
        sleep $((error_count > 3 ? 10 : 3))
        log_warn "packages.list 监控异常退出，已重启 (错误次数: $error_count)"
    done
) &
pid1=$!

# 任务2: 监控 taa_sys.txt 变化
(
    error_count=0
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
        error_count=$((error_count + 1))
        sleep $((error_count > 3 ? 10 : 3))
        log_warn "taa_sys.txt 监控异常退出，已重启 (错误次数: $error_count)"
    done
) &
pid2=$!

# 保存 PID 以便卸载时清理
echo "$pid1" > "$pids_file"
echo "$pid2" >> "$pids_file"

log_info "守护进程已启动 (PID: $pid1, $pid2)"
exit 0