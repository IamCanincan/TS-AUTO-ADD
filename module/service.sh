#!/system/bin/sh
#=============================================================================
# service.sh - 事件驱动型后台守护服务 (无轮询防抖架构)
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

# ---------- 环境预检 ----------
INOTIFY_CMD=""
for cmd in "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd" "inotifyd" "/system/bin/inotifyd"; do
    if command -v ${cmd%% *} >/dev/null 2>&1; then
        INOTIFY_CMD="$cmd"
        break
    fi
done
[ -z "$INOTIFY_CMD" ] && { log_err "未找到在用的 inotifyd"; exit 1; }

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
    update_module_status "$PROP_FILE" "$BASE" "$PATCH_CONFIG_FILE"
}

# 彻底摒弃 sleep 轮询，采用基于目录原子锁的非阻塞防抖 (Debounce)
dispatch_sync() {
    if mkdir "$DEBOUNCE_LOCK" 2>/dev/null; then
        (
            # 窗口期内若再次触发，外层 mkdir 会直接跳过，从而实现批处理
            sleep 3 
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

# 阻塞等待直至系统完全启动
until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done

log_info "系统启动完毕，触发首次同步"
dispatch_sync

# ---------- 守护进程下发 (自愈式沙盒) ----------
# Magisk规范要求service.sh本体不应长时间阻塞。下发各监控任务至后台后主脚本退出。

# 任务1: 安全补丁自动更新 (独立休眠循环)
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
echo $! >> "$PIDS_FILE"

# 任务2: 目录级 packages.list 监控
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        $INOTIFY_CMD - "$WATCH_DIR:wc" 2>/dev/null | while read -r line; do
            case "$line" in
                *packages.list*) dispatch_sync ;;
            esac
        done
        sleep 3 # 如果因系统异常导致管道断开，延迟重启，代替外部轮询守护
    done
) &
echo $! >> "$PIDS_FILE"

# 任务3: taa_sys.txt 白名单文件监控
(
    while true; do
        ensure_taa_sys "$TAA_SYS_FILE"
        $INOTIFY_CMD - "$TAA_SYS_FILE:wc" 2>/dev/null | while read -r line; do
            dispatch_sync
        done
        sleep 3
    done
) &
echo $! >> "$PIDS_FILE"

log_info "事件驱动守护程序组下发完毕，主引导退出。"
exit 0