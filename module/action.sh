#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步工具 (详细统计版)
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"
LOCK_DIR="$BASE/.ts_lock"
PATCH_CACHE_FILE="$BASE/.last_month"
TMP="$BASE/.ts_tmp"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { echo " [错误] 无法加载 common.sh" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo " [错误] 需要 root 权限" >&2
    exit 1
fi

FORCE_MODE=0
case "$1" in --force|-f) FORCE_MODE=1 ;; --help|-h) echo "用法: $0 [--force|-f]"; exit 0 ;; esac

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

acquire_lock "$LOCK_DIR" || exit 1

echo "[1/3] 正在提取应用列表..."
ensure_taa_sys "$TAA_SYS_FILE"

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p' | sort -u)
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)

sys_list=$(cat "$TAA_SYS_FILE" 2>/dev/null | sort -u)
sys_count=$(echo "$sys_list" | sed '/^$/d' | wc -l)

echo "  系统白名单应用数: $sys_count"
echo "  第三方用户应用数: $user_count"

{
    echo "$sys_list"
    echo ""
    echo "$user_list"
} | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null

if [ -s "$TMP" ]; then
    if ! cmp -s "$TMP" "$BASE/target.txt" 2>/dev/null; then
        mv -f "$TMP" "$BASE/target.txt" 2>/dev/null
        chmod 644 "$BASE/target.txt" 2>/dev/null
        echo " [✓] target.txt 同步成功，总行数: $(wc -l < "$BASE/target.txt" 2>/dev/null || echo 0)"
    else
        rm -f "$TMP" 2>/dev/null
        echo " [i] 内容与现有配置一致，无需写入。"
    fi
else
    rm -f "$TMP" 2>/dev/null
    echo " [✗] 严重错误：未能获取本地包名列表！"
fi

echo ""
echo "[2/3] 正在检测并刷新安全补丁配置..."
update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" "$FORCE_MODE"
if [ $? -eq 0 ]; then
    echo " [✓] 补丁配置已更新"
else
    echo " [警告] 补丁更新可能失败"
fi

echo ""
echo "[3/3] 更新模块描述..."
patch_desc=$(get_patch_details "$PATCH_CONFIG_FILE")
new_desc="[系统: ${sys_count} | 用户: ${user_count} | 补丁: ${patch_desc}]"
update_module_prop "$PROP_FILE" "$new_desc" && echo " [✓] 模块描述已更新" || echo " [✗] 描述更新失败"

release_lock "$LOCK_DIR"
echo "================================================"
echo "  同步完成！"
echo "  系统应用数: $sys_count"
echo "  用户应用数: $user_count"
echo "  补丁信息: $patch_desc"
echo "================================================"
exit 0