#!/system/bin/sh
# 设置日志路径
LOG_FILE="/data/adb/ts_auto.log"
log_force() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}
log_force "========== TS-AUTO-ADD 服务启动 =========="
log_force "PID: $$, 时间: $(date)"

MODDIR="${0%/*}"
export MODDIR
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 加载 common.sh
if [ -f "$MODDIR/lib/common.sh" ]; then
    log_force "加载 common.sh..."
    . "$MODDIR/lib/common.sh" 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        log_force "common.sh 加载成功"
    else
        log_force "common.sh 加载失败"
        # 定义最小函数集（略）
        exit 1
    fi
else
    log_force "common.sh 不存在"
    exit 1
fi

# 清理残留
[ -n "$TARGET_BASE" ] && {
    rm -f "$TARGET_BASE/.ts_tmp" "$TARGET_BASE/.lock_dir" "$TARGET_BASE/.debounce" 2>/dev/null
    pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    [ -f "$pids_file" ] && { while read -r pid; do kill -9 "$pid" 2>/dev/null; done < "$pids_file"; rm -f "$pids_file"; }
}

# 等待系统启动
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
log_info "系统已启动"

# 启动守护进程（循环重试）
while true; do
    detect_target_env
    env_status=$?
    case $env_status in
        2) log_err "冲突"; sleep 10; continue ;;
        3) log_err "无环境"; sleep 10; continue ;;
    esac
    inotify_info="$(find_inotify_cmd)"
    [ -z "$inotify_info" ] && { log_err "无inotify"; sleep 10; continue; }
    inotify_mode="${inotify_info%%:*}"
    inotify_cmd="${inotify_info#*:}"

    log_info "执行首次同步"
    with_debounce

    # 启动两个监控进程
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

    pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    echo "$pid1" > "$pids_file"
    echo "$pid2" >> "$pids_file"
    log_info "守护进程已启动 (PID: $pid1, $pid2)"
    update_module_prop "$PROP_FILE" "✅ 运行中 (环境: ${TARGET_TYPE})"
    break
done

log_force "service.sh 正常退出"
exit 0