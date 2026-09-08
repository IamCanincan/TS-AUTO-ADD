#!/system/bin/sh
#=============================================================================
# service.sh - 事件驱动后台守护（无联网 · 省电）
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_DIR="/data/system"

TMP="${BASE}/.ts_tmp"
LOCK_DIR="${BASE}/.ts_lock"
DEBOUNCE_LOCK="${BASE}/.ts_debounce"

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

# ---------- 同步核心（应用列表 + 描述） ----------
do_sync() {
    log_info "开始应用列表同步..."
    sync_target_list "$BASE" "$TARGET" "$TMP"
    local rc=$?
    case "$rc" in
        0) log_info "同步完成。系统应用: $TAA_SYS_COUNT，用户应用: $TAA_USER_COUNT" ;;
        2) log_warn "未能获取本地包名列表" ;;
    esac
    update_module_desc "$PROP_FILE" "$TAA_SYS_COUNT" "$TAA_USER_COUNT"
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

# ---------- 事件监听（合并监听系统包列表与白名单文件，单进程） ----------
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        ensure_taa_sys "$TAA_SYS_FILE"
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete "$WATCH_DIR" "$TAA_SYS_FILE" 2>/dev/null \
            | while read -r line; do
                case "$line" in
                    *packages.list*|*taa_sys.txt*) dispatch_sync ;;
                esac
            done
        else
            $INOTIFY_CMD - "$WATCH_DIR:wc" "$TAA_SYS_FILE:wc" 2>/dev/null \
            | while read -r _ev file; do
                case "$file" in
                    *packages.list*|*taa_sys.txt*) dispatch_sync ;;
                esac
            done
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

log_info "守护进程就绪，主进程退出"
exit 0
