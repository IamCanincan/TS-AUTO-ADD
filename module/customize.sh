#!/system/bin/sh
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序 (纯事件驱动)"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================"

# 加载公共函数
. "$MODPATH/common.sh" 2>/dev/null || abort "无法加载 common.sh"

ui_print " "
ui_print "[1/6] 检测 inotify 支持"
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    abort "  错误：未检测到 inotify 工具 (inotifywait/inotifyd)\n  此模块必须使用 inotify 事件驱动，请确保内核支持。"
fi
INOTIFY_MODE="${INOTIFY_INFO%%:*}"
INOTIFY_CMD="${INOTIFY_INFO#*:}"
ui_print "  检测到可用监控: ${INOTIFY_CMD%% *} (模式: $INOTIFY_MODE)"

ui_print " "
ui_print "[2/6] 检查并创建工作目录"
BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR" 2>/dev/null || abort "  无法创建目录 $BASE_DIR"

if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
fi
ui_print "  工作目录已就绪"

ui_print " "
ui_print "[3/6] 设置核心脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[4/6] 清理历史残留"
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_debounce" "$BASE_DIR/.ts_tmp" "$BASE_DIR"/.ts_daemon*.pid 2>/dev/null

ui_print " "
ui_print "[5/6] 执行初始应用列表同步"
TAA_SYS_FILE="$BASE_DIR/taa_sys.txt"
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
    chmod 640 "$TAA_SYS_FILE" 2>/dev/null
    chown root:root "$TAA_SYS_FILE" 2>/dev/null
fi

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p' | sort -u)
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)

sys_list=$(cat "$TAA_SYS_FILE" 2>/dev/null | sort -u)
sys_count=$(echo "$sys_list" | sed '/^$/d' | wc -l)

ui_print "  系统白名单应用: $sys_count"
ui_print "  第三方用户应用: $user_count"

{
    echo "$sys_list"
    echo ""
    echo "$user_list"
} | sort -u | sed '/^$/d' > "$BASE_DIR/.ts_tmp" 2>/dev/null

if [ -s "$BASE_DIR/.ts_tmp" ]; then
    mv -f "$BASE_DIR/.ts_tmp" "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
    ui_print "  同步完成，总行数: $(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0)"
else
    rm -f "$BASE_DIR/.ts_tmp" 2>/dev/null
    ui_print "  获取为空，由守护进程后续处理"
fi

# 部署属性注入服务
if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    mkdir -p /data/adb/service.d 2>/dev/null
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    rm -f "$MODPATH/taa_resetprop.sh" 2>/dev/null
    ui_print "  属性注入服务已部署"
fi

ui_print " "
ui_print "[6/6] 更新模块描述"
# 初始化补丁文件（若无）
if [ ! -f "$BASE_DIR/security_patch.txt" ]; then
    echo "system=未知" > "$BASE_DIR/security_patch.txt"
    echo "boot=未知" >> "$BASE_DIR/security_patch.txt"
    echo "vendor=未知" >> "$BASE_DIR/security_patch.txt"
fi
patch_desc=$(get_patch_details "$BASE_DIR/security_patch.txt")
new_desc="[系统: ${sys_count} | 用户: ${user_count} | 补丁: ${patch_desc}]"
sed "s/^description=.*/description=$new_desc/" "$MODPATH/module.prop" > "$MODPATH/module.prop.tmp" 2>/dev/null
if [ $? -eq 0 ]; then
    cat "$MODPATH/module.prop.tmp" > "$MODPATH/module.prop"
    rm -f "$MODPATH/module.prop.tmp"
    ui_print "  模块描述已更新"
fi

ui_print "================================================"
ui_print "  安装完成！请重启设备生效。"
ui_print "  系统应用: $sys_count | 用户应用: $user_count"
ui_print "  补丁: $patch_desc"
ui_print "================================================"