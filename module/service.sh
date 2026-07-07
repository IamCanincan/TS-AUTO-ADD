#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TAA_SYS_FILE="$BASE/taa_sys.txt"

TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_CACHE_FILE="$BASE/.last_month"
MAIN_PID_FILE="${BASE}/.ts_daemon_main.pid"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || { logger -t TS-AUTO -p err "无法加载 common.sh"; exit 1; }

log_info() { logger -t TS-AUTO -p info "$*"; }
log_warn() { logger -t TS-AUTO -p warn "$*"; }
log_err()  { logger -t TS-AUTO -p err "$*"; }

# ---------- 同步核心 ----------
do_sync() {
    mkdir -p "$BASE"
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
        chmod 644 "$TAA_SYS_FILE"
        log_info "taa_sys.txt 已重建（缺失）"
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
            log_info "target.txt 内容无变化，跳过更新"
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

# ---------- 启动清理与开机对齐 ----------
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

# ---------- 核心守护线程 ----------

# [线程 1] 补丁定时更新 (12小时)
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [线程 2] 应用安装监听（packages.list）
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

# [线程 3] 白名单修改监听（taa_sys.txt）—— 纯事件驱动 + MD5 内容校验
start_monitor_sys() {
    (
        # 初始化哈希基准（若文件不存在则创建）
        if [ ! -f "$TAA_SYS_FILE" ]; then
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
            chmod 644 "$TAA_SYS_FILE"
            log_info "初始化 taa_sys.txt（初始创建）"
        fi
        local last_hash="$(md5sum "$TAA_SYS_FILE" 2>/dev/null | cut -d' ' -f1)"
        log_info "初始哈希: $last_hash"

        while true; do
            # 监控 BASE 目录，捕获所有文件变动（写入、创建、删除、关闭写入）
            inotifyd - "$BASE:wycd" 2>/dev/null | while read -r event; do
                # 每次事件都检查目标文件
                if [ -f "$TAA_SYS_FILE" ]; then
                    local current_hash="$(md5sum "$TAA_SYS_FILE" 2>/dev/null | cut -d' ' -f1)"
                    if [ -n "$current_hash" ] && [ "$current_hash" != "$last_hash" ]; then
                        last_hash="$current_hash"
                        log_info "检测到 taa_sys.txt 内容变化（新哈希: $current_hash）"
                        dispatch_sync
                        # 同步后可能文件被外部工具再次修改，重新获取最新哈希作为基准，避免重复触发
                        last_hash="$(md5sum "$TAA_SYS_FILE" 2>/dev/null | cut -d' ' -f1)"
                    fi
                else
                    # 文件被删除，立即重建并触发同步
                    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                    chmod 644 "$TAA_SYS_FILE"
                    last_hash="$(md5sum "$TAA_SYS_FILE" 2>/dev/null | cut -d' ' -f1)"
                    log_info "taa_sys.txt 已重建（原文件缺失），哈希: $last_hash"
                    dispatch_sync
                fi
            done
            # 若 inotifyd 意外退出，短暂等待后重启循环
            sleep 2
        done
    ) &
    echo $!
}
MONITOR2_PID=$(start_monitor_sys)

echo $$ > "$MAIN_PID_FILE"
trap 'kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 主生存心跳检测（每5分钟检查一次，降低开销）
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
        log_warn "监控2 (taa_sys.txt) 重启"
        MONITOR2_PID=$(start_monitor_sys)
    fi
done