#!/system/bin/sh
set +e  # 禁止任何错误导致脚本退出

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
        exit 1
    fi
else
    log_force "common.sh 不存在: $MODDIR/lib/common.sh"
    exit 1
fi

# 清理残留文件
[ -n "$TARGET_BASE" ] && {
    rm -f "$TARGET_BASE/.ts_tmp" "$TARGET_BASE/.lock_dir" "$TARGET_BASE/.debounce" 2>/dev/null
    pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    [ -f "$pids_file" ] && { while read -r pid; do kill -9 "$pid" 2>/dev/null; done < "$pids_file"; rm -f "$pids_file"; }
}

# 等待系统启动完成
log_force "等待 sys.boot_completed..."
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
    log_force "sys.boot_completed 未就绪，继续等待"
done
log_force "系统已启动"

# 主循环：尝试启动守护进程
while true; do
    log_info "尝试启动守护进程（循环）..."

    # 检测目标环境
    detect_target_env
    env_status=$?
    log_info "环境检测状态: $env_status"
    case $env_status in
        2) log_err "检测到 TrickyStore 与 TeeSimulator 冲突，等待 10 秒重试..."; sleep 10; continue ;;
        3) log_err "未检测到 TrickyStore 或 TeeSimulator，等待 10 秒重试..."; sleep 10; continue ;;
    esac
    log_info "目标环境: $TARGET_TYPE, 基础目录: $TARGET_BASE"

    # 检查 config.json（TeeSim 必须存在）
    if [ "$TARGET_TYPE" = "TEESIM" ] && [ ! -f "$TARGET_BASE/config.json" ]; then
        log_err "TeeSimulator config.json 不存在，等待 10 秒重试..."
        sleep 10
        continue
    fi

    # 检查 inotify
    inotify_info="$(find_inotify_cmd)"
    if [ -z "$inotify_info" ]; then
        log_err "inotify 工具不可用，等待 10 秒重试..."
        sleep 10
        continue
    fi
    inotify_mode="${inotify_info%%:*}"
    inotify_cmd="${inotify_info#*:}"
    log_info "inotify 模式: $inotify_mode, 命令: $inotify_cmd"

    # 执行首次同步
    log_info "执行首次同步..."
    with_debounce
    log_info "首次同步完成"

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
    break  # 启动成功，退出循环
done

log_force "service.sh 正常退出"
exit 0