#!/system/bin/sh
#=============================================================================
# service.sh - 事件驱动后台守护
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_DIR="/data/system"

TMP="${BASE}/.ts_tmp"
LOCK_DIR="${BASE}/.ts_lock"
DEBOUNCE_LOCK="${BASE}/.ts_debounce"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_CACHE_FILE="$BASE/.last_month"
PIDS_FILE="${BASE}/.ts_daemon_pids.list"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || exit 1

# ---------- inotify 依赖检查 ----------
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    log_err "未找到 inotify 工具，服务退出。"
    exit 1
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
log_info "初始化 inotify: ${INOTIFY_CMD%% *} (模式: $INOTIFY_MODE)"

# ---------- 列表同步核心 ----------
do_sync() {
    log_info "开始应用列表同步..."
    mkdir -p "$BASE" 2>/dev/null
    ensure_taa_sys "$TAA_SYS_FILE"

    local apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    local user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
    local user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
    local sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

    # 通过输出流合并数据
    (cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null

    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET" 2>/dev/null; then
            mv -f "$TMP" "$TARGET" 2>/dev/null
            chmod 644 "$TARGET" 2>/dev/null
            log_info "同步完成。系统应用: $sys_count，用户应用: $user_count"
        else
            rm -f "$TMP" 2>/dev/null
        fi
    else
        rm -f "$TMP" 2>/dev/null
    fi

    # 描述文件更新
    local patch_desc=$(get_patch_details "$PATCH_CONFIG_FILE")
    local current_time=$(date '+%H:%M')
    local new_desc="[系统: ${sys_count} | 用户: ${user_count} | 补丁: ${patch_desc} | 更新: ${current_time}]"
    update_module_prop "$PROP_FILE" "$new_desc"
}

# 防抖调度控制 (延迟: 2秒)
dispatch_sync() {
    if mkdir "$DEBOUNCE_LOCK" 2>/dev/null; then
        (
            sleep 2
            rmdir "$DEBOUNCE_LOCK" 2>/dev/null
            acquire_lock "$LOCK_DIR" || exit 1
            do_sync
            release_lock "$LOCK_DIR"
        ) &
    fi
}

# ---------- 状态重置 ----------
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        # 验证进程有效性后关闭
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi
rm -rf "$TMP" "$LOCK_DIR" "$DEBOUNCE_LOCK" 2>/dev/null

until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done

log_info "启动阶段检测完成，执行首次同步"
dispatch_sync

# ---------- 守护进程任务 ----------
# 任务1: 安全补丁更新 (周期任务)
(
    while true; do
        if is_network_available; then
            update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
            do_sync
            sleep 21600
        else
            log_info "网络状态不可用，推迟补丁更新"
            sleep 43200
        fi
    done
) &
echo $! >> "$PIDS_FILE"

start_inotifywait_monitor() {
    local cmd="$1" watch_path="$2"
    $cmd -m -e modify -e create -e delete "$watch_path" 2>/dev/null | while read -r line; do
        case "$line" in *packages.list*) dispatch_sync ;; esac
    done
}

start_inotifyd_monitor() {
    local cmd="$1" watch_path="$2"
    $cmd - "$watch_path:wc" 2>/dev/null | while read -r event file; do
        case "$file" in *packages.list*) dispatch_sync ;; esac
    done
}

# 任务2: 系统文件变更监控
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            start_inotifywait_monitor "$INOTIFY_CMD" "$WATCH_DIR"
        else
            start_inotifyd_monitor "$INOTIFY_CMD" "$WATCH_DIR"
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

# 任务3: 模块配置文件变更监控
(
    while true; do
        ensure_taa_sys "$TAA_SYS_FILE"
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete "$TAA_SYS_FILE" 2>/dev/null | while read -r line; do
                dispatch_sync
            done
        else
            $INOTIFY_CMD - "$TAA_SYS_FILE:wc" 2>/dev/null | while read -r line; do
                dispatch_sync
            done
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

log_info "守护进程就绪，主进程退出"
exit 0