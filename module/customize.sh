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
ui_print "[2/5] 初始化工作目录"
BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR" 2>/dev/null || abort "  无法创建目录 $BASE_DIR"

if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
fi

# 旧版 taa_sys.txt 迁移为 rules.txt（保留用户自定义内容）
if [ ! -f "$BASE_DIR/rules.txt" ] && [ -f "$BASE_DIR/taa_sys.txt" ]; then
    mv -f "$BASE_DIR/taa_sys.txt" "$BASE_DIR/rules.txt" 2>/dev/null
    chmod 640 "$BASE_DIR/rules.txt" 2>/dev/null
    chown root:root "$BASE_DIR/rules.txt" 2>/dev/null
fi
ui_print "  工作目录设置完毕"

ui_print " "
ui_print "[3/5] 配置脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/post-fs-data.sh" 2>/dev/null
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[4/5] 清理旧版文件"
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_debounce" "$BASE_DIR/.ts_tmp" "$BASE_DIR"/.ts_daemon*.pid "$BASE_DIR/.last_month" "$BASE_DIR/.ts_fingerprint" 2>/dev/null
rm -f "$BASE_DIR/taa_sys.txt" 2>/dev/null
rm -f /data/adb/service.d/taa_resetprop.sh 2>/dev/null

ui_print " "
ui_print "[5/5] 运行初始同步（生成 target.txt 与模块描述）"
run_sync "$BASE_DIR" "$BASE_DIR/target.txt" "$BASE_DIR/.ts_tmp" "$MODPATH/module.prop"
rc=$?
ui_print "  应用总数: $TAA_COUNT"
case "$rc" in
    0) ui_print "  数据写入完成。" ;;
    1) ui_print "  数据与现有配置一致。" ;;
    2) ui_print "  当前结果集为空，推迟至守护进程处理" ;;
esac

ui_print "================================================"
ui_print "  安装流程结束，需重启设备生效"
ui_print "================================================"
