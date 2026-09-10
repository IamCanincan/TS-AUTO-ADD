#!/system/bin/sh
#=============================================================================
# 公共函数库 (事件驱动版 · 无联网 · 双后端)
#
# 后端二选一（TEE Simulator 与 Tricky Store 互斥）：
#   teesim -> /data/adb/teesim/config.json     仅替换 profiles.default.apps
#   tricky -> /data/adb/tricky_store/target.txt
#=============================================================================

TSTORE_DIR="/data/adb/tricky_store"
TEESIM_DIR="/data/adb/teesim"
TEESIM_CONFIG="$TEESIM_DIR/config.json"

LOG_FILE="/data/adb/ts_auto.log"
LOCK_TIMEOUT=15

# 以下变量由 detect_backend 填充
TAA_BACKEND=""
TAA_DIR=""
RULES_FILE=""
TARGET_FILE=""
AWK_CMD=""
TAA_PATCH=""

# ---------- 后端探测 ----------
# 存在 /data/adb/teesim/config.json 时使用 TEE Simulator，否则使用 Tricky Store
# 用法：detect_backend <模块目录>
# 后端实现：tricky -> backends/tricky.sh（写 target.txt）；teesim -> backends/teesim.awk（改 config.json）
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
        if [ -f "$mdir/backends/tricky.sh" ]; then
            . "$mdir/backends/tricky.sh"
        else
            log_warn "缺少后端脚本 backends/tricky.sh"
        fi
    fi
    return 0
}

backend_name() {
    case "$TAA_BACKEND" in
        teesim) echo "TEE Simulator" ;;
        *)      echo "Tricky Store" ;;
    esac
}

# ---------- 日志记录 ----------
# 日志置于 /data/adb（root 专属），并强制 600 权限，避免被普通应用读取检测。
_log() {
    local level="$1" tag="$2"; shift 2
    local msg="[$tag] $(date '+%Y-%m-%d %H:%M:%S') $*"
    # 日志超过 256KB 时仅保留末尾 200 行，防止长期运行撑大磁盘
    if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')" -gt 262144 ]; then
        tail -n 200 "$LOG_FILE" > "${LOG_FILE}.rot" 2>/dev/null && mv -f "${LOG_FILE}.rot" "$LOG_FILE" 2>/dev/null
    fi
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    chmod 600 "$LOG_FILE" 2>/dev/null
    logger -t TS-AUTO -p "$level" "$*" 2>/dev/null || true
}
log_info() { _log info INFO "$@"; }
log_warn() { _log warn WARN "$@"; }
log_err()  { _log err  ERR  "$@"; }

