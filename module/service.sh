#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务
# 功能：监听文件变化并同步 target.txt，定期更新安全补丁日期
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
PATCH_BACKUP_FILE="$BASE/security_patch.txt.bak"
PATCH_CACHE_FILE="$BASE/.last_month"
MAIN_PID_FILE="${BASE}/.ts_daemon_main.pid"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 加载公共函数库
. "$MODDIR/common.sh" || { logger -t TS-AUTO -p err "无法加载 common.sh"; exit 1; }

# ---------- 日志 ----------
log_info() { logger -t TS-AUTO -p info "$*"; }
log_warn() { logger -t TS-AUTO -p warn "$*"; }
log_err()  { logger -t TS-AUTO -p err "$*"; }

# ---------- 同步核心 ----------
do_sync() {
    mkdir -p "$BASE"
    local TAA_SYS_FILE="$BASE/taa_sys.txt"
    {
        if [ -f "$TAA_SYS_FILE" ]; then
            cat "$TAA_SYS_FILE" 2>/dev/null
            echo ""
        else
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        fi
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
        [ -z "$apps_raw" ] && apps_raw=$(pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            log_info "target.txt 更新，行数: $(wc -l < "$TARGET")"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
        log_warn "同步结果为空"
    fi
    update_module_status "$PROP_FILE" "$BASE" "$PATCH_CONFIG_FILE"
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock "$LOCK_DIR" || { log_err "获取锁失败"; rm -f "$PENDING"; return 1; }
    # 合并短时间内的多次触发，延迟 50 毫秒，平衡实时性与资源消耗
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 0.05
    done
    do_sync
    release_lock "$LOCK_DIR"
}

# ---------- 启动流程 ----------
# 清理旧进程和临时文件
for pid_file in "$BASE/.ts_daemon_b1.pid" "$BASE/.ts_daemon_b2.pid" "$BASE/.ts_patch.pid"; do
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null && sleep 0.1 && kill -9 "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi
done
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"   # 强制清理残留锁目录

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

# 首次同步
log_info "首次同步"
dispatch_sync

# 启动补丁定时更新子进程
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# ---------- 辅助函数：启动一个监控子进程 ----------
start_monitor() {
    local file="$1"
    local events="$2"
    (
        while true; do
            [ -f "$file" ] || { sleep 5; continue; }
            inotifyd - "$file:$events" 2>/dev/null | while read -r _; do
                dispatch_sync
            done
            sleep 2
        done
    ) &
    echo $!
}

# 监控 packages.list 变化
MONITOR1_PID=$(start_monitor "$WATCH_FILE" "w")

# ---------- 监控 taa_sys.txt 变更（目录监控方式） ----------
# 监控整个 BASE 目录，捕获 taa_sys.txt 的创建、写入、删除事件
(
    while true; do
        inotifyd - "$BASE:wyc" 2>/dev/null | while read -r line; do
            # 仅处理与 taa_sys.txt 相关的事件
            if echo "$line" | grep -q "taa_sys.txt"; then
                # 若文件被删除，则立即重建默认内容
                if [ ! -f "$BASE/taa_sys.txt" ]; then
                    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$BASE/taa_sys.txt"
                    chmod 644 "$BASE/taa_sys.txt"
                    log_info "taa_sys.txt 已重建"
                fi
                log_info "taa_sys.txt 变化事件触发"
                dispatch_sync
            fi
        done
        sleep 2
    done
) &
MONITOR2_PID=$!

echo $$ > "$MAIN_PID_FILE"

# 主进程健康监管
trap 'log_info "收到退出信号，终止子进程"; kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 子进程重启计数器
restart_count=0
max_restart=5
reset_interval=600  # 10分钟内超过5次则进入冷静期

while true; do
    sleep 60
    # 补丁进程
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启 (计数 $restart_count)"
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
        restart_count=$((restart_count + 1))
    fi
    # 监控1
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        log_warn "监控1 (packages.list) 重启 (计数 $restart_count)"
        MONITOR1_PID=$(start_monitor "$WATCH_FILE" "w")
        restart_count=$((restart_count + 1))
    fi
    # 监控2
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        log_warn "监控2 (taa_sys.txt) 重启 (计数 $restart_count)"
        (
            while true; do
                inotifyd - "$BASE:wyc" 2>/dev/null | while read -r line; do
                    if echo "$line" | grep -q "taa_sys.txt"; then
                        if [ ! -f "$BASE/taa_sys.txt" ]; then
                            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$BASE/taa_sys.txt"
                            chmod 644 "$BASE/taa_sys.txt"
                            log_info "taa_sys.txt 已重建"
                        fi
                        log_info "taa_sys.txt 变化事件触发"
                        dispatch_sync
                    fi
                done
                sleep 2
            done
        ) &
        MONITOR2_PID=$!
        restart_count=$((restart_count + 1))
    fi

    # 若重启过于频繁，进入冷静期
    if [ $restart_count -ge $max_restart ]; then
        log_warn "子进程频繁重启，进入冷静期 10 分钟"
        sleep $reset_interval
        restart_count=0
    fi
done