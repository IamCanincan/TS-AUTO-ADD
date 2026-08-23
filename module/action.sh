#!/system/bin/sh
# 获取模块真实路径
if [ -L "$0" ]; then
    REAL_PATH="$(readlink -f "$0" 2>/dev/null)"
    if [ -n "$REAL_PATH" ]; then
        MODDIR="${REAL_PATH%/*}"
    else
        MODDIR="$(ls -l "$0" | awk '{print $NF}' | sed 's/\/[^\/]*$//')"
    fi
else
    MODDIR="${0%/*}"
fi
[ ! -d "$MODDIR/lib" ] && [ -d "/data/adb/modules/ts-auto-add" ] && MODDIR="/data/adb/modules/ts-auto-add"
export MODDIR
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/lib/common.sh" || { echo "❌ 加载失败"; exit 1; }

[ "$(id -u)" -ne 0 ] && { echo "❌ 需要 root"; exit 1; }

detect_target_env
case $? in
    0) echo "✅ 检测到 TrickyStore" ;;
    1) echo "✅ 检测到 TeeSimulator" ;;
    2) echo "❌ 冲突"; exit 1 ;;
    3) echo "❌ 未检测到 TrickyStore 或 TeeSimulator"; echo "   请安装 TrickyStore 或 TeeSimulator 模块"; exit 1 ;;
esac

case "$1" in
    --status|-s) show_status; exit 0 ;;
    --log|-l)    [ -f "$LOG_FILE" ] && tail -n 20 "$LOG_FILE" || echo "⚠️ 无日志"; exit 0 ;;
    --stop|-t)   stop_daemon; exit 0 ;;
    --help|-h)   echo "用法: $0 [--status|--log|--stop|--help]"; exit 0 ;;
esac

echo "🔄 开始手动同步..."
# 尝试获取锁，若失败则强制清理后重试
if ! acquire_lock "$TARGET_BASE"; then
    echo "⚠️ 获取锁失败，尝试强制清理残留锁..."
    rmdir "$TARGET_BASE/.lock_dir" 2>/dev/null
    if ! acquire_lock "$TARGET_BASE"; then
        echo "❌ 获取锁失败，请检查权限或手动清理 $TARGET_BASE/.lock_dir"
        exit 1
    fi
fi
do_sync
release_lock "$TARGET_BASE"
echo "✅ 手动同步完成"