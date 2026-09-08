#!/system/bin/sh
#=============================================================================
# 公共函数库 (事件驱动版 · 无联网)
#=============================================================================

RULES_FILE="/data/adb/tricky_store/rules.txt"
LOG_FILE="/data/adb/ts_auto.log"
LOCK_TIMEOUT=15

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

# ---------- rules.txt（常驻应用列表，始终并入 target.txt） ----------
ensure_rules_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
        chown root:root "$file" 2>/dev/null
        chcon system_data_file "$file" 2>/dev/null || true
    fi
}

# ---------- 应用列表同步 ----------
# 将 rules.txt 常驻列表与已安装第三方应用合并去重后写入 target.txt。
# 总数写入全局变量 TAA_COUNT。
# 返回码：0=已写入（内容变化）；1=内容一致未写入；2=结果为空。
sync_target_list() {
    local base="$1" target="$2" tmp="$3"
    mkdir -p "$base" 2>/dev/null
    ensure_rules_file "$RULES_FILE"

    local apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    local user_list=$(echo "$apps_raw" | sed -n 's/^package://p')

    # 两段之间补一个空行再过滤空行，避免 rules.txt 末行缺换行符时与应用拼到同一行
    { cat "$RULES_FILE" 2>/dev/null; echo; echo "$user_list"; } | sort -u | sed '/^$/d' > "$tmp" 2>/dev/null

    TAA_COUNT=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" 2>/dev/null
        TAA_COUNT=0
        return 2
    fi
    if cmp -s "$tmp" "$target" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    mv -f "$tmp" "$target" 2>/dev/null
    chmod 644 "$target" 2>/dev/null
    return 0
}

# ---------- 模块描述更新 ----------
update_module_desc() {
    local prop_file="$1" app_count="$2"
    [ -f "$prop_file" ] || return 1
    local current_time=$(date '+%H:%M')
    local new_desc="[应用: ${app_count} | 更新: ${current_time}]"
    local tmp_file="${prop_file}.tmp.$$"
    sed "s/^description=.*/description=$new_desc/" "$prop_file" > "$tmp_file" 2>/dev/null && {
        cat "$tmp_file" > "$prop_file"
        rm -f "$tmp_file"
        return 0
    }
    rm -f "$tmp_file"
    return 1
}

# ---------- 完整同步（写入 target.txt + 刷新模块描述） ----------
# 返回码同 sync_target_list：0=已写入；1=一致未写入；2=结果为空。
run_sync() {
    sync_target_list "$1" "$2" "$3"
    local rc=$?
    update_module_desc "$4" "$TAA_COUNT"
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
