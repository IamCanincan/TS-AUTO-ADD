#!/system/bin/sh
#=============================================================================
# lib/backend.sh - 后端探测、后端写入、模块描述、同步入口
#
# 后端（TEE Simulator 与 Tricky Store 互斥，前者优先）：
#   teesim -> /data/adb/teesim/config.json        仅替换 profiles.default.apps
#   tricky -> /data/adb/tricky_store/target.txt   整体重写为纯包名列表
#   写入实现分别位于 backends/teesim.awk 与 backends/tricky.sh
#=============================================================================

# ---------- 后端探测 ----------
# 说明：存在 teesim 配置时按 TEE Simulator 处理，否则按 Tricky Store 处理；
#       探测结果写入 core.sh 中的运行期变量，并在此加载对应后端实现。
# 用法：detect_backend <模块目录>
detect_backend() {
    local mdir="$1"

    TAA_PATCH="$mdir/backends/teesim.awk"

    if [ -f "$TEESIM_CONFIG" ]; then
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
    return 0
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
# 说明：把「后端 / 应用总数 / 更新时间」写回 module.prop 的 description 字段。
# 用法：update_module_desc <module.prop> <应用总数>
# 返回：0=成功 1=失败
update_module_desc() {
    local prop_file="$1" app_count="$2"
    local desc tmp_file

    [ -f "$prop_file" ] || return 1

    desc="[$(backend_name) | 应用: ${app_count} | 更新: $(date '+%H:%M')]"
    tmp_file="${prop_file}.tmp.$$"

    if sed "s/^description=.*/description=$desc/" "$prop_file" > "$tmp_file" 2>/dev/null; then
        cat "$tmp_file" > "$prop_file"
        rm -f "$tmp_file" 2>/dev/null
        return 0
    fi

    rm -f "$tmp_file" 2>/dev/null
    return 1
}

# ---------- 同步入口 ----------
# 说明：按当前后端写入目标文件，随后刷新模块描述；两者共用同一返回码语义。
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

    update_module_desc "$prop_file" "$TAA_COUNT"
    return "$rc"
}
