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
case $? in 0|1) ;; *) echo "❌ 无环境"; exit 1 ;; esac

case "$1" in
    --status|-s) show_status; exit 0 ;;
    --log|-l)    [ -f "$LOG_FILE" ] && tail -n 20 "$LOG_FILE" || echo "⚠️ 无日志"; exit 0 ;;
    --stop|-t)   stop_daemon; exit 0 ;;
    --help|-h)   echo "用法: $0 [--status|--log|--stop|--help]"; exit 0 ;;
esac

echo "🔄 手动同步..."
acquire_lock "$TARGET_BASE" || { echo "❌ 锁失败"; exit 1; }
do_sync
release_lock "$TARGET_BASE"
echo "✅ 完成"