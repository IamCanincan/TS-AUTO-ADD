#!/system/bin/sh
#=============================================================================
# lib/common.sh - 通用函数库（事件驱动 · 无联网 · 双后端）
#
# 职责：
#   日志、并发锁、常驻列表、应用列表生成、模块描述、后端探测、属性伪装
#
# 后端（TEE Simulator 与 Tricky Store 互斥，前者优先）：
#   teesim -> /data/adb/teesim/config.json       仅替换 profiles.default.apps
#   tricky -> /data/adb/tricky_store/target.txt  整体重写为纯包名列表
#   后端写入实现分别位于 backends/teesim.awk 与 backends/tricky.sh
#=============================================================================

# ---------- 常量 ----------
TSTORE_DIR="/data/adb/tricky_store"
TEESIM_DIR="/data/adb/teesim"
TEESIM_CONFIG="$TEESIM_DIR/config.json"

LOG_FILE="/data/adb/ts_auto.log"
LOG_MAX_BYTES=262144          # 日志上限 256KB，超出后仅保留末尾若干行
LOG_KEEP_LINES=200
LOCK_TIMEOUT=15               # 锁等待上限（秒）

# ---------- 运行期状态 ----------
# 以下变量由 detect_backend 填充，其余为同步过程的中间结果
TAA_BACKEND=""                # 当前后端：teesim | tricky
TAA_DIR=""                    # 后端目录（rules.txt 与运行文件所在）
RULES_FILE=""                 # 常驻应用列表路径
TARGET_FILE=""                # 后端目标文件路径
AWK_CMD=""                     # 可用的 awk 命令（可能为空）
TAA_PATCH=""                  # TEE Simulator 定点替换脚本路径
TAA_COUNT=0                   # 最近一次生成的应用总数

# ---------- 后端探测 ----------
# 说明：TEE Simulator 与 Tricky Store 互斥，存在 teesim 配置时优先 TEE Simulator。
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

# 说明：返回当前后端名称，用于日志与模块描述
# 用法：backend_name
backend_name() {
    case "$TAA_BACKEND" in
        teesim) echo "TEE Simulator" ;;
        *)      echo "Tricky Store" ;;
    esac
}

# ---------- 日志 ----------
# 说明：日志置于 /data/adb（root 专属）并强制 600 权限，避免被普通应用读取；
#       同时通过 logger 写入系统日志。超过上限时截断为末尾若干行，防止长期运行撑大磁盘。
# 用法：log_info|log_warn|log_err <消息>
_log() {
    local level="$1" tag="$2"; shift 2
    local msg="[$tag] $(date '+%Y-%m-%d %H:%M:%S') $*"

    if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')" -gt "$LOG_MAX_BYTES" ]; then
        tail -n "$LOG_KEEP_LINES" "$LOG_FILE" > "${LOG_FILE}.rot" 2>/dev/null &&
            mv -f "${LOG_FILE}.rot" "$LOG_FILE" 2>/dev/null
    fi

    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    chmod 600 "$LOG_FILE" 2>/dev/null
    logger -t TS-AUTO -p "$level" "$*" 2>/dev/null || true
}
log_info() { _log info INFO "$@"; }
log_warn() { _log warn WARN "$@"; }
log_err()  { _log err  ERR  "$@"; }

