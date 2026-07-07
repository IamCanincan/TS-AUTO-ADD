#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"

TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_CACHE_FILE="$BASE/.last_month"
MAIN_PID_FILE="${BASE}/.ts_daemon_main.pid"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { logger -t TS-AUTO -p err "无法加载 common.sh"; exit 1; }

# ---------- 同步核心 ----------
do_sync() {
    log_info "do_sync 开始执行"
    mkdir -p "$BASE"
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
        chmod 640 "$TAA_SYS_FILE"
        chown root:root "$TAA_SYS_FILE" 2>/dev/null
        log_info "taa_sys.list 已创建（缺失）"
    fi

    {
        cat "$TAA_SYS_FILE" 2>/dev/null
        echo ""
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
        [ -z "$apps_raw" ] && apps_raw=$(pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            log_info "target.txt 已同步，行数: $(wc -l < "$TARGET")"
        else
            rm -f "$TMP"
            log_info "target.txt 内容无变化，跳过写入"
        fi
    else
        rm -f "$TMP"
        log_warn "同步结果为空（可能包管理器异常）"
    fi
    update_module_status "$PROP_FILE" "$BASE" "$PATCH_CONFIG_FILE"
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock "$LOCK_DIR" || { log_err "获取锁失败"; rm -f "$PENDING"; return 1; }
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 0.1
    done
    do_sync
    release_lock "$LOCK_DIR"
}

# ---------- 启动清理 ----------
for pid_file in "$BASE/.ts_daemon_b1.pid" "$BASE/.ts_daemon_b2.pid" "$BASE/.ts_patch.pid" "$MAIN_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$old_pid" ] && kill -9 "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi
done
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

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

# 监控 packages.list
start_monitor_pkg() {
    (
        while true; do
            [ -f "$WATCH_FILE" ] || { sleep 5; continue; }
            inotifyd - "$WATCH_FILE:w" 2>/dev/null | while read -r _; do
                log_info "检测到 packages.list 变化"
                dispatch_sync
            done
            sleep 2
        done
    ) &
    echo $!
}
MONITOR1_PID=$(start_monitor_pkg)

# 监控 taa_sys.list（与 packages.list 完全相同）
start_monitor_sys() {
    (
        while true; do
            if [ ! -f "$TAA_SYS_FILE" ]; then
                printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                chmod 640 "$TAA_SYS_FILE"
                chown root:root "$TAA_SYS_FILE" 2>/dev/null
                log_info "taa_sys.list 已创建（初始）"
                dispatch_sync
            fi
            inotifyd - "$TAA_SYS_FILE:w" 2>/dev/null | while read -r _; do
                log_info "检测到 taa_sys.list 变化"
                dispatch_sync
            done
            sleep 2
        done
    ) &
    echo $!
}
MONITOR2_PID=$(start_monitor_sys)

echo $$ > "$MAIN_PID_FILE"
trap 'kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 心跳检测（每 5 分钟）
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启"
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        log_warn "监控1 (packages.list) 重启"
        MONITOR1_PID=$(start_monitor_pkg)
    fi
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        log_warn "监控2 (taa_sys.list) 重启"
        MONITOR2_PID=$(start_monitor_sys)
    fi
done