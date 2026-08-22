#!/system/bin/sh
#==============================================================================
# 文件: action.sh
# 描述: TS-AUTO-ADD 手动同步工具，用于立即执行一次应用列表同步
# 用法: action.sh [--status|--log|--help]
#==============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

# 加载公共函数库
. "$MODDIR/common.sh" || { print_err "无法加载 common.sh，请检查模块完整性"; exit 1; }

# 检查 root 权限
[ "$(id -u)" -ne 0 ] && { print_err "需要 root 权限，请使用 su 执行"; exit 1; }

# ----------------------------- 命令行参数处理 ------------------------------
case "$1" in
    --status|-s)
        # 显示守护进程状态
        if [ -f "$TARGET_BASE/.ts_daemon_pids.list" ]; then
            pids=$(cat "$TARGET_BASE/.ts_daemon_pids.list" 2>/dev/null | tr '\n' ' ')
            print_info "守护进程 PID: $pids"
            print_info "监控目标: $TARGET_TYPE"
            # 显示配置文件最后修改时间
            if [ -f "$TARGET_BASE/target.txt" ]; then
                print_info "最后同步时间: $(stat -c %y "$TARGET_BASE/target.txt" 2>/dev/null)"
            elif [ -f "$TARGET_BASE/config.json" ]; then
                print_info "最后同步时间: $(stat -c %y "$TARGET_BASE/config.json" 2>/dev/null)"
            fi
        else
            print_warn "守护进程未运行或 PID 文件不存在"
        fi
        exit 0
        ;;
    --log|-l)
        # 显示最近 20 条日志
        if [ -f "$LOG_FILE" ]; then
            tail -n 20 "$LOG_FILE"
        else
            print_warn "日志文件不存在"
        fi
        exit 0
        ;;
    --help|-h)
        echo "用法: $0 [选项]"
        echo "  --status, -s  查看守护进程状态"
        echo "  --log, -l     显示最近 20 条日志"
        echo "  --help, -h    显示此帮助"
        echo "  无参数则执行一次手动同步"
        exit 0
        ;;
esac

# ----------------------------- 主流程 -------------------------------------
echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

# 检测目标环境
detect_target_env
env_status=$?
case $env_status in
    0) env_name="TrickyStore" ;;
    1) env_name="TeeSimulator" ;;
    2) print_err "检测到 TrickyStore 与 TeeSimulator 同时存在，请禁用其中一个"; exit 1 ;;
    3) print_err "未检测到 TrickyStore 或 TeeSimulator 环境"; exit 1 ;;
esac

lock_dir="$TARGET_BASE/.ts_lock"
tmp_file="$TARGET_BASE/.ts_tmp"

# 获取锁，防止并发
acquire_lock "$lock_dir" || { print_err "获取文件锁失败，可能其他进程正在同步"; exit 1; }

print_info "目标环境: $env_name ($TARGET_BASE)"

# 确保系统白名单存在
ensure_taa_sys "$TAA_SYS_FILE"

# 获取用户应用列表
user_list="$(get_installed_packages)"
user_count="$(count_lines "$user_list")"
sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"

print_info "系统白名单项数: $sys_count"
print_info "第三方应用项数: $user_count"

# 若用户列表为空，跳过同步（防止清空配置）
if [ "$user_count" -eq 0 ]; then
    print_warn "第三方应用列表为空，可能系统未完全启动，跳过同步"
    release_lock "$lock_dir"
    exit 0
fi

# 合并并写入配置文件
merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
if [ -s "$tmp_file" ]; then
    write_target_config "$tmp_file" && print_ok "配置文件已更新" || print_warn "配置写入失败（可能 TeeSim 的 config.json 不存在）"
else
    print_err "应用列表为空，同步失败"
fi
rm -f "$tmp_file" 2>/dev/null

# 更新模块描述信息
current_time="$(date '+%H:%M')"
new_desc="[环境: ${env_name} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
update_module_prop "$PROP_FILE" "$new_desc"
print_ok "模块描述已更新"

release_lock "$lock_dir"

echo "================================================"
print_ok "同步流程执行完毕"
echo "================================================"
exit 0