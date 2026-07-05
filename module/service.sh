#!/system/bin/sh
# 模块后台服务脚本: service.sh
# 功能: 开机启动，维持 target.txt 与 security_patch.txt 的自动同步。
#       包含应用列表更新、安全补丁定期刷新及 packages.list 变更监听。

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

# ---------- 工具函数 ----------

# 创建目录互斥锁，防止并发执行。
# 超时 30 秒后尝试强制清理残留锁并重建。
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

# 移除锁目录。
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

# 更新 module.prop 的 description 字段。
# 显示应用数、补丁日期及最后更新时间。
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

# 执行应用列表同步：收集三个 Google 包及所有第三方包，去重后写入 target.txt。
# 使用 sed '/^$/d' 过滤可能出现的空行。
do_sync() {
    mkdir -p "$BASE"
    {
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        pm list packages -3 2>/dev/null | sed -n 's/^package://p'
    } | sort -u | sed '/^$/d' > "$TMP"
    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            logger -t TrickyStore "target.txt updated"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
        logger -t TrickyStore "sync failed: empty list"
    fi
    update_module_status
}

# 带锁和防抖的同步调度：标记 PENDING，获取锁，处理多次触发合并，执行 do_sync。
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

# 提取 YYYY-MM-DD 格式的日期（年份 2020 及以后）。
clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

# 获取系统安全补丁日期并标准化为 05 日。
get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

# 若日期为 *-01，则替换为 *-05，以匹配安全公告发布日期。
# 其他日期保持不变。
force_to_05() {
    local in_date="$1"
    if [ -n "$in_date" ]; then
        case "$in_date" in
            *-01) echo "${in_date%-01}-05" ;;
            *) echo "$in_date" ;;
        esac
    fi
}

# 从给定 URL 获取 HTML，提取安全补丁日期。
# 优先匹配包含关键词的段落，否则返回首个符合格式的日期。
# 返回空值表示获取或解析失败。
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

# 比较两个日期，返回较新的日期。
# 若任一为空，则返回另一个。
pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    local n1=$(echo "$d1" | tr -d '-')
    local n2=$(echo "$d2" | tr -d '-')
    [ "$n1" -ge "$n2" ] && echo "$d1" || echo "$d2"
}

# 更新 security_patch.txt：取系统日期与在线获取日期的较新值写入。
# 使用 .last_month 缓存月份，避免重复请求。
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
        # 正常启动守护进程
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

# ---------- 清理旧进程 ----------
if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE")"
    kill "$old_pid" 2>/dev/null
    sleep 0.3
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null
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

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# 首次同步
do_sync

# ---------- 启动后台子进程 ----------
# 子进程 A：每 12 小时更新安全补丁
(
    update_security_patch
    while true; do
        sleep 43200
        update_security_patch
    done
) &
echo $! > "$PATCH_PID_FILE"

# 子进程 B：监听 packages.list 变更，触发同步
(
    trap 'release_lock; rm -f "$PENDING"; exit' EXIT INT TERM
    while true; do
        while [ ! -f "$WATCH_FILE" ]; do sleep 2; done
        inotifyd "$0" "$WATCH_FILE:w" >/dev/null 2>&1
        dispatch_sync
        sleep 1
    done
) &
echo $! > "$PID_FILE"

exit 0