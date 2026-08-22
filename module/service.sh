#!/system/bin/sh
MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || exit 1

# 清理残留
rm -f "$TARGET_BASE/.ts_tmp" "$TARGET_BASE/.lock_dir" "$TARGET_BASE/.debounce" 2>/dev/null
pids_file="$TARGET_BASE/.ts_daemon_pids.list"
[ -f "$pids_file" ] && { while read -r pid; do kill -9 "$pid" 2>/dev/null; done < "$pids_file"; rm -f "$pids_file"; }

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
log_info "系统已启动，准备初始化"

# 定义一个函数，用于尝试启动守护进程
start_daemon() {
    # 检测环境（可能多次尝试）
    detect_target_env
    local env_status=$?
    case $env_status in
        2) log_err "冲突：TrickyStore 与 TeeSimulator 同时存在"; return 1 ;;
        3) log_err "未检测到目标环境"; return 1 ;;
    esac

    [ "$TARGET_TYPE" = "TEESIM" ] && [ ! -f "$TARGET_BASE/config.json" ] && {
        log_err "TeeSimulator config.json 不存在"
        return 1
    }

    inotify_info="$(find_inotify_cmd)"
    [ -z "$inotify_info" ] && { log_err "inotify 工具不可用"; return 1; }
    inotify_mode="${inotify_info%%:*}"
    inotify_cmd="${inotify_info#*:}"

    # 执行首次同步
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

    echo "$pid1" > "$pids_file"
    echo "$pid2" >> "$pids_file"
    log_info "守护进程已启动 (PID: $pid1, $pid2)"
    update_module_prop "$PROP_FILE" "✅ 运行中 (环境: ${TARGET_TYPE})"
    return 0
}

# 循环尝试启动，直到成功
while true; do
    if start_daemon; then
        break
    else
        log_warn "初始化失败，等待 10 秒后重试..."
        sleep 10
    fi
done

exit 0