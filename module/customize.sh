#!/system/bin/sh
#=============================================================================
# customize.sh - 安装脚本（框架固定调用，必须位于模块根目录）
#
# 流程：依赖检查 → 探测后端并初始化目录 → 配置权限 → 清理旧版残留 → 初始同步
#=============================================================================
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "================================================"

. "$MODPATH/lib/common.sh" 2>/dev/null || abort "无法加载 lib/common.sh"

# ---------- [1/5] 依赖检查 ----------
ui_print " "
ui_print "[1/5] 检查 inotify 支持"
INOTIFY_INFO=$(find_inotify_cmd)
[ -n "$INOTIFY_INFO" ] || abort "  错误：未检测到 inotifywait 或 inotifyd"
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
ui_print "  监听方式：$INOTIFY_MODE（${INOTIFY_CMD%% *}）"

# ---------- [2/5] 探测后端并初始化目录 ----------
ui_print " "
ui_print "[2/5] 探测后端并初始化目录"
detect_backend "$MODPATH"
mkdir -p "$TAA_DIR" 2>/dev/null || abort "  无法创建目录 $TAA_DIR"
ui_print "  后端：$(backend_name)"
ui_print "  目录：$TAA_DIR"

if [ "$TAA_BACKEND" = "teesim" ]; then
    [ -n "$AWK_CMD" ] || ui_print "  [警告] 未找到 awk，TEE Simulator 配置将无法维护"
elif [ ! -f "$TARGET_FILE" ]; then
    touch "$TARGET_FILE" 2>/dev/null
    chmod 644 "$TARGET_FILE" 2>/dev/null
fi

# 继承旧版 taa_sys.txt 或另一后端目录中的 rules.txt
if [ ! -f "$RULES_FILE" ]; then
    if [ -f "$TSTORE_DIR/taa_sys.txt" ]; then
        cp -f "$TSTORE_DIR/taa_sys.txt" "$RULES_FILE" 2>/dev/null
    elif [ -f "$TSTORE_DIR/rules.txt" ]; then
        cp -f "$TSTORE_DIR/rules.txt" "$RULES_FILE" 2>/dev/null
    fi
    if [ -f "$RULES_FILE" ]; then
        chmod 640 "$RULES_FILE" 2>/dev/null
        chown root:root "$RULES_FILE" 2>/dev/null
    fi
fi
ui_print "  常驻列表：$RULES_FILE"

# ---------- [3/5] 脚本权限 ----------
ui_print " "
ui_print "[3/5] 配置脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/post-fs-data.sh" 2>/dev/null
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

# ---------- [4/5] 清理旧版残留 ----------
ui_print " "
ui_print "[4/5] 清理旧版文件"
rm -rf "$TSTORE_DIR/.ts_lock" "$TSTORE_DIR/.ts_debounce" "$TSTORE_DIR/.ts_tmp" \
       "$TEESIM_DIR/.ts_lock" "$TEESIM_DIR/.ts_debounce" "$TEESIM_DIR/.ts_tmp" \
       "$TSTORE_DIR"/.ts_daemon*.pid "$TEESIM_DIR"/.ts_daemon*.pid 2>/dev/null
rm -f "$TSTORE_DIR/.last_month" "$TSTORE_DIR/.ts_fingerprint" "$TEESIM_DIR/.ts_fingerprint" 2>/dev/null
rm -f "$TSTORE_DIR/taa_sys.txt" 2>/dev/null
rm -f /data/adb/service.d/taa_resetprop.sh 2>/dev/null

# ---------- [5/5] 初始同步 ----------
ui_print " "
ui_print "[5/5] 运行初始同步"
run_sync "$MODPATH/module.prop" "${TAA_DIR}/.ts_tmp"
rc=$?
ui_print "  应用总数：$TAA_COUNT"
case "$rc" in
    0) ui_print "  写入完成" ;;
    1) ui_print "  数据与现有配置一致" ;;
    2) ui_print "  结果为空或后端配置不可写，交由守护进程处理" ;;
esac

ui_print "================================================"
ui_print "  安装完成，重启后生效"
ui_print "================================================"