# ---------- 并发锁管理 ----------
acquire_lock() {
    local lock_dir="$1"
    local waited=0
    while [ $waited -lt "$LOCK_TIMEOUT" ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    log_warn "锁获取超时，清理遗留锁目录: $lock_dir"
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# ---------- rules.txt（常驻应用列表，始终并入目标） ----------
ensure_rules_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
        chown root:root "$file" 2>/dev/null
        chcon system_data_file "$file" 2>/dev/null || true
    fi
}

# ---------- 生成期望应用列表 ----------
# rules.txt 常驻列表 + 已安装第三方应用，去重排序后写入 $1；总数存入 TAA_COUNT
build_app_list() {
    local tmp="$1"
    mkdir -p "$TAA_DIR" 2>/dev/null
    ensure_rules_file "$RULES_FILE"

    local apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    local user_list=$(echo "$apps_raw" | sed -n 's/^package://p')

    # 两段之间补一个空行再过滤空行，避免 rules.txt 末行缺换行符时与应用拼到同一行
    { cat "$RULES_FILE" 2>/dev/null; echo; echo "$user_list"; } | sort -u | sed '/^$/d' > "$tmp" 2>/dev/null

    TAA_COUNT=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')
}

# ---------- 定位可用的 awk ----------
find_awk() {
    if command -v awk >/dev/null 2>&1; then
        echo "awk"
        return 0
    fi
    local b
    for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$b" ] && "$b" awk 'BEGIN{}' >/dev/null 2>&1; then
            echo "$b awk"
            return 0
        fi
    done
    return 1
}

# ---------- TEE Simulator 后端：仅替换 config.json 中 default profile 的 apps ----------
# 定点替换逻辑见 backends/teesim.awk；其它字段与其它 profile 原样保留，
# 无法可靠定位 apps 数组时返回 2，绝不写坏配置。
sync_teesim_config() {
    local config="$1" tmp="$2"
    # awk 可能在上次探测后才可用（如后装了 busybox），这里按需重探
    [ -n "$AWK_CMD" ] || AWK_CMD=$(find_awk)
    if [ ! -f "$config" ] || [ -z "$AWK_CMD" ] || [ ! -f "$TAA_PATCH" ]; then
        TAA_COUNT=0
        return 2
    fi

    build_app_list "$tmp"
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" 2>/dev/null
        TAA_COUNT=0
        return 2
    fi

    local out="${tmp}.json" status="${tmp}.status"
    rm -f "$out" "$status" 2>/dev/null
    $AWK_CMD -v listfile="$tmp" -v statusfile="$status" -f "$TAA_PATCH" "$config" > "$out" 2>/dev/null

    if [ "$(cat "$status" 2>/dev/null)" != "ok" ] || [ ! -s "$out" ]; then
        rm -f "$tmp" "$out" "$status" 2>/dev/null
        return 2
    fi
    if cmp -s "$out" "$config" 2>/dev/null; then
        rm -f "$tmp" "$out" "$status" 2>/dev/null
        return 1
    fi

    chmod 600 "$out" 2>/dev/null
    chown root:root "$out" 2>/dev/null
    rm -f "$tmp" "$status" 2>/dev/null
    mv -f "$out" "$config" 2>/dev/null || return 2
    return 0
}

# ---------- 模块描述更新 ----------
update_module_desc() {
    local prop_file="$1" app_count="$2"
    [ -f "$prop_file" ] || return 1
    local current_time=$(date '+%H:%M')
    local new_desc="[$(backend_name) | 应用: ${app_count} | 更新: ${current_time}]"
    local tmp_file="${prop_file}.tmp.$$"
    sed "s/^description=.*/description=$new_desc/" "$prop_file" > "$tmp_file" 2>/dev/null && {
        cat "$tmp_file" > "$prop_file"
        rm -f "$tmp_file"
        return 0
    }
    rm -f "$tmp_file"
    return 1
}

# ---------- 完整同步（按后端写入 + 刷新模块描述） ----------
# 用法：run_sync <module.prop 路径> <临时文件路径>
# 返回码：0=已写入；1=内容一致未写入；2=失败或结果为空
run_sync() {
    local prop_file="$1" tmp="$2" rc=2
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

# ---------- inotify 工具定位 ----------
find_inotify_cmd() {
    for cmd in "inotifywait" "/data/adb/magisk/busybox inotifywait" "/data/adb/ksu/bin/busybox inotifywait"; do
        if command -v ${cmd%% *} >/dev/null 2>&1; then
            if ${cmd%% *} --help 2>&1 | grep -q -e '-m' -e '--monitor'; then
                echo "inotifywait:${cmd}"
                return 0
            fi
        fi
    done
    for cmd in "inotifyd" "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd"; do
        if command -v ${cmd%% *} >/dev/null 2>&1; then
            if ${cmd%% *} --help 2>&1 | grep -q 'inotifyd'; then
                echo "inotifyd:${cmd}"
                return 0
            fi
        fi
    done
    return 1
}

# ---------- 系统属性伪装 ----------
apply_resetprop() {
    command -v resetprop >/dev/null 2>&1 || return 0
    local value="" name="" expected=""

    local PROPS_LIST="
ro.boot.vbmeta.device_state locked
ro.boot.verifiedbootstate green
ro.boot.flash.locked 1
ro.boot.veritymode enforcing
ro.boot.warranty_bit 0
ro.warranty_bit 0
ro.debuggable 0
ro.force.debuggable 0
ro.secure 1
ro.adb.secure 1
ro.build.type user
ro.build.tags release-keys
ro.vendor.boot.warranty_bit 0
ro.vendor.warranty_bit 0
vendor.boot.warranty_bit 0
"

    # 当前值缺失或与期望值不一致时才写入
    while read -r name expected; do
        [ -n "$name" ] && [ -n "$expected" ] || continue
        value="$(resetprop "$name" 2>/dev/null)"
        if [ -z "$value" ] || [ "$value" != "$expected" ]; then
            resetprop -n "$name" "$expected" 2>/dev/null
        fi
    done <<EOF
$PROPS_LIST
EOF

    # 属性值含特定特征时替换
    value="$(resetprop ro.bootloader 2>/dev/null)"
    case "$value" in *engineering*) resetprop -n ro.bootloader release 2>/dev/null ;; esac
    value="$(resetprop ro.build.description 2>/dev/null)"
    case "$value" in *test-keys*) resetprop -n ro.build.description release-keys 2>/dev/null ;; esac
}