# ---------- 并发锁 ----------
# 说明：用目录原子创建实现互斥；等待超时后清理疑似遗留的锁目录再重试一次。
# 用法：acquire_lock <锁目录>
# 返回：0=取得锁 1=失败
acquire_lock() {
    local lock_dir="$1"
    local waited=0

    while [ "$waited" -lt "$LOCK_TIMEOUT" ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    log_warn "锁等待超时，清理遗留锁目录：$lock_dir"
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

# 说明：释放锁目录
# 用法：release_lock <锁目录>
release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# ---------- 常驻列表 ----------
# 说明：rules.txt 不存在时写入默认白名单（Google 三件套）
# 用法：ensure_rules_file <rules.txt 路径>
ensure_rules_file() {
    local file="$1"

    [ -f "$file" ] && return 0

    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$file" 2>/dev/null
    chmod 640 "$file" 2>/dev/null
    chown root:root "$file" 2>/dev/null
    chcon system_data_file "$file" 2>/dev/null || true
}

# ---------- 应用列表生成 ----------
# 说明：常驻列表 + 已安装第三方应用，去重排序后写入指定文件，并设置 TAA_COUNT。
# 用法：build_app_list <输出文件>
build_app_list() {
    local tmp="$1"
    local apps_raw user_list

    mkdir -p "$TAA_DIR" 2>/dev/null
    ensure_rules_file "$RULES_FILE"

    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    user_list=$(echo "$apps_raw" | sed -n 's/^package://p')

    # 两段之间补一个空行再过滤空行：rules.txt 末行缺少换行符时不会与应用名拼到一起
    { cat "$RULES_FILE" 2>/dev/null; echo; echo "$user_list"; } | sort -u | sed '/^$/d' > "$tmp" 2>/dev/null

    TAA_COUNT=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')
}

# ---------- 工具定位 ----------
# 说明：定位可用的 awk（系统自带优先，其次各框架的 busybox）
# 用法：find_awk
# 返回：0=成功（命令写入标准输出）1=未找到
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

# 说明：定位 inotify 监控工具，优先 inotifywait
# 用法：find_inotify_cmd
# 返回：0=成功（输出 "模式:命令"）1=未找到
find_inotify_cmd() {
    local cmd

    for cmd in "inotifywait" "/data/adb/magisk/busybox inotifywait" "/data/adb/ksu/bin/busybox inotifywait"; do
        if command -v ${cmd%% *} >/dev/null 2>&1 &&
           ${cmd%% *} --help 2>&1 | grep -q -e '-m' -e '--monitor'; then
            echo "inotifywait:${cmd}"
            return 0
        fi
    done

    for cmd in "inotifyd" "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd"; do
        if command -v ${cmd%% *} >/dev/null 2>&1 &&
           ${cmd%% *} --help 2>&1 | grep -q 'inotifyd'; then
            echo "inotifyd:${cmd}"
            return 0
        fi
    done
    return 1
}

# ---------- TEE Simulator 后端写入 ----------
# 说明：调用 backends/teesim.awk 定点替换 config.json 中 default profile 的 apps；
#       其它字段与其它 profile 原样保留，无法可靠定位数组时放弃写入。
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
        if [ -s "$tmp" ]; then
            rm -f "$out" "$status" 2>/dev/null
            $AWK_CMD -v listfile="$tmp" -v statusfile="$status" -f "$TAA_PATCH" "$config" > "$out" 2>/dev/null

            if [ "$(cat "$status" 2>/dev/null)" = "ok" ] && [ -s "$out" ]; then
                if cmp -s "$out" "$config" 2>/dev/null; then
                    rc=1
                else
                    chmod 600 "$out" 2>/dev/null
                    chown root:root "$out" 2>/dev/null
                    mv -f "$out" "$config" 2>/dev/null && rc=0
                fi
            fi
        fi
    fi

    rm -f "$tmp" "$out" "$status" 2>/dev/null
    return "$rc"
}

# ---------- 模块描述 ----------
# 说明：把运行状态写入 module.prop 的 description 字段
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
# 说明：按当前后端写入目标文件，并刷新模块描述。
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

# ---------- 系统属性伪装 ----------
# 说明：逐项比对后写入期望值，已符合则不重复调用 resetprop；
#       另外对含特定特征值的属性做替换。供 post-fs-data.sh 在 Zygote 前调用。
# 用法：apply_resetprop
apply_resetprop() {
    local name="" expected="" value=""
    local PROPS_LIST

    command -v resetprop >/dev/null 2>&1 || return 0

    PROPS_LIST="
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

    # 每行形如「属性名 期望值」：当前值缺失或不同才写入
    while read -r name expected; do
        [ -n "$name" ] && [ -n "$expected" ] || continue
        value=$(resetprop "$name" 2>/dev/null)
        if [ -z "$value" ] || [ "$value" != "$expected" ]; then
            resetprop -n "$name" "$expected" 2>/dev/null
        fi
    done <<EOF
$PROPS_LIST
EOF

    # 值中含特定特征时整体替换
    value=$(resetprop ro.bootloader 2>/dev/null)
    case "$value" in
        *engineering*) resetprop -n ro.bootloader release 2>/dev/null ;;
    esac

    value=$(resetprop ro.build.description 2>/dev/null)
    case "$value" in
        *test-keys*) resetprop -n ro.build.description release-keys 2>/dev/null ;;
    esac
}
