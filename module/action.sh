#!/system/bin/sh
#=============================================================================
# action.sh - 手动同步（管理器“操作”按钮入口）
#
# 用途：立即按当前后端写入一次应用列表，并刷新模块描述
# 退出码：0=正常（含内容一致）；1=模块已停止、环境异常或写入失败
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || { echo " ❌ 无法加载 lib/common.sh" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || { echo " ❌ 需要 root 权限" >&2; exit 1; }

case "$1" in
    --help|-h) echo "用法：$0"; exit 0 ;;
esac

# ---------- 后端互斥检查 ----------
# 两者同时启用时不做任何处理：明确提示模块已停止，并把状态写进模块描述
if backends_conflict; then
    mark_module_stopped "$PROP_FILE"
    echo "================================================"
    echo "        ⛔ TS-AUTO-ADD 已停止"
    echo "================================================"
    echo "  $TAA_CONFLICT_MSG"
    echo "  该状态已写入模块描述，可在管理器界面查看。"
    echo "================================================"
    exit 1
fi

detect_backend "$MODDIR"
TMP="${TAA_DIR}/.ts_tmp"
LOCK_DIR="${TAA_DIR}/.ts_lock"

echo "================================================"
echo "        🚀 TS-AUTO-ADD 手动同步工具"
echo "================================================"
echo "  🔌 后端：$(backend_name)"
echo "  🎯 目标：$TARGET_FILE"
echo ""

acquire_lock "$LOCK_DIR" || { echo " ❌ 获取锁超时" >&2; exit 1; }

echo "🔄 [1/1] 正在同步应用列表..."
run_sync "$PROP_FILE" "$TMP"
rc=$?

case "$rc" in
    0) echo " ✅ 已更新（应用总数：$TAA_COUNT），模块描述已刷新" ;;
    1) echo " ℹ️ 内容与现有配置一致，无需写入（应用总数：$TAA_COUNT）" ;;
    2) echo " ❌ 写入失败：未能生成或写入应用列表，已记入模块描述" ;;
esac

release_lock "$LOCK_DIR"
echo "================================================"
[ "$rc" = "2" ] && echo "  ❌ 同步失败" || echo "  ✅ 同步完成"
echo "  🕒 更新时间：$(date '+%H:%M')"
echo "================================================"

[ "$rc" = "2" ] && exit 1
exit 0
