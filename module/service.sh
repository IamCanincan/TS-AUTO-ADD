#!/system/bin/sh
#=============================================================================
# 后台服务脚本 (service.sh)
# 功能: 系统启动后在后台运行，对 target.txt 与 security_patch.txt 进行全自动同步。
# 监听机制: 利用内核 inotifyd 对配置文件和包名文件进行阻断式事件流监听。
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

#=============================================================================
# 工具函数
#=============================================================================

# 进程互斥锁：防止并发写入冲突，超时自动尝试清理并重建
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

# 释放互斥锁
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

# 更新 module.prop 的描述字段
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

# 核心合并行为：将 taa_sys.txt 的内容与第三方应用列表拼装并去重写入 target.txt
do_sync() {
    mkdir -p "$BASE"
    local TAA_SYS_FILE="$BASE/taa_sys.txt"
    {
        if [ -f "$TAA_SYS_FILE" ]; then
            cat "$TAA_SYS_FILE"
        else
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        fi
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

# 同步合并调度器：对短时间内的高频触发请求进行排队和去抖动合并
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

# 提取 YYYY-MM-DD 格式
clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

# 获取本地系统安全补丁日期属性
get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

# 规范补丁日为 05
force_to_05() {
    local in_date="$1"
    if [ -n "$in_date" ]; then
        case "$in_date" in
            *-01) echo "${in_date%-01}-05" ;;
            *) echo "$in_date" ;;
        esac
    fi
}

# 在线拉取 Google 的 Android 安全公告
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

# 比较并获取较新日期
pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    local n1=$(echo "$d1" | tr -d '-')
    local n2=$(echo "$d2" | tr -d '-')
    [ "$n1" -ge "$n2" ] && echo "$d1" || echo "$d2"
}

# 定时触发的安全补丁更新逻辑
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

#=============================================================================
# 脚本入口点解析
#=============================================================================
case "$1" in
    "")
        # 常规启动后台驻留服务
        ;;
    "--sync")
        # 外部单次强行执行同步的快捷入口
        dispatch_sync
        exit 0
        ;;
    *)
        dispatch_sync
        exit 0
        ;;
esac

#-----------------------------------------------------------------------------
# 环境初始化：终止并清理冲突进程及旧执行痕迹
#-----------------------------------------------------------------------------
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

# 等待 Android 框架完全就绪
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# 开机引导时执行基础同步
do_sync

#-----------------------------------------------------------------------------
# 分支子进程维护树
#-----------------------------------------------------------------------------

# 子进程 A: 安全补丁更新轮询时钟 (固定每 12 小时循环一次)
(
    update_security_patch
    while true; do
        sleep 43200
        update_security_patch
    done
) &
echo $! > "$PATCH_PID_FILE"

# 子进程 B: 实时监控事件常驻守护进程
(
    trap 'release_lock; rm -f "$PENDING"; exit' EXIT INT TERM
    local TAA_SYS_FILE="$BASE/taa_sys.txt"
    while true; do
        while [ ! -f "$WATCH_FILE" ]; do sleep 2; done
        
        # 当配置文件在运行时不存在，则执行补回
        if [ ! -f "$TAA_SYS_FILE" ]; then
            printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
            chmod 0644 "$TAA_SYS_FILE"
        fi
        
        # 核心事件双轨监听：
        # 1. $WATCH_FILE:w -> 监听应用安装或卸载引发的物理存储状态变更
        # 2. $TAA_SYS_FILE:wy -> 监听用户直接写入或通过第三方工具覆盖保存 taa_sys.txt 文件的行为
        inotifyd "$0" "$WATCH_FILE:w" "$TAA_SYS_FILE:wy" >/dev/null 2>&1
        dispatch_sync
        sleep 1
    done
) &
echo $! > "$PID_FILE"

exit 0