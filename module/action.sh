#!/system/bin/sh
#=============================================================================
# 手动管理脚本 (action.sh)
# 功能：手动同步 target.txt 并更新安全补丁日期
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"
LOCK_FILE="$BASE/.ts_lock"
PATCH_CACHE_FILE="$BASE/.last_month"
TMP="$BASE/.ts_tmp"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

if [ "$(id -u)" -ne 0 ]; then
    echo " [错误] 需要 root 权限" >&2
    exit 1
fi

# ---------- 锁 ----------
acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
        exec 200>"$LOCK_FILE"
        flock -w 30 200 || { echo " 获取锁超时"; return 1; }
        return 0
    else
        local timeout=30
        while [ $timeout -gt 0 ]; do
            if mkdir "$LOCK_FILE" 2>/dev/null; then return 0; fi
            sleep 1; timeout=$((timeout-1))
        done
        rmdir "$LOCK_FILE" 2>/dev/null; mkdir "$LOCK_FILE" 2>/dev/null || return 1
        return 0
    fi
}
release_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 200 2>/dev/null; exec 200>&-
    else
        rmdir "$LOCK_FILE" 2>/dev/null
    fi
}

# ---------- 工具函数 ----------
clean_date() { echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1; }
force_to_05() {
    local in_date="$1"
    [ -n "$in_date" ] || return
    case "$in_date" in *-01) echo "${in_date%-01}-05" ;; *) echo "$in_date" ;; esac
}
get_system_date() { force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"; }
fetch_online_date() {
    local url="$1" html=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
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
        [ -n "$raw_date" ] && { force_to_05 "$raw_date"; return; }
    fi
    force_to_05 "$(echo "$all_dates" | sort -r | head -n 1)"
}
pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    [ "$(echo "$d1" | tr -d '-')" -ge "$(echo "$d2" | tr -d '-')" ] && echo "$d1" || echo "$d2"
}
update_module_status() {
    [ -f "$PROP_FILE" ] || return 0
    local app_count=0
    [ -f "$BASE/target.txt" ] && app_count=$(wc -l < "$BASE/target.txt")
    local patch_date="未配置"
    [ -f "$PATCH_CONFIG_FILE" ] && patch_date=$(grep '^boot=' "$PATCH_CONFIG_FILE" | cut -d'=' -f2)
    [ -z "$patch_date" ] && patch_date="未知"
    sed -i "s@^description=.*@description=[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]@" "$PROP_FILE" 2>/dev/null
}

# ---------- 参数处理 ----------
FORCE_MODE=0
case "$1" in --force|-f) FORCE_MODE=1 ;; --help|-h) echo "用法: $0 [--force]"; exit 0 ;; esac

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"
acquire_lock || exit 1

echo ""
echo "[1/3] 获取应用列表"
mkdir -p "$BASE"
apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
[ -z "$apps_raw" ] && apps_raw=$(pm list packages -3 2>/dev/null)
{
    if [ -f "$BASE/taa_sys.txt" ]; then cat "$BASE/taa_sys.txt"; else printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"; fi
    echo ""
    echo "$apps_raw" | sed -n 's/^package://p'
} | sort -u | sed '/^$/d' > "$TMP"

if [ -s "$TMP" ]; then
    if ! cmp -s "$TMP" "$BASE/target.txt"; then
        mv -f "$TMP" "$BASE/target.txt"
        chmod 644 "$BASE/target.txt"
        echo " [✓] target.txt 已更新，行数: $(wc -l < "$BASE/target.txt")"
    else
        rm -f "$TMP"
        echo " [i] 内容未变化"
    fi
else
    rm -f "$TMP"
    echo " [✗] 获取包名失败"
fi

echo ""
echo "[2/3] 更新安全补丁日期"
SYSTEM_DATE=$(get_system_date)
if [ -z "$SYSTEM_DATE" ]; then
    echo " [✗] 无法获取系统补丁日期"
    release_lock; exit 1
fi
echo "  系统日期: $SYSTEM_DATE"

SYS_YM="${SYSTEM_DATE%-*}"
NEED_ONLINE=0
if [ -f "$PATCH_CACHE_FILE" ] && [ $FORCE_MODE -eq 0 ]; then
    [ "$(cat "$PATCH_CACHE_FILE")" != "$SYS_YM" ] && NEED_ONLINE=1
else
    NEED_ONLINE=1
fi

FINAL_DATE="$SYSTEM_DATE"
if [ $NEED_ONLINE -eq 1 ]; then
    echo "  从 AOSP 获取最新日期"
    NET_DATE=""
    retry=0
    while [ $retry -lt 3 ] && [ -z "$NET_DATE" ]; do
        for url in "https://source.android.google.cn/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin"; do
            NET_DATE=$(fetch_online_date "$url")
            [ -n "$NET_DATE" ] && break
        done
        [ -z "$NET_DATE" ] && { retry=$((retry+1)); sleep 2; }
    done
    if [ -n "$NET_DATE" ]; then
        NEWER=$(pick_newer "$SYSTEM_DATE" "$NET_DATE")
        if [ "$NEWER" = "$NET_DATE" ] && [ "$NET_DATE" != "$SYSTEM_DATE" ]; then
            FINAL_DATE="$NET_DATE"
            echo "  [✓] 使用网络日期: $FINAL_DATE"
        else
            echo "  [i] 系统日期较新或相同"
        fi
        echo "$SYS_YM" > "$PATCH_CACHE_FILE"
    else
        echo "  [⚠] 网络请求失败，保留系统日期"
    fi
else
    echo "  跳过网络请求（缓存命中）"
fi

cat << EOF > "$PATCH_CONFIG_FILE"
system=$FINAL_DATE
boot=$FINAL_DATE
vendor=$FINAL_DATE
EOF
chmod 644 "$PATCH_CONFIG_FILE"
echo "  补丁配置:"
cat "$PATCH_CONFIG_FILE"

echo ""
echo "[3/3] 更新模块描述"
update_module_status
echo "  描述已刷新"

release_lock
echo "================================================"
echo "  同步完成"
echo "================================================"
exit 0