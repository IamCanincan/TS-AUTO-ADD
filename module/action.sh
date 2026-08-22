#!/system/bin/sh
#==============================================================================
# action.sh - 手动同步工具（支持 --status, --log, --stop）
#==============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
. "$MODDIR/common.sh" || { echo "❌ 无法加载 common.sh"; exit 1; }

[ "$(id -u)" -ne 0 ] && { echo "❌ 需要 root 权限"; exit 1; }

# 检测环境（仅用于获取 TARGET_BASE 等）
detect_target_env >/dev/null 2>&1
env_status=$?
case $env_status in
    0|1) ;;
    *) echo "❌ 未检测到 TrickyStore 或 TeeSimulator 环境"; exit 1 ;;
esac

# ----------------------------- 子命令函数 ------------------------------------
show_status() {
    if [ -f "$TARGET_BASE/.ts_daemon_pids.list" ]; then
        pids=$(cat "$TARGET_BASE/.ts_daemon_pids.list" 2>/dev/null | tr '\n' ' ')
        alive=0
        for pid in $pids; do
            kill -0 "$pid" 2>/dev/null && alive=1
        done
        if [ "$alive" -eq 1 ]; then
            echo "✅ 守护进程运行中，PID: $pids"
            echo "   目标环境: $TARGET_TYPE"
            if [ -f "$TARGET_BASE/target.txt" ]; then
                echo "   最后同步: $(stat -c %y "$TARGET_BASE/target.txt" 2>/dev/null)"
            elif [ -f "$TARGET_BASE/config.json" ]; then
                echo "   最后同步: $(stat -c %y "$TARGET_BASE/config.json" 2>/dev/null)"
            fi
        else
            echo "⚠️ PID 文件存在但进程未运行"
        fi
    else
        echo "⚠️ 守护进程未运行"
    fi
}

stop_daemon() {
    local pids_file="$TARGET_BASE/.ts_daemon_pids.list"
    [ ! -f "$pids_file" ] && { echo "⚠️ 守护进程未运行"; return 0; }
    local pids=$(cat "$pids_file" 2>/dev/null | tr '\n' ' ')
    local stopped=0
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 0.5
            kill -9 "$pid" 2>/dev/null
            stopped=1
        fi
    done
    rm -f "$pids_file" 2>/dev/null
    if [ "$stopped" -eq 1 ]; then
        local stop_time="$(date '+%H:%M')"
        update_module_prop "$PROP_FILE" "⏹️ 已停止 (环境: ${TARGET_TYPE}) | 时间: ${stop_time}"
        echo "✅ 守护进程已停止，模块描述已更新"
    else
        echo "⚠️ 没有找到正在运行的守护进程"
    fi
}

# ----------------------------- 命令行参数处理 --------------------------------
case "$1" in
    --status|-s) show_status; exit 0 ;;
    --log|-l)
        if [ -f "$LOG_FILE" ]; then
            tail -n 20 "$LOG_FILE"
        else
            echo "⚠️ 日志文件不存在"
        fi
        exit 0 ;;
    --stop|-t) stop_daemon; exit 0 ;;
    --help|-h)
        echo "用法: $0 [--status|--log|--stop|--help]"
        echo "  --status   查看守护进程状态"
        echo "  --log      显示最近20条日志"
        echo "  --stop     停止守护进程"
        echo "  无参数     执行一次手动同步"
        exit 0 ;;
esac

# ----------------------------- 主同步流程 --------------------------------
echo "================================================"
echo "          TS-AUTO-ADD 手动同步"
echo "================================================"

detect_target_env >/dev/null 2>&1
case $? in
    0) env_name="TrickyStore" ;;
    1) env_name="TeeSimulator" ;;
    *)
        # 写入停止原因
        update_module_prop "$PROP_FILE" "⛔ 已停止: 未检测到目标环境"
        echo "❌ 未检测到 TrickyStore 或 TeeSimulator 环境"
        exit 1
        ;;
esac

# TeeSim 且 config.json 不存在则退出
if [ "$TARGET_TYPE" = "TEESIM" ] && [ ! -f "$TARGET_BASE/config.json" ]; then
    update_module_prop "$PROP_FILE" "⛔ 已停止: TeeSimulator config.json 不存在"
    echo "❌ TeeSimulator config.json 不存在，无法同步"
    exit 1
fi

lock_dir="$TARGET_BASE/.ts_lock"
tmp_file="$TARGET_BASE/.ts_tmp"

acquire_lock "$lock_dir" || { echo "❌ 获取锁失败"; exit 1; }

echo "▶ 目标环境: $env_name ($TARGET_BASE)"
ensure_taa_sys "$TAA_SYS_FILE"

user_list="$(get_installed_packages)"
user_count="$(count_lines "$user_list")"
sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"

echo "   系统白名单: $sys_count 项，第三方应用: $user_count 项"

if [ "$user_count" -eq 0 ]; then
    echo "⚠️ 第三方应用列表为空，跳过同步"
    release_lock "$lock_dir"
    exit 0
fi

merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
if [ -s "$tmp_file" ]; then
    if write_target_config "$tmp_file"; then
        echo "✅ 配置文件已更新"
    else
        echo "⚠️ 写入失败（可能 TeeSim 缺少 config.json）"
    fi
else
    echo "❌ 合并结果为空"
fi
rm -f "$tmp_file" 2>/dev/null

current_time="$(date '+%H:%M')"
new_desc="✅ 运行中 (环境: ${env_name} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time})"
update_module_prop "$PROP_FILE" "$new_desc"
echo "✅ 模块描述已更新"

release_lock "$lock_dir"
echo "================================================"
echo "✅ 同步完成"
echo "================================================"
exit 0