#!/system/bin/sh
#=============================================================================
# service.sh - 后台守护服务
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
WATCH_DIR="/data/system"
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
    
    # 环境自愈：确保 taa_sys.txt 始终存在
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
        chmod 644 "$TAA_SYS_FILE"
    fi

    # 管道流合并，避免多次读写中间文件
    {
        cat "$TAA_SYS_FILE" 2>/dev/null
        echo ""
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    # 原子比对与替换
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            log_info "target.txt 联动刷新成功，行数: $(wc -l < "$TARGET")"
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
        sleep 0.1
    done
    do_sync
    release_lock "$LOCK_DIR"
}

# ---------- 启动流程 ----------
# 强制清理以往版本可能残留的所有隐藏进程和锁
for pid_file in "$BASE/.ts_daemon_b1.pid" "$BASE/.ts_daemon_b2.pid" "$BASE/.ts_patch.pid" "$MAIN_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$old_pid" ] && kill -9 "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi
done
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

# 阻塞等待 boot_completed，确保系统不处于高负载冲突期
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 4; done

# 开机初次强制对齐
log_info "开机首次包名及补丁初始化对齐"
dispatch_sync

# ----------------------------------------------------------------------------
# 后台常驻服务（双线程异步架构，无互相干扰）
# ----------------------------------------------------------------------------

# [线程 1：补丁定时更新] 12小时全睡眠唤醒一次，零日常功耗
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [线程 2：双路事件监听] 
# 彻底移除 $BASE:wyc，直接监听 taa_sys.txt 文件的写入事件
# 配合监控 /data/system 目录的移入事件，全面捕获应用安装
start_monitor() {
    (
        while true; do
            # 建立物理节点，防止 inotifyd 因为找不到目标而异常挂死
            [ -f "$WATCH_FILE" ] || touch "$WATCH_FILE"
            [ -f "$TAA_SYS_FILE" ] || touch "$TAA_SYS_FILE"

            # 联动捕获：应用更替（父目录m、子文件wm）与 白名单修改（w）
            inotifyd - "$WATCH_FILE:wm" "$WATCH_DIR:m" "$TAA_SYS_FILE:w" 2>/dev/null | while read -r event file_name; do
                # 过滤条件：如果事件由 /data/system 目录抛出，但被移动的不是 packages.list，则忽略以防耗电
                if [ -n "$file_name" ] && [ "$file_name" != "packages.list" ]; then
                    continue
                fi
                dispatch_sync
            done
            sleep 3 # 保守容错延迟
        done
    ) &
    echo $!
}

MONITOR_PID=$(start_monitor)
echo $$ > "$MAIN_PID_FILE"

# 主进程优雅注销信号捕获
trap 'log_info "收到退出信号，清理并安全注销"; kill $PATCH_PID $MONITOR_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# ---------- 轻量级心跳存活维护 ----------
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁子进程异常，重新拉起..."
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR_PID 2>/dev/null; then
        log_warn "事件监控进程异常，重新拉起..."
        MONITOR_PID=$(start_monitor)
    fi
done