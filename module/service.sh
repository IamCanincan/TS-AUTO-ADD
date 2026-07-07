#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务（合并监控，避免冲突）
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_DIR="/data/system"   # 监控整个 /data/system 目录

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
    mkdir -p "$BASE"
    mkdir -p "$(dirname "$TAA_SYS_FILE")"
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
        chmod 644 "$TAA_SYS_FILE"
        log_info "taa_sys.txt 已创建（缺失）"
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
        fi
    else
        rm -f "$TMP"
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

# ---------- 合并监控线程（监控 /data/system 目录） ----------
(
    while true; do
        # 监控目录内所有文件的写入、创建、删除事件
        inotifyd - "$WATCH_DIR:wyc" 2>/dev/null | while read -r event; do
            # 检查事件是否涉及 packages.list 或 taa_sys.txt
            if echo "$event" | grep -q "packages.list"; then
                log_info "检测到 packages.list 变化"
                dispatch_sync
            elif echo "$event" | grep -q "ts_auto_add/taa_sys.txt"; then
                # 确保文件存在，若缺失则重建
                if [ ! -f "$TAA_SYS_FILE" ]; then
                    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                    chmod 644 "$TAA_SYS_FILE"
                    log_info "taa_sys.txt 已重建（监控捕捉到删除）"
                fi
                log_info "检测到 taa_sys.txt 变化"
                dispatch_sync
            fi
        done
        sleep 2
    done
) &
MONITOR_PID=$!

echo $$ > "$MAIN_PID_FILE"
trap 'kill $PATCH_PID $MONITOR_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 心跳检测（每 5 分钟）
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启"
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR_PID 2>/dev/null; then
        log_warn "监控进程重启"
        (
            while true; do
                inotifyd - "$WATCH_DIR:wyc" 2>/dev/null | while read -r event; do
                    if echo "$event" | grep -q "packages.list"; then
                        log_info "检测到 packages.list 变化"
                        dispatch_sync
                    elif echo "$event" | grep -q "ts_auto_add/taa_sys.txt"; then
                        if [ ! -f "$TAA_SYS_FILE" ]; then
                            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                            chmod 644 "$TAA_SYS_FILE"
                            log_info "taa_sys.txt 已重建（监控捕捉到删除）"
                        fi
                        log_info "检测到 taa_sys.txt 变化"
                        dispatch_sync
                    fi
                done
                sleep 2
            done
        ) &
        MONITOR_PID=$!
    fi
done