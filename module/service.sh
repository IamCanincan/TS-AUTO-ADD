#!/system/bin/sh
#=============================================================================
# service.sh - 事件驱动后台守护（无联网 · 省电 · 双后端）
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
WATCH_DIR="/data/system"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || exit 1

# ---------- 后端探测（TEE Simulator 优先，其与 Tricky Store 互斥） ----------
detect_backend

TMP="${TAA_DIR}/.ts_tmp"
LOCK_DIR="${TAA_DIR}/.ts_lock"
DEBOUNCE_LOCK="${TAA_DIR}/.ts_debounce"
PIDS_FILE="${TAA_DIR}/.ts_daemon_pids.list"
FP_FILE="${TAA_DIR}/.ts_fingerprint"

log_info "后端: $(backend_name)（目录: $TAA_DIR）"
if [ "$TAA_BACKEND" = "teesim" ] && [ -z "$AWK_CMD" ]; then
    log_warn "未找到 awk，暂时无法维护 TEE Simulator 配置（install busybox 后会自动重试）"
fi

# ---------- inotify 依赖检查 ----------
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    log_err "未找到 inotify 工具，服务退出。"
    exit 1
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
log_info "初始化 inotify: ${INOTIFY_CMD%% *} (模式: $INOTIFY_MODE)"

# ---------- 变更检测 ----------
# 以 packages.list 的包名集合 + rules.txt 生成指纹，仅在真正发生
# 安装/卸载或常驻列表变化时才执行同步，避免系统频繁改写 packages.list 造成无谓刷新。
get_source_fingerprint() {
    local pkgs=$(cut -d' ' -f1 "$WATCH_DIR/packages.list" 2>/dev/null | sort -u)
    local rules=$(sed '/^$/d' "$RULES_FILE" 2>/dev/null | sort -u)
    printf '%s\n%s\n' "$pkgs" "$rules" | cksum 2>/dev/null | cut -d' ' -f1
}

# ---------- 同步核心 ----------
do_sync() {
    local fp=$(get_source_fingerprint)
    if [ -n "$fp" ] && [ "$fp" = "$(cat "$FP_FILE" 2>/dev/null)" ]; then
        return 0
    fi

    log_info "开始应用列表同步..."
    run_sync "$PROP_FILE" "$TMP"
    local rc=$?
    case "$rc" in
        0) log_info "同步完成。应用总数: $TAA_COUNT" ;;
        2) log_warn "同步失败：未能生成或写入应用列表" ;;
    esac
    # 仅在成功（已写入或确认一致）时记录指纹；失败时不记录，便于下次重试
    if [ "$rc" != "2" ] && [ -n "$fp" ]; then
        echo "$fp" > "$FP_FILE" 2>/dev/null
    fi
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

# ---------- 事件监听（合并监听系统包列表与常驻列表，单进程） ----------
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        ensure_rules_file "$RULES_FILE"
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete "$WATCH_DIR" "$RULES_FILE" 2>/dev/null \
            | while read -r line; do
                case "$line" in
                    *packages.list*|*rules.txt*) dispatch_sync ;;
                esac
            done
        else
            $INOTIFY_CMD - "$WATCH_DIR:wc" "$RULES_FILE:wc" 2>/dev/null \
            | while read -r _ev file; do
                case "$file" in
                    *packages.list*|*rules.txt*) dispatch_sync ;;
                esac
            done
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

log_info "守护进程就绪，主进程退出"
exit 0
