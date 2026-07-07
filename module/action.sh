#!/system/bin/sh
#=============================================================================
# 手动管理脚本 (action.sh)
# 功能：手动同步 target.txt 并更新安全补丁日期
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"
LOCK_DIR="$BASE/.ts_lock"
PATCH_CACHE_FILE="$BASE/.last_month"
TMP="$BASE/.ts_tmp"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 加载公共函数库
. "$MODDIR/common.sh" || { echo "无法加载 common.sh" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo " [错误] 需要 root 权限" >&2
    exit 1
fi

# ---------- 参数处理 ----------
FORCE_MODE=0
case "$1" in --force|-f) FORCE_MODE=1 ;; --help|-h) echo "用法: $0 [--force]"; exit 0 ;; esac

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"
acquire_lock "$LOCK_DIR" || exit 1

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
update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" "$FORCE_MODE"

echo ""
echo "[3/3] 更新模块描述"
update_module_status "$PROP_FILE" "$BASE" "$PATCH_CONFIG_FILE"
echo "  描述已刷新"

release_lock "$LOCK_DIR"
echo "================================================"
echo "  同步完成"
echo "================================================"
exit 0