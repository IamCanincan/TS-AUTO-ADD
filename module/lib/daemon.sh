#!/system/bin/sh
# daemon.sh - 防抖与守护管理

with_debounce() {
    local debounce_file="$TARGET_BASE/.debounce"
    local now=$(date +%s)
    if [ -f "$debounce_file" ]; then
        local last=$(cat "$debounce_file" 2>/dev/null || echo 0)
        [ $((now - last)) -lt "$DEBOUNCE_SECONDS" ] && { log_info "忽略重复事件"; return; }
    fi
    echo "$now" > "$debounce_file"
    acquire_lock "$TARGET_BASE" || { log_err "获取锁失败，放弃本次同步"; return; }
    do_sync
    release_lock "$TARGET_BASE"
}

show_status() {
    local pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    if [ -f "$pids_file" ]; then
        local pids=$(cat "$pids_file" 2>/dev/null | tr '\n' ' ')
        local alive=0
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