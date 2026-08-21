#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 模块安装程序
#=============================================================================

SKIPUNZIP=0

ui_print "================================================"
ui_print "          TS-AUTO-ADD 安装程序"
ui_print "================================================"

. "$MODPATH/common.sh" 2>/dev/null || abort "[ERROR] 无法加载 common.sh"

ui_print " "
ui_print "[1/5] 检查环境兼容性"

detect_target_env
env_status=$?

if [ "$env_status" -eq 2 ]; then
    abort "[ERROR] 检测到 TrickyStore 与 TeeSimulator 同时存在！本模块无法在冲突环境下安装。"
elif [ "$env_status" -eq 1 ]; then
    abort "[ERROR] 未检测到 TrickyStore 或 TeeSimulator，请先安装其中之一。"
fi

ui_print "  目标环境: $TARGET_TYPE ($TARGET_BASE)"

ui_print " "
ui_print "[2/5] 检查 inotify 依赖"
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    abort "[ERROR] 未检测到系统提供的 inotify 监控工具"
fi
ui_print "  可用监控组件: ${INOTIFY_INFO#*:}"

ui_print " "
ui_print "[3/5] 初始化目标工作目录与权限"
mkdir -p "$TARGET_BASE" 2>/dev/null

set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" "$MODPATH/action.sh" 2>/dev/null

if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    mkdir -p /data/adb/service.d 2>/dev/null
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    rm -f "$MODPATH/taa_resetprop.sh" 2>/dev/null
    ui_print "  系统属性注入脚本部署完成"
fi

ui_print " "
ui_print "[4/5] 生成初始配置"
ensure_taa_sys "$TAA_SYS_FILE"

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

ui_print "  系统白名单项数: $sys_count"
ui_print "  第三方应用项数: $user_count"

(cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$TARGET_BASE/.ts_tmp" 2>/dev/null

if [ -s "$TARGET_BASE/.ts_tmp" ]; then
    write_target_config "$TARGET_BASE/.ts_tmp"
    ui_print "  已成功写入 $TARGET_TYPE 配置文件"
else
    ui_print "  未提取到应用数据，延迟至首次启动时处理"
fi
rm -f "$TARGET_BASE/.ts_tmp" 2>/dev/null

ui_print " "
ui_print "[5/5] 更新模块描述"
current_time=$(date '+%H:%M')
new_desc="[环境: ${TARGET_TYPE} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
update_module_prop "$MODPATH/module.prop" "$new_desc"

ui_print "================================================"
ui_print "  安装完成，重启设备后生效"
ui_print "================================================"