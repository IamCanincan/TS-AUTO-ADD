#!/system/bin/sh
#=============================================================================
# service.sh - 纯事件驱动后台守护
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

# ---------- 强制检测 inotify ----------
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    log_err "未找到 inotify 工具，该设备不支持事件驱动，服务退出。"
    exit 1
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
log_info "使用 inotify 工具: ${INOTIFY_CMD%% *} (模式: $INOTIFY_MODE)"

# ---------- 同步核心逻辑 ----------
do_sync() {
    log_info "执行列表同步..."
    mkdir -p "$BASE" 2>/dev/null
    ensure_taa_sys "$TAA_SYS_FILE"

    local apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    
    {
        cat "$TAA_SYS_FILE" 2>/dev/null
        echo ""
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET" 2>/dev/null; then
            mv -f "$TMP" "$TARGET" 2>/dev/null
            chmod 644 "$TARGET" 2>/dev/null
            log_info "同步完成，当前包数: $(wc -l < "$TARGET" 2>/dev/null || echo 0)"
        else
            rm -f "$TMP" 2>/dev/null
        fi
    else
        rm -f "$TMP" 2>/dev/null
    fi
    
    local app_count=$(wc -l < "$TARGET" 2>/dev/null || echo 0)
    local patch_date="未知"
    [ -f "$PATCH_CONFIG_FILE" ] && patch_date=$(grep '^boot=' "$PATCH_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
    [ -z "$patch_date" ] && patch_date="未配置"
    update_module_prop "$PROP_FILE" "[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
}

# 防抖调度 (窗口 2 秒)
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

# ---------- 初始化清理 ----------
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi
rm -rf "$TMP" "$LOCK_DIR" "$DEBOUNCE_LOCK" 2>/dev/null

# 等待系统启动完成
until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done

log_info "系统启动完毕，触发首次同步"
dispatch_sync

# ---------- 守护进程下发 ----------
# 任务1: 安全补丁自动更新 (6小时周期，非文件轮询)
(
    while true; do
        if is_network_available; then
            update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
            sleep 21600
        else
            log_info "网络不可用，补丁更新推迟至12小时后"
            sleep 43200
        fi
    done
) &
echo $! >> "$PIDS_FILE"

# 监控函数 (inotifywait)
start_inotifywait_monitor() {
    local cmd="$1"
    local watch_path="$2"
    $cmd -m -e modify -e create -e delete "$watch_path" 2>/dev/null | while read -r line; do
        case "$line" in
            *packages.list*) dispatch_sync ;;
        esac
    done
}

# 监控函数 (inotifyd)
start_inotifyd_monitor() {
    local cmd="$1"
    local watch_path="$2"
    $cmd - "$watch_path:wc" 2>/dev/null | while read -r event file; do
        case "$file" in
            *packages.list*) dispatch_sync ;;
        esac
    done
}

# 任务2: 监控 /data/system 目录 (捕获 packages.list 变更)
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            start_inotifywait_monitor "$INOTIFY_CMD" "$WATCH_DIR"
        else
            start_inotifyd_monitor "$INOTIFY_CMD" "$WATCH_DIR"
        fi
        sleep 3  # 仅用于子进程意外退出后的自愈重启，非轮询检测
    done
) &
echo $! >> "$PIDS_FILE"

# 任务3: 监控 taa_sys.txt 文件
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
        sleep 3  # 自愈重启
    done
) &
echo $! >> "$PIDS_FILE"

log_info "事件驱动守护进程组下发完毕，主进程退出。"
exit 0