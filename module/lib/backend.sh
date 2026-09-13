#!/system/bin/sh
#=============================================================================
# lib/backend.sh - 后端探测、后端写入、模块描述、同步入口
#
# 后端（Tricky Store 与 TEE Simulator 互斥；两者同时启用时模块直接停止）：
#   teesim -> /data/adb/teesim/config.json        仅替换 profiles.default.apps
#   tricky -> /data/adb/tricky_store/target.txt   整体重写为纯包名列表
#   写入实现分别位于 backends/teesim.awk 与 backends/tricky.sh
#=============================================================================

# ---------- 模块探测 ----------
# 说明：按 /data/adb/modules 下的模块 id（目录名）判定：
#       Tricky Store / Tricky Store OSS 的模块 id 为 tricky_store
#       TEE Simulator v4+ 的模块 id 为 teesim
#       带 disable 标记表示被管理器停用，不计入；TEE Simulator 安装时会停用旧的
#       Tricky Store，因此这种“已停用的残留目录”不算冲突。
# 用法：teesim_active / tricky_active
# 返回：0=已安装且启用 1=未安装或已停用
teesim_active() {
    [ -d "$TEESIM_MODULE" ] && [ ! -f "$TEESIM_MODULE/disable" ]
}

tricky_active() {
    [ -d "$TRICKY_MODULE" ] && [ ! -f "$TRICKY_MODULE/disable" ]
}

# ---------- 后端冲突 ----------
# 说明：两个模块同时启用时不做任何处理，直接停止模块，不存在优先级；
#       各入口据此中止自身流程。
# 用法：backends_conflict
# 返回：0=两者同时启用 1=未冲突
backends_conflict() {
    teesim_active && tricky_active
}

# 冲突时的统一提示文案（各入口共用）
TAA_CONFLICT_MSG="检测到 Tricky Store 与 TEE Simulator 模块同时启用，模块停止运行（请停用或卸载其中一个）"

# ---------- 后端装载 ----------
# 说明：把运行期变量指向指定后端，并按需加载其写入实现。
# 用法：use_backend <teesim|tricky> <模块目录>
use_backend() {
    local mdir="$2"

    TAA_PATCH="$mdir/backends/teesim.awk"

    if [ "$1" = "teesim" ]; then
        TAA_BACKEND="teesim"
        TAA_DIR="$TEESIM_DIR"
        RULES_FILE="$TEESIM_DIR/rules.txt"
        TARGET_FILE="$TEESIM_CONFIG"
        AWK_CMD=$(find_awk)
    else
        TAA_BACKEND="tricky"
        TAA_DIR="$TSTORE_DIR"
        RULES_FILE="$TSTORE_DIR/rules.txt"
        TARGET_FILE="$TSTORE_DIR/target.txt"
        AWK_CMD=""
        # 仅在选用该后端时加载其写入实现，避免无用开销
        if [ -f "$mdir/backends/tricky.sh" ]; then
            . "$mdir/backends/tricky.sh"
        else
            log_warn "缺少后端脚本 backends/tricky.sh"
        fi
    fi
}

# ---------- 后端探测 ----------
# 说明：优先按已启用模块判定；两者都没有时，回退到配置文件判定
#       （兼容未装模块但已存在 teesim 配置的场景）。
# 用法：detect_backend <模块目录>
detect_backend() {
    if teesim_active; then
        use_backend teesim "$1"
    elif tricky_active; then
        use_backend tricky "$1"
    elif [ -f "$TEESIM_CONFIG" ]; then
        use_backend teesim "$1"
    else
        use_backend tricky "$1"
    fi
}

# ---------- 后端名称 ----------
# 说明：用于日志与模块描述展示
# 用法：backend_name
backend_name() {
    case "$TAA_BACKEND" in
        teesim) echo "TEE Simulator" ;;
        *)      echo "Tricky Store" ;;
    esac
}

