#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 手动同步脚本
#=============================================================================

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
TS_TARGET="$TS_BASE/target.txt"
TEESIM_CONFIG="$TEESIM_BASE/config.json"

LOCK_DIR="$TS_BASE/.ts_lock"
TMP="$TS_BASE/.ts_tmp"

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

. "$MODDIR/common.sh" || {
    echo "[ERROR] 无法加载 common.sh" >&2
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 当前操作需要 root 权限" >&2
    exit 1
fi

echo "================================================"
echo "          TS-AUTO-ADD 手动同步工具"
echo "================================================"

acquire_lock "$LOCK_DIR" || exit 1

echo "[1/2] 正在提取与合并包名列表..."
ensure_taa_sys "$TAA_SYS_FILE"
mkdir -p "$TS_BASE" "$TEESIM_BASE" 2>/dev/null

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
user_count=$(echo "$user_list" | sed '/^$/d' | wc -l)
sys_count=$(cat "$TAA_SYS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)

echo "  系统白名单项数: $sys_count"
echo "  第三方应用项数: $user_count"

(cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d' > "$TMP" 2>/dev/null

if [ -s "$TMP" ]; then
    # 写入 TrickyStore 配置
    cp -f "$TMP" "$TS_TARGET" 2>/dev/null
    chmod 644 "$TS_TARGET" 2>/dev/null
    echo "[INFO] TrickyStore target.txt 更新成功"

    # 写入 TeeSim 配置 (仅更新 apps 节点)
    generate_teesim_json "$TMP" "$TEESIM_CONFIG"
    echo "[INFO] TeeSim config.json 更新成功"

    rm -f "$TMP" 2>/dev/null
else
    rm -f "$TMP" 2>/dev/null
    echo "[ERROR] 获取应用列表失败，操作中止"
fi

echo ""
echo "[2/2] 更新模块描述信息..."
current_time=$(date '+%H:%M')
new_desc="[系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time}]"

if update_module_prop "$PROP_FILE" "$new_desc"; then
    echo "[INFO] 模块描述更新成功"
fi

release_lock "$LOCK_DIR"

echo "================================================"
echo "  同步流程执行完毕"
echo "================================================"
exit 0