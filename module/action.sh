#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步工具
#=============================================================================

MODDIR="/data/adb/modules/ts-auto-add"
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

echo "[1/2] 正在提取与合并第三方应用包名..."
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
    chmod 640 "$TAA_SYS_FILE"
    chown root:root "$TAA_SYS_FILE" 2>/dev/null
    chcon system_data_file "$TAA_SYS_FILE" 2>/dev/null || \
    chcon u:object_r:adb_data_file:s0 "$TAA_SYS_FILE" 2>/dev/null || true
fi

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)

{
    cat "$TAA_SYS_FILE" 2>/dev/null
    echo ""
    echo "$apps_raw" | sed -n 's/^package://p'
} | sort -u | sed '/^$/d' > "$TMP"

if [ -s "$TMP" ]; then
    if ! cmp -s "$TMP" "$BASE/target.txt"; then
        mv -f "$TMP" "$BASE/target.txt"
        chmod 644 "$BASE/target.txt"
        echo " [✓] target.txt 同步成功，当前有效行数: $(wc -l < "$BASE/target.txt")"
    else
        rm -f "$TMP"
        echo " [i] 内容与现有配置一致，无需写入。"
    fi
else
    rm -f "$TMP"
    echo " [✗] 严重错误：未能获取本地包名列表！"
fi

echo ""
echo "[2/2] 正在检测并刷新安全补丁配置..."
update_security_patch_core "$BASE" "$PATCH_CONFIG_FILE" "$PATCH_CACHE_FILE" "$PROP_FILE" "$FORCE_MODE"

release_lock "$LOCK_DIR"
echo "================================================"
echo "  同步完成！"
echo "================================================"
exit 0