#!/system/bin/sh
SKIPUNZIP=0
MODPATH="${0%/*}"
MODDIR="$MODPATH"
PROP_FILE="$MODPATH/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODPATH/lib/common.sh" 2>/dev/null || { echo "❌ 无法加载 common.sh"; exit 1; }

ui_print "================================================"
ui_print "          TS-AUTO-ADD 安装程序"
ui_print "================================================"

ui_print "[1/5] 检查环境兼容性"
detect_target_env
env_status=$?
case $env_status in
    2) abort "❌ 检测到 TrickyStore 与 TeeSimulator 同时存在" ;;
    3) abort "❌ 未检测到 TrickyStore 或 TeeSimulator" ;;
    0) env_name="TrickyStore" ;;
    1) env_name="TeeSimulator" ;;
esac
ui_print "  目标环境: $env_name ($TARGET_BASE)"

ui_print "[2/5] 检查 inotify 依赖"
inotify_info="$(find_inotify_cmd)"
[ -z "$inotify_info" ] && abort "❌ 未找到 inotify 监控工具"
ui_print "  可用组件: ${inotify_info#*:}"

ui_print "[3/5] 设置权限与创建链接"
chmod -R 755 "$MODPATH/lib" 2>/dev/null || true
chmod 755 "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" "$MODPATH/uninstall.sh" "$MODPATH/action.sh" 2>/dev/null || true
mkdir -p /data/adb 2>/dev/null || true
ln -sf "$MODPATH/action.sh" "/data/adb/ts-sync" 2>/dev/null || true
chmod 755 "/data/adb/ts-sync" 2>/dev/null || true

ui_print "[4/5] 生成初始配置（执行首次同步）"
do_sync || true

ui_print "[5/5] 更新模块描述（已在同步中更新）"

ui_print "================================================"
ui_print "  安装完成！"
ui_print "  手动同步: /data/adb/ts-sync"
ui_print "  停止服务: /data/adb/ts-sync --stop"
ui_print "  建议重启设备使服务生效"
ui_print "================================================"
exit 0