# daemon.sh - 防抖与守护管理

with_debounce() {
    local lock_dir="$TARGET_BASE/.ts_lock"
    local debounce_lock="$TARGET_BASE/.ts_debounce"
    if mkdir "$debounce_lock" 2>/dev/null; then
        (
            trap 'rmdir "$debounce_lock" 2>/dev/null' EXIT
            acquire_lock "$lock_dir" || exit 1
            do_sync
            release_lock "$lock_dir"
        ) &
    else
        log_info "同步已在排队，忽略本次事件"
    fi
}

show_status() {
    local pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    if [ -f "$pids_file" ]; then
        pids=$(cat "$pids_file" 2>/dev/null | tr '\n' ' ')
        alive=0
        for pid in $pids; do
            kill -0 "$pid" 2>/dev/null && alive=1
        done
        if [ "$alive" -eq 1 ]; then
            echo "✅ 守护进程运行中，PID: $pids"
            echo "   目标环境: $TARGET_TYPE"
            if [ -f "$TARGET_BASE/target.txt" ]; then
                echo "   最后同步: $(stat -c %y "$TARGET_BASE/target.txt" 2>/dev/null)"
            elif [ -f "$TARGET_BASE/config.json" ]; then
                echo "   最后同步: $(stat -c %y "$TARGET_BASE/config.json" 2>/dev/null)"
            fi
        else
            echo "⚠️ PID 文件存在但进程未运行"
        fi
    else
        echo "⚠️ 守护进程未运行"
    fi
}

stop_daemon() {
    local pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    [ ! -f "$pids_file" ] && { echo "⚠️ 守护进程未运行"; return 0; }
    local pids=$(cat "$pids_file" 2>/dev/null | tr '\n' ' ')
    local stopped=0
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.5
            kill -9 "$pid" 2>/dev/null
            stopped=1
        fi
    done
    rm -f "$pids_file" 2>/dev/null
    if [ "$stopped" -eq 1 ]; then
        local stop_time="$(date '+%H:%M')"
        update_module_prop "$PROP_FILE" "⏹️ 已停止 (环境: ${TARGET_TYPE}) | 时间: ${stop_time}"
        echo "✅ 守护进程已停止"
    else
        echo "⚠️ 没有找到正在运行的守护进程"
    fi
}