# ---------- TEE Simulator 后端写入 ----------
# 说明：调用 backends/teesim.awk 定点替换 config.json 中 default profile 的 apps；
#       其它字段与其它 profile 原样保留；无法可靠定位数组时放弃写入，不改动原文件。
# 用法：sync_teesim_config <config.json> <临时文件>
# 返回：0=已写入 1=内容一致未写入 2=失败或结果为空
sync_teesim_config() {
    local config="$1" tmp="$2"
    local out="${tmp}.json" status="${tmp}.status"
    local rc=2

    TAA_COUNT=0
    # awk 可能在上次探测之后才可用（例如后装了 busybox），此处按需重探
    [ -n "$AWK_CMD" ] || AWK_CMD=$(find_awk)

    if [ -f "$config" ] && [ -n "$AWK_CMD" ] && [ -f "$TAA_PATCH" ]; then
        build_app_list "$tmp"
        [ -s "$tmp" ] && {
            # 生成替换后的内容；状态文件不是 "ok" 说明未定位到 apps 数组，保持原配置
            rm -f "$out" "$status" 2>/dev/null
            $AWK_CMD -v listfile="$tmp" -v statusfile="$status" -f "$TAA_PATCH" "$config" > "$out" 2>/dev/null

            if [ "$(cat "$status" 2>/dev/null)" = "ok" ] && [ -s "$out" ]; then
                if cmp -s "$out" "$config" 2>/dev/null; then
                    rc=1                       # 内容一致，无需落盘
                else
                    chmod 600 "$out" 2>/dev/null
                    chown root:root "$out" 2>/dev/null
                    mv -f "$out" "$config" 2>/dev/null && rc=0
                fi
            fi
        }
    fi

    rm -f "$tmp" "$out" "$status" 2>/dev/null
    return "$rc"
}

# ---------- 模块描述 ----------
# 说明：把 description 字段替换为指定文本（写入前先落临时文件，成功才覆盖）。
# 用法：set_module_desc <module.prop> <描述文本>
# 返回：0=成功 1=失败
set_module_desc() {
    local prop_file="$1" desc="$2"
    local tmp_file

    [ -f "$prop_file" ] || return 1

    tmp_file="${prop_file}.tmp.$$"
    if sed "s/^description=.*/description=$desc/" "$prop_file" > "$tmp_file" 2>/dev/null; then
        cat "$tmp_file" > "$prop_file"
        rm -f "$tmp_file" 2>/dev/null
        return 0
    fi

    rm -f "$tmp_file" 2>/dev/null
    return 1
}

# 说明：把运行状态写回 description：后端 / 应用总数 / 更新时间
# 用法：update_module_desc <module.prop> <应用总数>
# 返回：0=成功 1=失败
update_module_desc() {
    set_module_desc "$1" "✅ [$(backend_name) | 应用: $2 | 更新: $(date '+%H:%M')]"
}

# 说明：写入失败时把失败状态写进 description，避免界面仍显示成正常状态
# 用法：mark_module_failed <module.prop>
# 返回：0=成功 1=失败
mark_module_failed() {
    set_module_desc "$1" "⚠️ [$(backend_name) | 写入失败 | 更新: $(date '+%H:%M')]"
}

# 说明：因后端冲突停止运行时，把停止提示写进 description，
#       这样无需看日志，在管理器界面即可直接看到模块已停止。
# 用法：mark_module_stopped <module.prop>
# 返回：0=成功 1=失败
mark_module_stopped() {
    set_module_desc "$1" "⛔ [模块已停止 | Tricky Store 与 TEE Simulator 同时启用]"
}

# ---------- 同步入口 ----------
# 说明：按当前后端写入目标文件，随后刷新模块描述；写入失败时描述标注失败状态。
# 用法：run_sync <module.prop> <临时文件>
# 返回：0=已写入 1=内容一致未写入 2=失败或结果为空
run_sync() {
    local prop_file="$1" tmp="$2"
    local rc=2

    if [ "$TAA_BACKEND" = "teesim" ]; then
        sync_teesim_config "$TARGET_FILE" "$tmp"
        rc=$?
    elif command -v sync_target_list >/dev/null 2>&1; then
        sync_target_list "$TARGET_FILE" "$tmp"
        rc=$?
    else
        TAA_COUNT=0
    fi

    if [ "$rc" = "2" ]; then
        mark_module_failed "$prop_file"
    else
        update_module_desc "$prop_file" "$TAA_COUNT"
    fi
    return "$rc"
}
