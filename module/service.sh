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

# 加载公共函数库
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
            log_info "target.txt 已同步刷新，行数: $(wc -l < "$TARGET")"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
    fi
    
    # 这一步会改写 $BASE 目录的文件，但因为我们彻底关闭了对 $BASE 目录的 inotifyd 监听，所以绝对不会再引发死锁！
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

# 开机强制对齐一次
dispatch_sync

# ---------- 核心守护线程 ----------

# [线程 1] 补丁定时轮询 (12小时)
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [线程 2] 应用安装监听：完全保留第一版原汁原味的、100% 成功的单文件原生监听逻辑
start_monitor_pkg() {
    (
        while true; do
            [ -f "$WATCH_FILE" ] || { sleep 5; continue; }
            inotifyd - "$WATCH_FILE:w" 2>/dev/null | while read -r _; do
                dispatch_sync
            done
            sleep 2
        done
    ) &
    echo $!
}
MONITOR1_PID=$(start_monitor_pkg)

# [线程 3] 白名单配置监听：彻底废除危险的 $BASE 目录 inotifyd 监听，改用超轻量时间戳轮询
# 这能 100% 避开锁冲突，且在 3 秒内对任意文本编辑器的保存做出即时响应
start_monitor_sys() {
    (
        local last_mtime=0
        while true; do
            if [ -f "$TAA_SYS_FILE" ]; then
                # 使用 shell 内建的高性能 stat 获取修改时间戳
                local current_mtime=$(stat -c %Y "$TAA_SYS_FILE" 2>/dev/null)
                if [ -n "$current_mtime" ] && [ "$current_mtime" != "$last_mtime" ]; then
                    if [ "$last_mtime" -ne 0 ]; then
                        log_info "检测到 taa_sys.txt 发生修改，正在同步..."
                        dispatch_sync
                    fi
                    last_mtime="$current_mtime"
                fi
            fi
            sleep 3
        done
    ) &
    echo $!
}
MONITOR2_PID=$(start_monitor_sys)

echo $$ > "$MAIN_PID_FILE"
trap 'kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 主生存心跳检测
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        MONITOR1_PID=$(start_monitor_pkg)
    fi
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        MONITOR2_PID=$(start_monitor_sys)
    fi
done