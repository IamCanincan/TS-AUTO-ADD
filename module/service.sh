#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护（事件驱动 · 无联网）
#
# 职责：
#   1. 开机后执行一次同步并刷新模块描述
#   2. 单进程监听 /data/system/packages.list 与 rules.txt
#   3. 仅在源数据真正变化时同步（指纹比对 + 防抖）
#
# 说明：入口脚本由框架固定调用，必须位于模块根目录。
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
WATCH_DIR="/data/system"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || exit 1

# ---------- 后端探测 ----------
detect_backend "$MODDIR"

TMP="${TAA_DIR}/.ts_tmp"
LOCK_DIR="${TAA_DIR}/.ts_lock"
DEBOUNCE_LOCK="${TAA_DIR}/.ts_debounce"
PIDS_FILE="${TAA_DIR}/.ts_daemon_pids.list"
FP_FILE="${TAA_DIR}/.ts_fingerprint"

log_info "后端：$(backend_name)（目录：$TAA_DIR）"
if [ "$TAA_BACKEND" = "teesim" ] && [ -z "$AWK_CMD" ]; then
    log_warn "未找到 awk，暂时无法维护 TEE Simulator 配置"
fi

# ---------- inotify 依赖检查 ----------
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    log_err "未找到 inotify 工具，服务退出"
    exit 1
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
log_info "监听方式：$INOTIFY_MODE（${INOTIFY_CMD%% *}）"

# ---------- 变更检测 ----------
# 说明：以 packages.list 的包名集合 + rules.txt 生成指纹，用于过滤系统频繁
#       改写 packages.list 造成的无谓同步。
# 用法：get_source_fingerprint
get_source_fingerprint() {
    local pkgs rules

    pkgs=$(cut -d' ' -f1 "$WATCH_DIR/packages.list" 2>/dev/null | sort -u)
    rules=$(sed '/^$/d' "$RULES_FILE" 2>/dev/null | sort -u)

    printf '%s\n%s\n' "$pkgs" "$rules" | cksum 2>/dev/null | cut -d' ' -f1
}

# ---------- 同步核心 ----------
# 说明：指纹未变化则直接返回；失败时不记录指纹，便于下次重试。
# 用法：do_sync
do_sync() {
    local fp rc

    fp=$(get_source_fingerprint)
    if [ -n "$fp" ] && [ "$fp" = "$(cat "$FP_FILE" 2>/dev/null)" ]; then
        return 0
    fi

    log_info "开始应用列表同步"
    run_sync "$PROP_FILE" "$TMP"
    rc=$?
    case "$rc" in
        0) log_info "同步完成，应用总数：$TAA_COUNT" ;;
        2) log_warn "同步失败：未能生成或写入应用列表" ;;
    esac

    if [ "$rc" != "2" ] && [ -n "$fp" ]; then
        echo "$fp" > "$FP_FILE" 2>/dev/null
    fi
}

# ---------- 防抖调度 ----------
# 说明：2 秒内的多次触发合并为一次同步。
# 用法：dispatch_sync
dispatch_sync() {
    mkdir "$DEBOUNCE_LOCK" 2>/dev/null || return 0

    (
        sleep 2
        rmdir "$DEBOUNCE_LOCK" 2>/dev/null
        acquire_lock "$LOCK_DIR" || exit 1
        do_sync
        release_lock "$LOCK_DIR"
    ) &
}

# ---------- 状态清理 ----------
# 结束上次遗留的守护进程，并清理运行文件
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi
rm -rf "$TMP" "$LOCK_DIR" "$DEBOUNCE_LOCK" 2>/dev/null

# ---------- 启动 ----------
until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done

log_info "开机完成，执行首次同步"
dispatch_sync

# ---------- 事件监听 ----------
# 说明：单进程同时监听系统包列表目录与常驻列表文件；进程异常退出后自动重启。
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        ensure_rules_file "$RULES_FILE"

        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete "$WATCH_DIR" "$RULES_FILE" 2>/dev/null |
                while read -r line; do
                    case "$line" in
                        *packages.list*|*rules.txt*) dispatch_sync ;;
                    esac
                done
        else
            $INOTIFY_CMD - "$WATCH_DIR:wc" "$RULES_FILE:wc" 2>/dev/null |
                while read -r _ev file; do
                    case "$file" in
                        *packages.list*|*rules.txt*) dispatch_sync ;;
                    esac
                done
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

log_info "守护进程就绪"
exit 0
