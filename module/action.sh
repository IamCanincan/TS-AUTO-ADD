#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步工具（双后端）
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { echo " [错误] 无法加载 common.sh" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo " [错误] 需要 root 权限" >&2
    exit 1
fi

case "$1" in
    --help|-h) echo "用法: $0"; exit 0 ;;
esac

detect_backend
TMP="${TAA_DIR}/.ts_tmp"

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"
echo "  后端: $(backend_name)"
echo "  目标: $TARGET_FILE"
echo ""

acquire_lock "${TAA_DIR}/.ts_lock" || exit 1

echo "[1/1] 正在同步应用列表..."
run_sync "$PROP_FILE" "$TMP"
rc=$?

echo "  应用总数: $TAA_COUNT"
case "$rc" in
    0) echo " [✓] 已更新，模块描述已刷新" ;;
    1) echo " [i] 内容与现有配置一致，无需写入" ;;
    2) echo " [✗] 错误：未能生成或写入应用列表" ;;
esac

release_lock "${TAA_DIR}/.ts_lock"
echo "================================================"
echo "  同步完成！"
echo "  应用总数: $TAA_COUNT"
echo "  更新时间: $(date '+%H:%M')"
echo "================================================"
exit 0
