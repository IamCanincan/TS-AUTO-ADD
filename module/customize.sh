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
ui_print "[1/5] 检查系统环境依赖"
INOTIFY_INFO=$(find_inotify_cmd)
if [ -z "$INOTIFY_INFO" ]; then
    abort "[ERROR] 未检测到系统提供的 inotify 监控工具"
fi
ui_print "  可用监控组件: ${INOTIFY_INFO#*:}"

ui_print " "
ui_print "[2/5] 初始化目标工作目录"
TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
mkdir -p "$TS_BASE" "$TEESIM_BASE" 2>/dev/null

if [ ! -f "$TS_BASE/target.txt" ]; then
    touch "$TS_BASE/target.txt" 2>/dev/null
    chmod 644 "$TS_BASE/target.txt" 2>/dev/null
fi

ui_print " "
ui_print "[3/5] 配置文件与脚本权限"
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
ui_print "[4/5] 生成初始配置数据"
TAA_SYS_FILE="$TS_BASE/taa_sys.txt"
ensure_taa_sys "$TAA_SYS_FILE"

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

ui_print "  系统白名单项数: $sys_count"
ui_print "  第三方应用项数: $user_count"

(cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$TS_BASE/.ts_tmp" 2>/dev/null

if [ -s "$TS_BASE/.ts_tmp" ]; then
    cp -f "$TS_BASE/.ts_tmp" "$TS_BASE/target.txt" 2>/dev/null
    chmod 644 "$TS_BASE/target.txt" 2>/dev/null

    generate_teesim_json "$TS_BASE/.ts_tmp" "$TEESIM_BASE/config.json"
    ui_print "  双格式目标数据写入完成"
else
    ui_print "  未提取到应用数据，延迟至首次启动时处理"
fi
rm -f "$TS_BASE/.ts_tmp" 2>/dev/null

ui_print " "
ui_print "[5/5] 更新模块描述"
current_time=$(date '+%H:%M')
new_desc="[系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
update_module_prop "$MODPATH/module.prop" "$new_desc"

ui_print "================================================"
ui_print "  安装完成，重启设备后生效"
ui_print "================================================"