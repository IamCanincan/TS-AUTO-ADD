#!/system/bin/sh
MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/lib/common.sh" || { echo "❌ 无法加载 common.sh"; exit 1; }
[ "$(id -u)" -ne 0 ] && { echo "❌ 需要 root 权限"; exit 1; }

detect_target_env >/dev/null 2>&1
env_status=$?
case $env_status in 0|1) ;; *) echo "❌ 未检测到目标环境"; exit 1 ;; esac

case "$1" in
    --status|-s) show_status; exit 0 ;;
    --log|-l)    if [ -f "$LOG_FILE" ]; then tail -n 20 "$LOG_FILE"; else echo "⚠️ 日志不存在"; fi; exit 0 ;;
    --stop|-t)   stop_daemon; exit 0 ;;
    --help|-h)   echo "用法: $0 [--status|--log|--stop|--help]"; exit 0 ;;
esac

# 手动同步
lock_dir="$TARGET_BASE/.ts_lock"
acquire_lock "$lock_dir" || { echo "❌ 获取锁失败"; exit 1; }
do_sync
release_lock "$lock_dir"
echo "✅ 手动同步完成"