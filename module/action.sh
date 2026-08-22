#!/system/bin/sh
# action.sh - 用户交互命令（支持符号链接调用）

# 获取模块真实路径（即使通过符号链接调用）
if [ -L "$0" ]; then
    REAL_PATH="$(readlink -f "$0" 2>/dev/null)"
    if [ -n "$REAL_PATH" ]; then
        MODDIR="${REAL_PATH%/*}"
    else
        # 备选方案：使用 ls -l 解析
        MODDIR="$(ls -l "$0" | awk '{print $NF}' | sed 's/\/[^\/]*$//')"
    fi
else
    MODDIR="${0%/*}"
fi
# 如果解析出的 MODDIR 不是有效模块目录，尝试硬编码常见路径
if [ ! -d "$MODDIR/lib" ]; then
    [ -d "/data/adb/modules/ts-auto-add" ] && MODDIR="/data/adb/modules/ts-auto-add"
    [ -d "/data/adb/modules_update/ts-auto-add" ] && MODDIR="/data/adb/modules_update/ts-auto-add"
fi

export MODDIR
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 加载 common.sh（如果失败则显示错误并退出）
if [ -f "$MODDIR/lib/common.sh" ]; then
    . "$MODDIR/lib/common.sh" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "❌ 加载 common.sh 失败，请检查模块完整性"
        echo "   路径: $MODDIR/lib/common.sh"
        exit 1
    fi
else
    echo "❌ common.sh 不存在: $MODDIR/lib/common.sh"
    exit 1
fi

# 检查 root
[ "$(id -u)" -ne 0 ] && { echo "❌ 需要 root 权限"; exit 1; }

# 检测目标环境（不再隐藏输出）
detect_target_env
case $? in
    0) echo "✅ 检测到 TrickyStore" ;;
    1) echo "✅ 检测到 TeeSimulator" ;;
    2) echo "❌ 同时检测到 TrickyStore 与 TeeSimulator，冲突" ; exit 1 ;;
    3) echo "❌ 未检测到 TrickyStore 或 TeeSimulator" ; exit 1 ;;
esac

# 解析参数
case "$1" in
    --status|-s) show_status; exit 0 ;;
    --log|-l)    [ -f "$LOG_FILE" ] && tail -n 20 "$LOG_FILE" || echo "⚠️ 日志不存在"; exit 0 ;;
    --stop|-t)   stop_daemon; exit 0 ;;
    --help|-h)   echo "用法: $0 [--status|--log|--stop|--help]"; exit 0 ;;
esac

# 默认：手动同步
echo "🔄 开始手动同步..."
acquire_lock "$TARGET_BASE" || { echo "❌ 获取锁失败"; exit 1; }
do_sync
release_lock "$TARGET_BASE"
echo "✅ 手动同步完成"