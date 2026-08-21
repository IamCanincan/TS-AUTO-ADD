#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 手动同步脚本（可通过 Magisk 管理器执行）
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || {
    echo "[ERROR] 无法加载 common.sh" >&2
    exit 1
}

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 需要 root 权限" >&2
    exit 1
fi

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

# 检测环境
detect_target_env
env_status=$?
case $env_status in
    0) target_env="TrickyStore" ;;
    1) target_env="TeeSimulator" ;;
    2) echo "[ERROR] TrickyStore 与 TeeSimulator 同时存在，无法执行" >&2; exit 1 ;;
    3) echo "[ERROR] 未检测到任何目标环境" >&2; exit 1 ;;
esac

lock_dir="$target_base/.ts_lock"
tmp_file="$target_base/.ts_tmp"

acquire_lock "$lock_dir" || {
    echo "[ERROR] 获取文件锁失败" >&2
    exit 1
}

echo "[1/2] 目标环境: $target_env"
echo "      配置目录: $target_base"

ensure_taa_sys "$taa_sys_file"

# 获取第三方应用列表
apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
sys_count=$(cat "$taa_sys_file" 2>/dev/null | sed '/^$/d' | wc -l)

echo "  系统白名单项数: $sys_count"
echo "  第三方应用项数: $user_count"

# 合并系统白名单与用户应用，去重
{
    cat "$taa_sys_file" 2>/dev/null
    echo "$user_list"
} | sort -u | sed '/^$/d' > "$tmp_file" 2>/dev/null

if [ -s "$tmp_file" ]; then
    write_target_config "$tmp_file"
    echo "[INFO] 目标配置文件更新完成"
else
    echo "[ERROR] 应用列表为空，同步失败" >&2
fi
rm -f "$tmp_file" 2>/dev/null

echo ""
echo "[2/2] 更新模块描述信息..."
current_time=$(date '+%H:%M')
new_desc="[环境: ${target_env} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
update_module_prop "$PROP_FILE" "$new_desc"
echo "[INFO] 模块描述更新成功"

release_lock "$lock_dir"

echo "================================================"
echo "  同步流程执行完毕"
echo "================================================"
exit 0