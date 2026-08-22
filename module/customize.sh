#!/system/bin/sh
SKIPUNZIP=0
MODPATH="${0%/*}"
MODDIR="$MODPATH"
PROP_FILE="$MODPATH/module.prop"
export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 尽量加载 common.sh，若失败则定义最小函数集
if [ -f "$MODPATH/lib/common.sh" ]; then
    . "$MODPATH/lib/common.sh" 2>/dev/null || {
        ui_print() { echo "$*"; }
        abort() { echo "❌ $*"; exit 1; }
        print_info() { echo "▶ $*"; }
        print_ok() { echo "✓ $*"; }
        print_warn() { echo "⚠ $*" >&2; }
        print_err() { echo "✗ $*" >&2; }
        update_module_prop() { return 0; }
        detect_target_env() { return 3; }
        find_inotify_cmd() { return 1; }
    }
else
    ui_print() { echo "$*"; }
    abort() { echo "❌ $*"; exit 1; }
fi

ui_print "================================================"
ui_print "          TS-AUTO-ADD 安装程序"
ui_print "================================================"

ui_print "[1/3] 设置权限与创建链接"
chmod -R 755 "$MODPATH/lib" 2>/dev/null || true
chmod 755 "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" "$MODPATH/uninstall.sh" "$MODPATH/action.sh" 2>/dev/null || true
mkdir -p /data/adb 2>/dev/null || true
ln -sf "$MODPATH/action.sh" "/data/adb/ts-sync" 2>/dev/null || true
chmod 755 "/data/adb/ts-sync" 2>/dev/null || true

ui_print "[2/3] 检测目标环境（仅提示，不影响安装）"
detect_target_env >/dev/null 2>&1
env_status=$?
case $env_status in
    2) ui_print "  ⚠ 同时检测到 TrickyStore 与 TeeSimulator，可能冲突" ;;
    3) ui_print "  ⚠ 未检测到 TrickyStore 或 TeeSimulator，模块将无法工作" ;;
    0) ui_print "  ✅ 检测到 TrickyStore" ;;
    1) ui_print "  ✅ 检测到 TeeSimulator" ;;
esac

ui_print "[3/3] 更新模块描述（简要）"
current_time="$(date '+%H:%M')"
new_desc="✅ 已安装 (环境: ${TARGET_TYPE:-未检测} | 时间: ${current_time})"
update_module_prop "$MODPATH/module.prop" "$new_desc" 2>/dev/null || true

ui_print "================================================"
ui_print "  安装完成！"
ui_print "  注意：首次同步将在系统启动后自动执行"
ui_print "  手动同步: /data/adb/ts-sync"
ui_print "  停止服务: /data/adb/ts-sync --stop"
ui_print "  建议重启设备使服务生效"
ui_print "================================================"
exit 0