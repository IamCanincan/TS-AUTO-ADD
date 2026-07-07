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
            log_info "target.txt 已更新，行数: $(wc -l < "$TARGET")"
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

# ---------- 启动清理与初始化 ----------
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

log_info "首次同步触发"
dispatch_sync

# ---------- 核心守护线程 ----------

# [1] 补丁定时更新服务 (12小时)
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [2] 恢复原版：完全照搬原脚本中已被验证成功的 packages.list 监控逻辑
start_monitor_pkg() {
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
MONITOR1_PID=$(start_monitor_pkg "$WATCH_FILE" "w")

# [3] 全新隔离逻辑：监控 $BASE 目录，但严格过滤文件名 (解决 taa_sys.txt 无法更新且耗电的死循环)
start_monitor_sys() {
    (
        while true; do
            mkdir -p "$BASE"
            [ -f "$TAA_SYS_FILE" ] || touch "$TAA_SYS_FILE"
            
            # wycmn 囊括了不同系统(Busybox/Toybox)下写入、创建、移动覆盖的所有可能事件
            inotifyd - "$BASE:wycmn" 2>/dev/null | while read -r event file_name; do
                # 核心修复：清理可能存在的换行符或空格，精准匹配
                clean_file=$(echo "$file_name" | tr -d '\r\n[:space:]')
                
                # 只有当事件明确属于 taa_sys.txt 时，才触发同步！
                # 这彻底隔绝了同目录下 .ts_tmp 和 target.txt 的写入死循环。
                if [ "$clean_file" = "taa_sys.txt" ]; then
                    dispatch_sync
                fi
            done
            sleep 2
        done
    ) &
    echo $!
}
MONITOR2_PID=$(start_monitor_sys)

echo $$ > "$MAIN_PID_FILE"
trap 'kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 主心跳维护
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        MONITOR1_PID=$(start_monitor_pkg "$WATCH_FILE" "w")
    fi
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        MONITOR2_PID=$(start_monitor_sys)
    fi
done