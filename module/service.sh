#!/system/bin/sh
#=============================================================================
# service.sh - 后台服务进程
# 优化策略：合并事件流、精准目标监控、剔除高频 Fork 派生开销
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TAA_SYS="$BASE/taa_sys.txt"
TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_CACHE_FILE="$BASE/.last_month"
MAIN_PID_FILE="${BASE}/.ts_daemon_main.pid"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 引入公共库
. "$MODDIR/common.sh" || exit 1

log_info() { logger -t TS-AUTO -p info "$*"; }

do_sync() {
    mkdir -p "$BASE"
    
    # [客观行为] 基础环境自愈：避免因手动误删导致后续 cat 流程阻塞或报错
    if [ ! -f "$TAA_SYS" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS"
        chmod 644 "$TAA_SYS"
    fi

    # [性能优化] 管道合并：将本地读取与 pm/cmd 指令合并入单次 I/O 流，减少临时文件多次复写开销
    {
        cat "$TAA_SYS" 2>/dev/null
        echo ""
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    # [原子写入] 使用 cmp 预检变更：仅在内容实际改变时进行 mv 覆盖，避免对 flash 介质进行高频无意义写入
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            log_info "target.txt 实时同步成功"
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
    acquire_lock "$LOCK_DIR" || { rm -f "$PENDING"; return 1; }
    
    # [时序防抖] 局部自旋锁：应对 packages.list 在连续安装/多开应用时产生的瞬时并发多重写事件
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 0.1
    done
    do_sync
    release_lock "$LOCK_DIR"
}

# [启动清理] 强行释放由于异常死机或模块重启残留下来的锁结构与临时文件
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

# [功耗优化] 阻塞等待 boot_completed 属性激活，确保在系统开机高负载阶段后台脚本不抢占 CPU 调度
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 4; done

# 开机初次强制对齐
dispatch_sync

# ----------------------------------------------------------------------------
# 子服务组：双线程架构（1. 定时慢速网络轮询  2. 极速文件事件响应）
# ----------------------------------------------------------------------------

# [线程1：补丁定时更新] 12小时唤醒一次。通过长 sleep 降低定时器唤醒 CPU 的频率
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [线程2：实时监控响应] 
# [优化逻辑] 摒弃对 $BASE 目录的全局监控（防止触发自身文件操作导致回环死循环现象）
# [内核行为] 通过 inotifyd 多路复用精准捕获指定的两个文件写事件（w），仅在内核抛出中断信号时唤醒，零轮询功耗
start_monitor() {
    (
        while true; do
            [ -f "$WATCH_FILE" ] || touch "$WATCH_FILE" 
            [ -f "$TAA_SYS" ] || touch "$TAA_SYS"

            inotifyd - "$WATCH_FILE:w" "$TAA_SYS:w" 2>/dev/null | while read -r _; do
                dispatch_sync
            done
            sleep 3 # 保守容错，防止因文件被系统强制重建导致 inotifyd 异常中断时引发死循环
        done
    ) &
    echo $!
}

MONITOR_PID=$(start_monitor)
echo $$ > "$MAIN_PID_FILE"

# 优雅终止机制：捕获系统的注销信号，确保卸载或更新模块时无常驻孤儿进程
trap 'kill $PATCH_PID $MONITOR_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# [守护心跳] 5分钟（300秒）轻量级存活检查，使用 kill -0 仅检测进程描述符是否存在，不产生任何计算负载
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR_PID 2>/dev/null; then
        MONITOR_PID=$(start_monitor)
    fi
done