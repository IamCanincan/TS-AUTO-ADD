#!/system/bin/sh
#=============================================================================
# 后台常驻同步守护服务 (service.sh)
# 功能：监听文件变化并同步 target.txt，定时更新安全补丁日期
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

# ---------- 日志 ----------
log_info() { logger -t TS-AUTO -p info "$*"; }
log_warn() { logger -t TS-AUTO -p warn "$*"; }
log_err()  { logger -t TS-AUTO -p err "$*"; }

# ---------- 锁（纯 mkdir 目录锁） ----------
acquire_lock() {
    local timeout=30
    local waited=0
    while [ $waited -lt $timeout ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    log_warn "锁获取超时，强制清理残留锁"
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
    return 0
}

release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null
}

# ---------- 模块描述更新 ----------
update_module_status() {
    [ -f "$PROP_FILE" ] || return 0
    local app_count=0
    [ -f "$TARGET" ] && app_count=$(wc -l < "$TARGET")
    local patch_date="未配置"
    if [ -f "$PATCH_CONFIG_FILE" ]; then
        patch_date=$(grep '^boot=' "$PATCH_CONFIG_FILE" | cut -d'=' -f2)
        [ -z "$patch_date" ] && patch_date="未知"
    fi
    local status_text="[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
    sed -i "s@^description=.*@description=${status_text}@" "$PROP_FILE" 2>/dev/null
}

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
    update_module_status
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock || { log_err "获取锁失败"; rm -f "$PENDING"; return 1; }
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 1
    done
    do_sync
    release_lock
}

# ---------- 安全补丁日期处理 ----------
clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

force_to_05() {
    local in_date="$1"
    [ -n "$in_date" ] || return
    case "$in_date" in *-01) echo "${in_date%-01}-05" ;; *) echo "$in_date" ;; esac
}

get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

fetch_online_date() {
    local url="$1" html="" patch=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 5 -m 10 -Ls -A "$user_agent" "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 10 --connect-timeout=5 --no-check-certificate -U "$user_agent" -qO- "$url" 2>/dev/null)
    else
        return 1
    fi
    patch=$(echo "$html" | sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' | head -n1)
    [ -n "$patch" ] && echo "$patch" || return 1
}

pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    [ "$(echo "$d1" | tr -d '-')" -ge "$(echo "$d2" | tr -d '-')" ] && echo "$d1" || echo "$d2"
}

update_security_patch() {
    local SYSTEM_DATE=$(get_system_date)
    [ -z "$SYSTEM_DATE" ] && { log_err "无法获取系统补丁日期"; return 1; }
    local SYS_YM="${SYSTEM_DATE%-*}"
    local NEED_ONLINE=0
    if [ -f "$PATCH_CACHE_FILE" ]; then
        [ "$(cat "$PATCH_CACHE_FILE")" != "$SYS_YM" ] && NEED_ONLINE=1
    else
        NEED_ONLINE=1
    fi

    local FINAL_DATE="$SYSTEM_DATE"
    if [ "$NEED_ONLINE" -eq 1 ]; then
        local NET_DATE=""
        local retry=0
        while [ $retry -lt 3 ] && [ -z "$NET_DATE" ]; do
            for url in "https://source.android.com/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin/pixel"; do
                NET_DATE=$(fetch_online_date "$url")
                [ -n "$NET_DATE" ] && break
            done
            [ -z "$NET_DATE" ] && { retry=$((retry+1)); sleep 5; }
        done
        if [ -n "$NET_DATE" ]; then
            local NEWER=$(pick_newer "$SYSTEM_DATE" "$NET_DATE")
            if [ "$NEWER" = "$NET_DATE" ] && [ "$NET_DATE" != "$SYSTEM_DATE" ]; then
                FINAL_DATE="$NET_DATE"
                log_info "使用网络日期: $FINAL_DATE"
            else
                log_info "系统日期较新或相同: $SYSTEM_DATE"
            fi
            echo "$SYS_YM" > "$PATCH_CACHE_FILE"
        else
            log_warn "网络请求失败，使用系统日期"
        fi
    else
        log_info "缓存命中 ($SYS_YM)"
    fi

    [ -f "$PATCH_CONFIG_FILE" ] && cp -f "$PATCH_CONFIG_FILE" "$PATCH_BACKUP_FILE"
    cat << EOF > "$PATCH_CONFIG_FILE"
system=$FINAL_DATE
boot=$FINAL_DATE
vendor=$FINAL_DATE
EOF
    chmod 644 "$PATCH_CONFIG_FILE"
    chown root:root "$PATCH_CONFIG_FILE" 2>/dev/null
    update_module_status
    log_info "补丁配置写入: $FINAL_DATE"
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
        update_security_patch
        sleep 43200
    done
) &
PATCH_PID=$!

