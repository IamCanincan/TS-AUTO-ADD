#!/system/bin/sh
#=============================================================================
# 手动管理脚本 (action.sh)
# 功能: 手动全域抓取、防丢行重组并同步，强制校正白名单配置。
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"
LOCK_DIR="$BASE/.ts_lock"
PATCH_CACHE_FILE="$BASE/.last_month"
TMP="$BASE/.ts_tmp"

export PATH="/providers/active/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# ---------- 工具函数 ----------

acquire_lock() {
    local timeout=10
    while [ $timeout -gt 0 ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            return 0
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    echo " [错误] 无法获取锁，可能后台进程正在运行，请稍后重试。" >&2
    return 1
}

release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
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

get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
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

update_module_status() {
    [ -f "$PROP_FILE" ] || return 0
    local app_count=0
    [ -f "$BASE/target.txt" ] && app_count=$(wc -l < "$BASE/target.txt")
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

# ---------- 参数解析 ----------
FORCE_MODE=0
case "$1" in
    --force|-f)
        FORCE_MODE=1
        ;;
    --help|-h)
        echo "用法: $0 [--force]"
        echo "  --force  强制清除月份缓存，重新在线获取安全补丁日期"
        exit 0
        ;;
esac

# ---------- 主流程 ----------
clear
echo "===================================================="
echo "          TS-AUTO-ADD 全域手动同步工具"
echo "===================================================="
echo " 启动时间 : $(date '+%Y-%m-%d %H:%M:%S')"
echo " 工作路径 : $BASE"
echo "===================================================="

acquire_lock || exit 1

echo ""
echo "[阶段 1/2] 提取多域第三方包及系统白名单包名..."
echo "----------------------------------------------------"
mkdir -p "$BASE"

# 全域获取（包含各隔离域下的第三方独立实例包）
APPS_3=$(cmd package list packages -3 -u --user all 2>/dev/null | sed -n 's/^package://p')
APPS_3_COUNT=$(echo "$APPS_3" | wc -l)

TAA_SYS_FILE="$BASE/taa_sys.txt"
{
    # 强制进行防截断整合
    if [ -f "$TAA_SYS_FILE" ]; then
        cat "$TAA_SYS_FILE"
        echo ""
    else
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
    fi
    echo "$APPS_3"
} | sort -u | sed '/^$/d' > "$TMP"

if [ -s "$TMP" ]; then
    if ! cmp -s "$TMP" "$BASE/target.txt"; then
        mv -f "$TMP" "$BASE/target.txt"
        chmod 644 "$BASE/target.txt"
        echo " [信息] target.txt 已重构并更新（合并第三方应用数: $APPS_3_COUNT）"
    else
        rm -f "$TMP"
        echo " [信息] 全域包名列表无变动，跳过物理覆写"
    fi
    TOTAL_LINES=$(wc -l < "$BASE/target.txt")
    echo " [状态] 阶段 1 完成（当前 target.txt 总包数: $TOTAL_LINES）"
else
    rm -f "$TMP"
    echo " [错误] 获取列表异常，阶段 1 终止"
fi

echo ""
echo "[阶段 2/2] 同步安全补丁日期..."
echo "----------------------------------------------------"
SYSTEM_DATE=$(get_system_date)
if [ -z "$SYSTEM_DATE" ]; then
    echo " [错误] 无法定位系统内置安全补丁字段"
    release_lock
    exit 1
fi
echo "  系统补丁日期: $SYSTEM_DATE"

SYS_YM="${SYSTEM_DATE%-*}"
NEED_ONLINE=0

if [ -f "$PATCH_CACHE_FILE" ] && [ $FORCE_MODE -eq 0 ]; then
    CACHED_MONTH=$(cat "$PATCH_CACHE_FILE")
    if [ "$CACHED_MONTH" != "$SYS_YM" ]; then
        NEED_ONLINE=1
        echo "  月份已变化，将尝试在线获取"
    else
        echo "  缓存月份匹配（$CACHED_MONTH），跳过在线获取"
    fi
else
    NEED_ONLINE=1
fi

FINAL_DATE="$SYSTEM_DATE"
NET_DATE=""
if [ $NEED_ONLINE -eq 1 ]; then
    echo "  尝试从 Google 安全公告页面获取..."
    for url in "https://source.android.google.cn/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin"; do
        NET_DATE=$(fetch_online_date "$url")
        if [ -n "$NET_DATE" ]; then
            echo "  从 $url 获取到日期: $NET_DATE"
            break
        fi
    done
    if [ -n "$NET_DATE" ]; then
        NEWER=$(pick_newer "$SYSTEM_DATE" "$NET_DATE")
        if [ "$NEWER" = "$NET_DATE" ] && [ "$NET_DATE" != "$SYSTEM_DATE" ]; then
            FINAL_DATE="$NET_DATE"
            echo "  网络日期较新，采用: $FINAL_DATE"
        else
            echo "  系统日期较新或相同，保留系统日期: $SYSTEM_DATE"
        fi
        echo "$SYS_YM" > "$PATCH_CACHE_FILE"
    else
        echo "  [警告] 在线获取失败，回退使用系统日期: $SYSTEM_DATE"
    fi
else
    echo "  使用系统日期（未触发在线获取）"
fi

if [ -f "$PATCH_CONFIG_FILE" ]; then
    cp -f "$PATCH_CONFIG_FILE" "$PATCH_CONFIG_FILE.bak"
fi
cat << EOF > "$PATCH_CONFIG_FILE"
system=$FINAL_DATE
boot=$FINAL_DATE
vendor=$FINAL_DATE
EOF
chmod 644 "$PATCH_CONFIG_FILE"
chown root:root "$PATCH_CONFIG_FILE" 2>/dev/null

echo "  最终安全补丁配置："
echo "        +----------------------------------------+"
while IFS= read -r line; do
    printf "        | %-38s |\n" "$line"
done < "$PATCH_CONFIG_FILE"
echo "        +----------------------------------------+"
echo " [状态] 阶段 2 完成"

update_module_status
echo "  已更新 module.prop 描述信息"

release_lock
echo ""
echo "===================================================="
echo " [结束] 全域同步流程执行完毕"
echo "===================================================="
exit 0