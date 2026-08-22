#!/system/bin/sh
SKIPUNZIP=0
ui_print "================================================"
ui_print "          TS-AUTO-ADD 安装程序"
ui_print "================================================"

. "$MODPATH/lib/common.sh" 2>/dev/null || abort "❌ 无法加载 common.sh"

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

ui_print "[3/5] 初始化目录与权限"
mkdir -p "$TARGET_BASE" 2>/dev/null
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/post-fs-data.sh" 2>/dev/null
ln -sf "$MODPATH/action.sh" "/data/adb/ts-sync" 2>/dev/null
chmod 0755 "/data/adb/ts-sync" 2>/dev/null

ui_print "[4/5] 生成初始配置"
ensure_taa_sys "$TAA_SYS_FILE"
user_list="$(get_installed_packages)"
user_count="$(count_lines "$user_list")"
sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"
ui_print "  系统白名单: $sys_count 项，第三方应用: $user_count 项"

if [ "$user_count" -gt 0 ]; then
    tmp_file="$TARGET_BASE/.ts_tmp"
    merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
    if [ -s "$tmp_file" ]; then
        write_target_config "$tmp_file" && ui_print "  ✅ 已写入 $env_name 配置文件" || ui_print "  ⚠️ 写入失败"
    else
        ui_print "  ⚠️ 未获取到有效应用列表"
    fi
    rm -f "$tmp_file" 2>/dev/null
else
    ui_print "  ⚠️ 当前无第三方应用"
fi

ui_print "[5/5] 更新模块描述"
current_time="$(date '+%H:%M')"
new_desc="✅ 运行中 (环境: ${env_name} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time})"
update_module_prop "$MODPATH/module.prop" "$new_desc"

ui_print "================================================"
ui_print "  安装完成！"
ui_print "  手动同步: /data/adb/ts-sync"
ui_print "  停止服务: /data/adb/ts-sync --stop"
ui_print "  建议重启设备"
ui_print "================================================"