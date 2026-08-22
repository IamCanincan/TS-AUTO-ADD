#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 手动同步脚本
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || { echo "[ERROR] 无法加载 common.sh" >&2; exit 1; }

# 检查 root 权限
[ "$(id -u)" -ne 0 ] && { echo "[ERROR] 需要 root 权限" >&2; exit 1; }

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

# 检测环境
detect_target_env
env_status=$?
case $env_status in
    0) env_name="TrickyStore" ;;
    1) env_name="TeeSimulator" ;;
    2) echo "[ERROR] TrickyStore 与 TeeSimulator 同时存在" >&2; exit 1 ;;
    3) echo "[ERROR] 未检测到任何目标环境" >&2; exit 1 ;;
esac

lock_dir="$TARGET_BASE/.ts_lock"
tmp_file="$TARGET_BASE/.ts_tmp"

acquire_lock "$lock_dir" || { echo "[ERROR] 获取文件锁失败" >&2; exit 1; }

echo "[1/2] 目标环境: $env_name"
echo "      配置目录: $TARGET_BASE"

ensure_taa_sys "$TAA_SYS_FILE"

# 获取用户应用列表
user_list="$(get_installed_packages)"
user_count="$(echo "$user_list" | wc -l)"
sys_count="$( [ -f "$TAA_SYS_FILE" ] && cat "$TAA_SYS_FILE" | sed '/^$/d' | wc -l || echo 0 )"

echo "  系统白名单项数: $sys_count"
echo "  第三方应用项数: $user_count"

# 合并并写入临时文件
merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null

if [ -s "$tmp_file" ]; then
    write_target_config "$tmp_file"
    echo "[INFO] 目标配置文件更新完成"
else
    echo "[ERROR] 应用列表为空，同步失败" >&2
fi
rm -f "$tmp_file" 2>/dev/null

echo ""
echo "[2/2] 更新模块描述信息..."
current_time="$(date '+%H:%M')"
new_desc="[环境: ${env_name} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"
update_module_prop "$PROP_FILE" "$new_desc"
echo "[INFO] 模块描述更新成功"

release_lock "$lock_dir"

echo "================================================"
echo "  同步流程执行完毕"
echo "================================================"
exit 0