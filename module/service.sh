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
rm -rf "$LOCK_DIR"

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

# ---------- 监控 taa_sys.txt 变更（事件触发 + mtime 校验，不依赖事件内容） ----------
(
    TAA_SYS_FILE="$BASE/taa_sys.txt"
    # 初始化 mtime（若文件存在）
    if [ -f "$TAA_SYS_FILE" ]; then
        LAST_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
    else
        LAST_MTIME=""
    fi

    while true; do
        # 监控整个 BASE 目录，任何文件变化（写入、创建、删除）都会触发
        inotifyd - "$BASE:wyc" 2>/dev/null | while read -r _; do
            # 每次目录事件，检查目标文件是否发生变化
            if [ -f "$TAA_SYS_FILE" ]; then
                # 获取当前 mtime
                CURRENT_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
                # 若 stat 获取成功且 mtime 变化，或 stat 失败（保守策略触发同步），则执行同步
                if [ -n "$CURRENT_MTIME" ]; then
                    if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
                        LAST_MTIME="$CURRENT_MTIME"
                        log_info "taa_sys.txt 修改时间变化，触发同步"
                        dispatch_sync
                    fi
                else
                    # stat 不支持，视为已变化，触发同步（保守）
                    log_info "stat 不支持，事件触发同步（保守策略）"
                    dispatch_sync
                    # 更新 LAST_MTIME 防止重复触发（但无法获取真实时间，可用当前时间）
                    LAST_MTIME=$(date +%s)
                fi
            else
                # 文件不存在，重建并同步
                printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                chmod 644 "$TAA_SYS_FILE"
                LAST_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
                log_info "taa_sys.txt 已重建，触发同步"
                dispatch_sync
            fi
        done
        # 若 inotifyd 异常退出，短暂等待后重启
        sleep 2
    done
) &
MONITOR2_PID=$!

echo $$ > "$MAIN_PID_FILE"

# 主进程健康监管
trap 'log_info "收到退出信号，终止子进程"; kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

restart_count=0
max_restart=5
reset_interval=600

while true; do
    sleep 60
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启 (计数 $restart_count)"
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
        restart_count=$((restart_count + 1))
    fi
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        log_warn "监控1 (packages.list) 重启 (计数 $restart_count)"
        MONITOR1_PID=$(start_monitor "$WATCH_FILE" "w")
        restart_count=$((restart_count + 1))
    fi
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        log_warn "监控2 (taa_sys.txt) 重启 (计数 $restart_count)"
        (
            TAA_SYS_FILE="$BASE/taa_sys.txt"
            if [ -f "$TAA_SYS_FILE" ]; then
                LAST_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
            else
                LAST_MTIME=""
            fi
            while true; do
                inotifyd - "$BASE:wyc" 2>/dev/null | while read -r _; do
                    if [ -f "$TAA_SYS_FILE" ]; then
                        CURRENT_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
                        if [ -n "$CURRENT_MTIME" ]; then
                            if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
                                LAST_MTIME="$CURRENT_MTIME"
                                log_info "taa_sys.txt 修改时间变化，触发同步"
                                dispatch_sync
                            fi
                        else
                            log_info "stat 不支持，事件触发同步（保守策略）"
                            dispatch_sync
                            LAST_MTIME=$(date +%s)
                        fi
                    else
                        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
                        chmod 644 "$TAA_SYS_FILE"
                        LAST_MTIME=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
                        log_info "taa_sys.txt 已重建，触发同步"
                        dispatch_sync
                    fi
                done
                sleep 2
            done
        ) &
        MONITOR2_PID=$!
        restart_count=$((restart_count + 1))
    fi

    if [ $restart_count -ge $max_restart ]; then
        log_warn "子进程频繁重启，进入冷静期 10 分钟"
        sleep $reset_interval
        restart_count=0
    fi
done