# 监控 packages.list 变化
(
    while true; do
        [ -f "$WATCH_FILE" ] || { sleep 5; continue; }
        inotifyd - "$WATCH_FILE:w" 2>/dev/null | while read -r _; do
            dispatch_sync
        done
        sleep 2
    done
) &
MONITOR1_PID=$!

# 监控 taa_sys.txt 变化
(
    TAA_SYS_FILE="$BASE/taa_sys.txt"
    while true; do
        if [ ! -f "$TAA_SYS_FILE" ]; then
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
            chmod 644 "$TAA_SYS_FILE"
        fi
        inotifyd - "$TAA_SYS_FILE:wy" 2>/dev/null | while read -r _; do
            dispatch_sync
        done
        sleep 2
    done
) &
MONITOR2_PID=$!   # 修复：使用 $! 获取PID

echo $$ > "$MAIN_PID_FILE"

# 主进程健康监管
trap 'log_info "收到退出信号，终止子进程"; kill $PATCH_PID $MONITOR1_PID $MONITOR2_PID 2>/dev/null; rm -f "$MAIN_PID_FILE"; exit' INT TERM

# 子进程重启计数器（防止频繁重启）
restart_count=0
max_restart=5
reset_interval=600  # 10分钟内超过5次则进入冷静期

while true; do
    sleep 60
    # 补丁进程
    if ! kill -0 $PATCH_PID 2>/dev/null; then
        log_warn "补丁进程重启 (计数 $restart_count)"
        ( while true; do update_security_patch; sleep 43200; done ) &
        PATCH_PID=$!
        restart_count=$((restart_count + 1))
    fi
    # 监控1
    if ! kill -0 $MONITOR1_PID 2>/dev/null; then
        log_warn "监控1 (packages.list) 重启 (计数 $restart_count)"
        (
            while true; do
                [ -f "$WATCH_FILE" ] || { sleep 5; continue; }
                inotifyd - "$WATCH_FILE:w" 2>/dev/null | while read -r _; do dispatch_sync; done
                sleep 2
            done
        ) &
        MONITOR1_PID=$!
        restart_count=$((restart_count + 1))
    fi
    # 监控2
    if ! kill -0 $MONITOR2_PID 2>/dev/null; then
        log_warn "监控2 (taa_sys.txt) 重启 (计数 $restart_count)"
        (
            TAA_SYS_FILE="$BASE/taa_sys.txt"
            while true; do
                [ -f "$TAA_SYS_FILE" ] || { printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"; chmod 644 "$TAA_SYS_FILE"; }
                inotifyd - "$TAA_SYS_FILE:wy" 2>/dev/null | while read -r _; do dispatch_sync; done
                sleep 2
            done
        ) &
        MONITOR2_PID=$!
        restart_count=$((restart_count + 1))
    fi

    # 若重启过于频繁，则进入冷静期（延长检查间隔）
    if [ $restart_count -ge $max_restart ]; then
        log_warn "子进程频繁重启，进入冷静期 10 分钟"
        sleep $reset_interval
        restart_count=0
    fi
done