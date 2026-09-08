#!/system/bin/sh
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "================================================"

. "$MODPATH/common.sh" 2>/dev/null || abort "无法加载 common.sh"

ui_print " "
ui_print "[1/6] 检查 inotify 支持状态"
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    abort "  错误: 未检测到系统提供 inotify 支持 (inotifywait/inotifyd)。"
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
ui_print "  可用监控组件: ${INOTIFY_CMD%% *} ($INOTIFY_MODE)"

ui_print " "
ui_print "[2/6] 初始化工作目录"
BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR" 2>/dev/null || abort "  无法创建目录 $BASE_DIR"

if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
fi
ui_print "  工作目录设置完毕"

ui_print " "
ui_print "[3/6] 配置脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[4/6] 清理旧版文件"
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_debounce" "$BASE_DIR/.ts_tmp" "$BASE_DIR"/.ts_daemon*.pid "$BASE_DIR/.last_month" 2>/dev/null
rm -f /data/adb/service.d/taa_resetprop.sh 2>/dev/null

ui_print " "
ui_print "[5/6] 运行初始列表生成"
sync_target_list "$BASE_DIR" "$BASE_DIR/target.txt" "$BASE_DIR/.ts_tmp"
rc=$?
ui_print "  系统白名单项数: $TAA_SYS_COUNT"
ui_print "  第三方应用项数: $TAA_USER_COUNT"
case "$rc" in
    0) ui_print "  数据写入完成。当前行数: $(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0)" ;;
    1) ui_print "  数据与现有配置一致。" ;;
    2) ui_print "  当前结果集为空，推迟至守护进程处理" ;;
esac

ui_print " "
ui_print "[6/6] 生成模块属性信息"
write_security_patch "$BASE_DIR/security_patch.txt"
if update_module_desc "$MODPATH/module.prop" "$BASE_DIR/security_patch.txt" "$TAA_SYS_COUNT" "$TAA_USER_COUNT"; then
    ui_print "  信息更新成功"
fi

ui_print "================================================"
ui_print "  安装流程结束，需重启设备生效"
ui_print "================================================"