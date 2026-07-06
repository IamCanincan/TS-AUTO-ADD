#!/system/bin/sh
#=============================================================================
# 后台常驻同步守护服务 (service.sh)
# 功能：监控应用列表变化并同步 target.txt，定期更新安全补丁日期
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"

B1_PID_FILE="${BASE}/.ts_daemon_b1.pid"
B2_PID_FILE="${BASE}/.ts_daemon_b2.pid"
PATCH_PID_FILE="${BASE}/.ts_patch.pid"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_BACKUP_FILE="$BASE/security_patch.txt.bak"
PATCH_CACHE_FILE="$BASE/.last_month"

export PATH="/providers/active/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# ---------- 工具函数 ----------

acquire_lock() {
    local timeout=30
    while [ $timeout -gt 0 ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            return 0
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    logger -t TrickyStore "Lock timeout, force break stale lock."
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
    return 0
}

release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

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
    
    # 使用 @ 作为 sed 定界符，避免 status_text 中的竖线引起语法错误
    sed -i "s@^description=.*@description=${status_text}@" "$PROP_FILE" 2>/dev/null
}

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
        
        # 使用 cmd 或 pm 获取第三方应用包名列表，兼容 Android 10 及以上版本
        local apps_raw=""
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
        if [ -z "$apps_raw" ]; then
            apps_raw=$(pm list packages -3 2>/dev/null)
        fi
        echo "$apps_raw" | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            logger -t TrickyStore "target.txt successfully synced"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
    fi
    update_module_status
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock || { rm -f "$PENDING"; return 1; }
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 3
    done
    do_sync
    release_lock
}

clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

force_to_05() {
    local in_date="$1"
    if [ -n "$in_date" ]; then
        case "$in_date" in
            *-01) echo "${in_date%-01}-05" ;;
            *) echo "$in_date" ;;
        esac
    fi
}

fetch_online_date() {
    local url="$1" html=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
    
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 5 -m 10 -Ls -A "$user_agent" "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 10 --connect-timeout=5 --no-check-certificate -U "$user_agent" -qO- "$url" 2>/dev/null)
    else
        return 1
    fi
    
    local all_dates=$(echo "$html" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | grep -E '\-01$|\-05$')
    [ -z "$all_dates" ] && return 1
    local kv_lines=$(echo "$html" | grep -iE 'security patch level|安全补丁级别|bulletin|公告')
    if [ -n "$kv_lines" ]; then
        local raw_date=$(echo "$kv_lines" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | grep -E '\-01$|\-05$' | sort -r | head -n 1)
        if [ -n "$raw_date" ]; then
            force_to_05 "$raw_date"
            return
        fi
    fi
    force_to_05 "$(echo "$all_dates" | sort -r | head -n 1)"
}

pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    local n1=$(echo "$d1" | tr -d '-')
    local n2=$(echo "$d2" | tr -d '-')
    [ "$n1" -ge "$n2" ] && echo "$d1" || echo "$d2"
}

update_security_patch() {
    mkdir -p "$BASE"
    local SYSTEM_DATE=$(get_system_date)
    [ -z "$SYSTEM_DATE" ] && return 1
    
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
        for url in "https://source.android.google.cn/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin"; do
            NET_DATE=$(fetch_online_date "$url")
            [ -n "$NET_DATE" ] && break
        done
        if [ -n "$NET_DATE" ]; then
            local NEWER=$(pick_newer "$SYSTEM_DATE" "$NET_DATE")
            if [ "$NEWER" = "$NET_DATE" ] && [ "$NET_DATE" != "$SYSTEM_DATE" ]; then
                FINAL_DATE="$NET_DATE"
            fi
            echo "$SYS_YM" > "$PATCH_CACHE_FILE"
        fi
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
}

# ---------- 流程流控与事件边界 ----------
# 过滤命令行参数，仅允许空参数、--sync 或特定的单字符事件掩码，其他直接退出
case "$1" in
    "") ;; # 正常系统开机唤醒
    "--sync") dispatch_sync; exit 0 ;; # 终端手动强刷
    w|y|c|m|n) dispatch_sync; exit 0 ;; # 响应该内核事件掩码
    *) exit 0 ;; # 拦截其他未知参数
esac

for item in b1 b2 patch; do
    PID_F="${BASE}/.ts_daemon_${item}.pid"
    if [ -f "$PID_F" ]; then
        old_pid="$(cat "$PID_F")"
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null && sleep 0.1 && kill -9 "$old_pid" 2>/dev/null
        rm -f "$PID_F"
    fi
done
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

do_sync

# ---------- 后台常驻维护进程树 ----------

(
    update_security_patch
    while true; do
        sleep 43200
        update_security_patch
    done
) &
echo $! > "$PATCH_PID_FILE"

(
    trap 'release_lock; rm -f "$PENDING"; exit' EXIT INT TERM
    while true; do
        while [ ! -f "$WATCH_FILE" ]; do sleep 5; done
        inotifyd "$0" "$WATCH_FILE:w" >/dev/null 2>&1
        dispatch_sync
        sleep 2
    done
) &
echo $! > "$B1_PID_FILE"

(
    trap 'release_lock; rm -f "$PENDING"; exit' EXIT INT TERM
    local TAA_SYS_FILE="$BASE/taa_sys.txt"
    while true; do
        if [ ! -f "$TAA_SYS_FILE" ]; then
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
            chmod 0644 "$TAA_SYS_FILE"
        fi
        inotifyd "$0" "$TAA_SYS_FILE:wy" >/dev/null 2>&1
        dispatch_sync
        sleep 2
    done
) &
echo $! > "$B2_PID_FILE"

exit 0