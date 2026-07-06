#!/system/bin/sh
#=============================================================================
# 后台服务脚本 (service.sh)
# 功能: 开机启动，维持 target.txt 与 security_patch.txt 的全自动化高保真同步。
# 机制: 优化了包名提取作用域，支持多用户、分身应用及非标准换行文本的完整解析。
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"
PID_FILE="${BASE}/.ts_daemon.pid"
PATCH_PID_FILE="${BASE}/.ts_patch.pid"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_BACKUP_FILE="$BASE/security_patch.txt.bak"
PATCH_CACHE_FILE="$BASE/.last_month"

# 强制补充完整的标准系统环境变量，保障后台进程的跨域权限
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
    local tmp_prop="${PROP_FILE}.tmp"
    rm -f "$tmp_prop"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            description=*) echo "description=${status_text}" >> "$tmp_prop" ;;
            *) echo "$line" >> "$tmp_prop" ;;
        esac
    done < "$PROP_FILE"
    mv -f "$tmp_prop" "$PROP_FILE" 2>/dev/null
    chmod 644 "$PROP_FILE" 2>/dev/null
}

# 核心同步逻辑：增强全域抓取，解决换行截断和多用户分身包遗漏问题
do_sync() {
    mkdir -p "$BASE"
    local TAA_SYS_FILE="$BASE/taa_sys.txt"
    {
        # 处理 taa_sys.txt：即使尾部缺失换行符，也能通过额外的 echo 补全流，防止最后一行丢失
        if [ -f "$TAA_SYS_FILE" ]; then
            cat "$TAA_SYS_FILE"
            echo "" 
        else
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        fi
        # --user all 抓取全域（主用户、应用双开、工作资料）;-u 包含冻结及隐藏应用
        cmd package list packages -3 -u --user all 2>/dev/null | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            logger -t TrickyStore "target.txt updated successfully"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
        logger -t TrickyStore "sync skipped: data fetch return empty"
    fi
    update_module_status
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock || { logger -t TrickyStore "lock failed, skip sync"; return 1; }
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
    local url="$1"
    local html=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 5 -Ls -A "$user_agent" "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 5 --no-check-certificate -U "$user_agent" -qO- "$url" 2>/dev/null)
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
    local raw_date_backup=$(echo "$all_dates" | sort -r | head -n 1)
    force_to_05 "$raw_date_backup"
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
    if [ -z "$SYSTEM_DATE" ]; then
        logger -t TrickyStore "Error: System patch date is empty."
        return 1
    fi
    local SYS_YEAR=$(echo "$SYSTEM_DATE" | cut -d'-' -f1)
    local SYS_MONTH=$(echo "$SYSTEM_DATE" | cut -d'-' -f2)
    local SYS_YM="${SYS_YEAR}-${SYS_MONTH}"

    local NEED_ONLINE=0
    if [ -f "$PATCH_CACHE_FILE" ]; then
        local CACHED_MONTH=$(cat "$PATCH_CACHE_FILE")
        [ "$CACHED_MONTH" != "$SYS_YM" ] && NEED_ONLINE=1
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
    logger -t TrickyStore "Security patch updated: $FINAL_DATE"
    update_module_status
}

# ---------- 主入口 ----------
case "$1" in
    "")
        ;;
    "--sync")
        dispatch_sync
        exit 0
        ;;
    *)
        dispatch_sync
        exit 0
        ;;
esac

# ---------- 清理历史进程树标记 ----------
if [ -f "$PID_FILE" ]; then
    old_pids="$(cat "$PID_FILE")"
    for p in $old_pids; do
        kill "$p" 2>/dev/null
        sleep 0.1
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
    done
    rm -f "$PID_FILE"
fi
if [ -f "$PATCH_PID_FILE" ]; then
    old_patch_pid="$(cat "$PATCH_PID_FILE")"
    kill "$old_patch_pid" 2>/dev/null
    sleep 0.3
    kill -0 "$old_patch_pid" 2>/dev/null && kill -9 "$old_patch_pid" 2>/dev/null
    rm -f "$PATCH_PID_FILE"
fi

rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# 开机完成首次同步
do_sync

# ---------- 后台常驻分支服务树 ----------

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
        while [ ! -f "$WATCH_FILE" ]; do sleep 2; done
        inotifyd "$0" "$WATCH_FILE:w" >/dev/null 2>&1
        dispatch_sync
        sleep 1
    done
) &
B1_PID=$!

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
        sleep 1
    done
) &
B2_PID=$!

echo "${B1_PID} ${B2_PID}" > "$PID_FILE"

exit 0