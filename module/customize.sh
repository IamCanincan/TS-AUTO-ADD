#!/system/bin/sh
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "================================================"

. "$MODPATH/common.sh" 2>/dev/null || abort "无法加载 common.sh"

ui_print " "
ui_print "[1/5] 检查 inotify 支持状态"
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    abort "  错误: 未检测到系统提供 inotify 支持 (inotifywait/inotifyd)。"
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
ui_print "  可用监控组件: ${INOTIFY_CMD%% *} ($INOTIFY_MODE)"

ui_print " "
ui_print "[2/5] 探测后端并初始化工作目录"
detect_backend
ui_print "  检测到后端: $(backend_name)"
ui_print "  工作目录: $TAA_DIR"
mkdir -p "$TAA_DIR" 2>/dev/null || abort "  无法创建目录 $TAA_DIR"

if [ "$TAA_BACKEND" = "teesim" ]; then
    if [ -z "$AWK_CMD" ]; then
        ui_print "  [警告] 未找到 awk，TEE Simulator 配置将无法维护"
    fi
else
    if [ ! -f "$TARGET_FILE" ]; then
        touch "$TARGET_FILE" 2>/dev/null
        chmod 644 "$TARGET_FILE" 2>/dev/null
    fi
fi

migrate_rules
ui_print "  常驻列表: $RULES_FILE"

ui_print " "
ui_print "[3/5] 配置脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/post-fs-data.sh" 2>/dev/null
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[4/5] 清理旧版文件"
rm -rf "$TSTORE_DIR/.ts_lock" "$TSTORE_DIR/.ts_debounce" "$TSTORE_DIR/.ts_tmp" \
       "$TEESIM_DIR/.ts_lock" "$TEESIM_DIR/.ts_debounce" "$TEESIM_DIR/.ts_tmp" \
       "$TSTORE_DIR"/.ts_daemon*.pid "$TEESIM_DIR"/.ts_daemon*.pid 2>/dev/null
rm -f "$TSTORE_DIR/.last_month" "$TSTORE_DIR/.ts_fingerprint" "$TEESIM_DIR/.ts_fingerprint" 2>/dev/null
rm -f "$TSTORE_DIR/taa_sys.txt" 2>/dev/null
rm -f /data/adb/service.d/taa_resetprop.sh 2>/dev/null

ui_print " "
ui_print "[5/5] 运行初始同步"
run_sync "$MODPATH/module.prop" "${TAA_DIR}/.ts_tmp"
rc=$?
ui_print "  应用总数: $TAA_COUNT"
case "$rc" in
    0) ui_print "  写入完成。" ;;
    1) ui_print "  数据与现有配置一致。" ;;
    2) ui_print "  当前结果集为空或后端配置不可写，推迟至守护进程处理" ;;
esac

ui_print "================================================"
ui_print "  安装流程结束，需重启设备生效"
ui_print "================================================"
