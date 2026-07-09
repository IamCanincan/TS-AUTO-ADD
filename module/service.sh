#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 后台守护进程
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
TS_TARGET="$TS_BASE/target.txt"
TEESIM_CONFIG="$TEESIM_BASE/config.json"
WATCH_DIR="/data/system"

TMP="${TS_BASE}/.ts_tmp"
LOCK_DIR="${TS_BASE}/.ts_lock"
DEBOUNCE_LOCK="${TS_BASE}/.ts_debounce"
PIDS_FILE="${TS_BASE}/.ts_daemon_pids.list"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || exit 1

# ---------- inotify 工具初始化 ----------
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    log_err "未检测到可用的 inotify 组件，守护进程退出"
    exit 1
fi

INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
log_info "初始化监控组件: ${INOTIFY_CMD%% *} ($INOTIFY_MODE)"

# ---------- 核心同步逻辑 ----------
do_sync() {
    log_info "触发包名列表自动同步"
    mkdir -p "$TS_BASE" "$TEESIM_BASE" 2>/dev/null
    ensure_taa_sys "$TAA_SYS_FILE"

    local apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    local user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
    local user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
    local sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

    (cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null

    if [ -s "$TMP" ]; then
        # 更新 TrickyStore 目标文件
        cp -f "$TMP" "$TS_TARGET" 2>/dev/null
        chmod 644 "$TS_TARGET" 2>/dev/null

        # 更新 TeeSim 配置文件 (仅修改 apps 节点)
        generate_teesim_json "$TMP" "$TEESIM_CONFIG"

        log_info "同步完成 - 系统白名单: $sys_count，第三方应用: $user_count"
    fi
    rm -f "$TMP" 2>/dev/null

    local current_time=$(date '+%H:%M')
    update_module_prop "$PROP_FILE" "[系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
}

# 防抖调度机制
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

# ---------- 状态重置与清理 ----------
if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE" 2>/dev/null
fi
rm -rf "$TMP" "$LOCK_DIR" "$DEBOUNCE_LOCK" 2>/dev/null

until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do
    sleep 2
done

log_info "系统开机完成，执行首次同步"
dispatch_sync

# ---------- 监控任务配置 ----------
# 任务 1: 系统应用包变更监听
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        if [ "$INOTIFY_MODE" = "inotifywait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete "$WATCH_DIR" 2>/dev/null | while read -r line; do
                case "$line" in *packages.list*) dispatch_sync ;; esac
            done
        else
            $INOTIFY_CMD - "$WATCH_DIR:wc" 2>/dev/null | while read -r event file; do
                case "$file" in *packages.list*) dispatch_sync ;; esac
            done
        fi
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

# 任务 2: 模块内置系统白名单文件监听
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

log_info "后台守护进程已运行"
exit 0