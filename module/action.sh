#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步（管理器“操作”按钮入口）
#
# 用途：立即按当前后端写入一次应用列表，并刷新模块描述
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || { echo " [错误] 无法加载 lib/common.sh" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || { echo " [错误] 需要 root 权限" >&2; exit 1; }

case "$1" in
    --help|-h) echo "用法：$0"; exit 0 ;;
esac

detect_backend "$MODDIR"
TMP="${TAA_DIR}/.ts_tmp"
LOCK_DIR="${TAA_DIR}/.ts_lock"

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"
echo "  后端：$(backend_name)"
echo "  目标：$TARGET_FILE"
echo ""

acquire_lock "$LOCK_DIR" || { echo " [错误] 获取锁超时" >&2; exit 1; }

echo "[1/1] 正在同步应用列表..."
run_sync "$PROP_FILE" "$TMP"
rc=$?

echo "  应用总数：$TAA_COUNT"
case "$rc" in
    0) echo " [✓] 已更新，模块描述已刷新" ;;
    1) echo " [i] 内容与现有配置一致，无需写入" ;;
    2) echo " [✗] 失败：未能生成或写入应用列表" ;;
esac

release_lock "$LOCK_DIR"
echo "================================================"
echo "  同步完成"
echo "  应用总数：$TAA_COUNT"
echo "  更新时间：$(date '+%H:%M')"
echo "================================================"
exit 0
