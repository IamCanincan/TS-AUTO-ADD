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
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_debounce" "$BASE_DIR/.ts_tmp" "$BASE_DIR"/.ts_daemon*.pid 2>/dev/null

ui_print " "
ui_print "[5/6] 运行初始列表生成"
TAA_SYS_FILE="$BASE_DIR/taa_sys.txt"
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
    chmod 640 "$TAA_SYS_FILE" 2>/dev/null
    chown root:root "$TAA_SYS_FILE" 2>/dev/null
fi

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

ui_print "  系统白名单项数: $sys_count"
ui_print "  第三方应用项数: $user_count"

(cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$BASE_DIR/.ts_tmp" 2>/dev/null

if [ -s "$BASE_DIR/.ts_tmp" ]; then
    mv -f "$BASE_DIR/.ts_tmp" "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
    ui_print "  数据写入完成。当前行数: $(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0)"
else
    rm -f "$BASE_DIR/.ts_tmp" 2>/dev/null
    ui_print "  当前结果集为空，推迟至守护进程处理"
fi

if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    mkdir -p /data/adb/service.d 2>/dev/null
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    rm -f "$MODPATH/taa_resetprop.sh" 2>/dev/null
    ui_print "  属性注入脚本部署完成"
fi

ui_print " "
ui_print "[6/6] 生成模块属性信息"
if [ ! -f "$BASE_DIR/security_patch.txt" ]; then
    echo "system=未知" > "$BASE_DIR/security_patch.txt"
    echo "boot=未知" >> "$BASE_DIR/security_patch.txt"
    echo "vendor=未知" >> "$BASE_DIR/security_patch.txt"
fi
patch_desc=$(get_patch_details "$BASE_DIR/security_patch.txt")
current_time=$(date '+%H:%M')
new_desc="[系统: ${sys_count} | 用户: ${user_count} | 补丁: ${patch_desc} | 更新: ${current_time}]"
sed "s/^description=.*/description=$new_desc/" "$MODPATH/module.prop" > "$MODPATH/module.prop.tmp" 2>/dev/null
if [ $? -eq 0 ]; then
    cat "$MODPATH/module.prop.tmp" > "$MODPATH/module.prop"
    rm -f "$MODPATH/module.prop.tmp"
    ui_print "  信息更新成功"
fi

ui_print "================================================"
ui_print "  安装流程结束，需重启设备生效"
ui_print "================================================"