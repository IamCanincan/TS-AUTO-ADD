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
    
    # 基础环境自愈
    if [ ! -f "$TAA_SYS_FILE" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
        chmod 644 "$TAA_SYS_FILE"
    fi

    # 管道流合并，降低 I/O 复写次数
    {
        cat "$TAA_SYS_FILE" 2>/dev/null
        echo ""
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    # 原子替换
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            log_info "target.txt 实时同步成功，行数: $(wc -l < "$TARGET")"
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
# 强制终止旧残留进程
for pid_file in "$BASE/.ts_daemon_b1.pid" "$BASE/.ts_daemon_b2.pid" "$BASE/.ts_patch.pid" "$MAIN_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$old_pid" ] && kill -9 "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi
done
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

# 阻塞等待 boot_completed，防止开机负载抢占
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 4; done

# 首次开机同步
log_info "首次开机对齐同步"
dispatch_sync

# ----------------------------------------------------------------------------
# 后台常驻子服务（独立双线程架构，避免死循环相互干扰）
# ----------------------------------------------------------------------------

# [线程 1：补丁定时更新] 12 小时完全唤醒一次，极低开销
(
    while true; do
        update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0
        sleep 43200
    done
) &
PATCH_PID=$!

# [线程 2：实时事件监听守护]
# 修复核心：
# 1. 放弃单文件 :w 监控，改用多路复用捕获 packages.list 及其父目录的写入和移动替换事件
# 2. 放弃对整个 BASE 目录的监控，精准直接锁定 taa_sys.txt，从而彻底切断回环耗电 Bug
start_monitor() {
    (
        while true; do
            # 确保目标文件存在，防止 inotifyd 因为找不到目标而直接挂死
            [ -f "$WATCH_FILE" ] || touch "$WATCH_FILE"
            [ -f "$TAA_SYS_FILE" ] || touch "$TAA_SYS_FILE"

            # 联动监听：监听 packages.list(含父目录mv事件) 和 taa_sys.txt
            # 任何应用安装引发的文件移入替换（m）或直接修改（w）均会瞬间唤醒
            inotifyd - "$WATCH_FILE:wm" "$WATCH_DIR:m" "$TAA_SYS_FILE:w" 2>/dev/null | while read -r event file_name; do
                # 如果是监控目录抛出的事件，仅当目标为 packages.list 时才处理，其余忽略（极省电）
                if [ -n "$file_name" ] && [ "$file_name" != "packages.list" ]; then
                    continue
                fi
                dispatch_sync
            done
            sleep 3 # 保守容错延迟，防止极端情况下出现空流死循环
        done
    ) &
    echo $!
}

MONITOR_PID=$(start_monitor)
echo $$ > "$MAIN_PID_FILE"

# 主进程优雅注销信号捕获
trap 'log_info "收到退出信号，清理并退出"; kill $PATCH_PID $MONITOR_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# ---------- 轻量级心跳健康维护 ----------
while true; do
    sleep 300
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁子进程异常关闭，重新拉起..."
        ( while true; do update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" 0; sleep 43200; done ) &
        PATCH_PID=$!
    fi
    if ! kill -0 $MONITOR_PID 2>/dev/null; then
        log_warn "事件监控进程异常关闭，重新拉起..."
        MONITOR_PID=$(start_monitor)
    fi
done