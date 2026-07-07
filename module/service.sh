#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_DIR="/data/system"

TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_CACHE_FILE="$BASE/.last_month"
MAIN_PID_FILE="${BASE}/.ts_daemon_main.pid"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { logger -t TS-AUTO -p err "无法加载 common.sh"; exit 1; }

# ---------- 查找可用的 inotifyd ----------
INOTIFY_CMD=""
for cmd in inotifyd /system/bin/inotifyd /data/adb/ksu/bin/busybox /data/adb/magisk/busybox; do
    if command -v "$cmd" >/dev/null 2>&1; then
        INOTIFY_CMD="$cmd"
        break
    fi
done
if [ -z "$INOTIFY_CMD" ]; then
    log_err "未找到 inotifyd 命令，无法启动文件监听服务"
    exit 1
fi
log_info "使用 inotifyd: $INOTIFY_CMD"

# ---------- 同步核心 ----------
do_sync() {
    log_info "do_sync 开始执行"
    mkdir -p "$BASE" 2>/dev/null
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
        chmod 640 "$TAA_SYS_FILE" 2>/dev/null
        chown root:root "$TAA_SYS_FILE" 2>/dev/null
        chcon system_data_file "$TAA_SYS_FILE" 2>/dev/null || true
        log_info "taa_sys.txt 已创建（缺失）"
    fi

    {
        cat "$TAA_SYS_FILE" 2>/dev/null
        echo ""
        local apps_raw=""
        if command -v cmd >/dev/null 2>&1; then
            apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
        fi
        [ -z "$apps_raw" ] && command -v pm >/dev/null 2>&1 && apps_raw=$(pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET" 2>/dev/null; then
            mv -f "$TMP" "$TARGET" 2>/dev/null
            chmod 644 "$TARGET" 2>/dev/null
            log_info "target.txt 已同步，行数: $(wc -l < "$TARGET" 2>/dev/null || echo 0)"
        else
            rm -f "$TMP" 2>/dev/null
            log_info "target.txt 内容无变化，跳过写入"
        fi
    else
        rm -f "$TMP" 2>/dev/null
        log_warn "同步结果为空（可能包管理器异常）"
    fi
    update_module_status "$PROP_FILE" "$BASE" "$PATCH_CONFIG_FILE"
}

dispatch_sync() {
    touch "$PENDING" 2>/dev/null
    acquire_lock "$LOCK_DIR" || { log_err "获取锁失败"; rm -f "$PENDING" 2>/dev/null; return 1; }
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING" 2>/dev/null
        sleep 0.1
    done
    do_sync
    release_lock "$LOCK_DIR"
}

# ---------- 启动清理 ----------
for pid_file in "$BASE/.ts_daemon_b1.pid" "$BASE/.ts_daemon_b2.pid" "$BASE/.ts_patch.pid" "$MAIN_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$old_pid" ] && kill -9 "$old_pid" 2>/dev/null && sleep 0.1
        rm -f "$pid_file" 2>/dev/null
    fi
done
rm -f "$TMP" "$PENDING" 2>/dev/null
rm -rf "$LOCK_DIR" 2>/dev/null

until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done

log_info "系统启动完成，执行首次同步"
dispatch_sync

# ---------- 守护线程 ----------

# 补丁定时更新（每 12 小时）
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# 监控 packages.list（改为监控 /data/system 目录，过滤文件名）
(
    while true; do
        [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
        $INOTIFY_CMD - "$WATCH_DIR:wc" 2>/dev/null | while read -r path event; do
            case "$path" in
                "packages.list")
                    log_info "检测到 packages.list 变化"
                    dispatch_sync
                    ;;
            esac
        done
        log_warn "packages.list 目录监听进程退出，2秒后重启"
        sleep 2
    done
) &
MONITOR1_PID=$!

# 监控 taa_sys.txt（直接文件监听）
(
    while true; do
        [ -f "$TAA_SYS_FILE" ] || {
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
            chmod 640 "$TAA_SYS_FILE" 2>/dev/null
            chown root:root "$TAA_SYS_FILE" 2>/dev/null
            chcon system_data_file "$TAA_SYS_FILE" 2>/dev/null || true
            log_info "taa_sys.txt 已创建（初始）"
            dispatch_sync
        }
        $INOTIFY_CMD - "$TAA_SYS_FILE:wc" 2>>"$LOG_FILE" | while read -r _; do
            log_info "检测到 taa_sys.txt 变化"
            dispatch_sync
        done
        log_warn "taa_sys.txt 监听进程退出，2秒后重启"
        sleep 2
    done
) &
MONITOR2_PID=$!

# 记录主进程 PID
echo $$ > "$MAIN_PID_FILE" 2>/dev/null
log_info "主守护进程已启动，PID: $$, MONITOR2_PID: $MONITOR2_PID"

cleanup() {
    log_info "收到终止信号，清理子进程"
    kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null
    rm -f "$MAIN_PID_FILE" 2>/dev/null
    exit 0
}
trap 'cleanup' INT TERM QUIT

# 心跳检测（每 5 分钟），监控子进程状态并自动重启
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启"
        (
            while true; do
                update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
                sleep 43200
            done
        ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        log_warn "监控1 (packages.list) 重启"
        (
            while true; do
                [ -d "$WATCH_DIR" ] || { sleep 5; continue; }
                $INOTIFY_CMD - "$WATCH_DIR:wc" 2>/dev/null | while read -r path event; do
                    case "$path" in
                        "packages.list")
                            log_info "检测到 packages.list 变化"
                            dispatch_sync
                            ;;
                    esac
                done
                log_warn "packages.list 目录监听进程退出，2秒后重启"
                sleep 2
            done
        ) &
        MONITOR1_PID=$!
    fi
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        log_warn "监控2 (taa_sys.txt) 重启"
        (
            while true; do
                [ -f "$TAA_SYS_FILE" ] || {
                    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
                    chmod 640 "$TAA_SYS_FILE" 2>/dev/null
                    chown root:root "$TAA_SYS_FILE" 2>/dev/null
                    chcon system_data_file "$TAA_SYS_FILE" 2>/dev/null || true
                    log_info "taa_sys.txt 已创建（重启）"
                    dispatch_sync
                }
                $INOTIFY_CMD - "$TAA_SYS_FILE:wc" 2>>"$LOG_FILE" | while read -r _; do
                    log_info "检测到 taa_sys.txt 变化"
                    dispatch_sync
                done
                log_warn "taa_sys.txt 监听进程退出，2秒后重启"
                sleep 2
            done
        ) &
        MONITOR2_PID=$!
    fi
done