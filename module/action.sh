#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步工具（无联网）
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"
LOCK_DIR="$BASE/.ts_lock"
TMP="$BASE/.ts_tmp"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { echo " [错误] 无法加载 common.sh" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo " [错误] 需要 root 权限" >&2
    exit 1
fi

case "$1" in
    --force|-f) echo " [提示] 已移除在线补丁获取，--force 参数已无效果" ;;
    --help|-h)  echo "用法: $0"; exit 0 ;;
esac

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

acquire_lock "$LOCK_DIR" || exit 1

echo "[1/3] 正在提取应用列表..."
sync_target_list "$BASE" "$TARGET" "$TMP"
rc=$?

echo "  系统白名单应用数: $TAA_SYS_COUNT"
echo "  第三方用户应用数: $TAA_USER_COUNT"

case "$rc" in
    0) echo " [✓] target.txt 同步成功，总行数: $(wc -l < "$TARGET" 2>/dev/null || echo 0)" ;;
    1) echo " [i] 内容与现有配置一致，无需写入。" ;;
    2) echo " [✗] 错误：未能获取本地包名列表" ;;
esac

echo ""
echo "[2/3] 写入安全补丁配置（本地系统日期）..."
write_security_patch "$PATCH_CONFIG_FILE"
if [ $? -eq 0 ]; then
    echo " [✓] 补丁配置已就绪"
else
    echo " [警告] 补丁配置写入异常"
fi

echo ""
echo "[3/3] 更新模块描述..."
if update_module_desc "$PROP_FILE" "$PATCH_CONFIG_FILE" "$TAA_SYS_COUNT" "$TAA_USER_COUNT"; then
    echo " [✓] 模块描述已更新"
else
    echo " [✗] 描述更新失败"
fi

release_lock "$LOCK_DIR"
echo "================================================"
echo "  同步完成！"
echo "  系统应用数: $TAA_SYS_COUNT"
echo "  用户应用数: $TAA_USER_COUNT"
echo "  补丁信息: $(get_patch_details "$PATCH_CONFIG_FILE")"
echo "  更新时间: $(date '+%H:%M')"
echo "================================================"
exit 0
