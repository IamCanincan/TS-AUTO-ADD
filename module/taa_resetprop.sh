#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 系统属性状态对齐（重置为锁定/正式版状态）
#=============================================================================

# 若 resetprop 不可用或存在禁用标记，则退出
command -v resetprop >/dev/null 2>&1 || exit 0
[ -f "/data/adb/disable_prop_handler" ] && exit 0

# ---------- 辅助函数 ----------
# 设置属性，仅当当前值不为目标值时更新
check_reset_prop() {
    local key="$1"
    local expected="$2"
    local current
    current="$(resetprop "$key" 2>/dev/null)"
    [ -z "$current" ] || [ "$current" != "$expected" ] && resetprop -n "$key" "$expected" 2>/dev/null
}

# 若属性包含匹配字符串，则替换为目标值
contains_reset_prop() {
    local key="$1"
    local match="$2"
    local target="$3"
    local current
    current="$(resetprop "$key" 2>/dev/null)"
    case "$current" in *"$match"*) resetprop -n "$key" "$target" 2>/dev/null ;; esac
}

# 若属性为空，则设置目标值
empty_reset_prop() {
    local key="$1"
    local target="$2"
    local current
    current="$(getprop "$key" 2>/dev/null)"
    [ -z "$current" ] && resetprop -n "$key" "$target" 2>/dev/null
}

# ---------- 1. 提取 Boot Hash ----------
fetch_boot_hash() {
    local hash
    # 从 /proc/cmdline 解析
    if [ -r "/proc/cmdline" ]; then
        hash="$(grep -oE 'androidboot\.vbmeta\.digest=[a-fA-F0-9]{64}' /proc/cmdline 2>/dev/null | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')"
        [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    fi
    # 从 dmesg 提取
    if command -v dmesg >/dev/null 2>&1; then
        hash="$(dmesg 2>/dev/null | grep -iE 'vbmeta.*digest|digest.*vbmeta' | grep -oE '[a-fA-F0-9]{64}' | head -n 1 | tr '[:upper:]' '[:lower:]')"
        [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    fi
    # 从 ro.boot.vbmeta.digest 属性
    hash="$(resetprop ro.boot.vbmeta.digest 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    return 1
}

detected_hash="$(fetch_boot_hash)"
[ -n "$detected_hash" ] && check_reset_prop "ro.boot.vbmeta.digest" "$detected_hash"

# ---------- 2. 基础验证属性 ----------
check_reset_prop "ro.boot.vbmeta.device_state"               "locked"
check_reset_prop "ro.boot.verifiedbootstate"                 "green"
check_reset_prop "ro.boot.flash.locked"                      "1"
check_reset_prop "ro.boot.veritymode"                        "enforcing"
check_reset_prop "ro.boot.warranty_bit"                      "0"
check_reset_prop "ro.warranty_bit"                           "0"
check_reset_prop "ro.debuggable"                             "0"
check_reset_prop "ro.force.debuggable"                       "0"
check_reset_prop "ro.secure"                                 "1"
check_reset_prop "ro.adb.secure"                             "1"
check_reset_prop "ro.build.type"                             "user"
check_reset_prop "ro.build.tags"                             "release-keys"
check_reset_prop "ro.boot.selinux"                           "enforcing"
check_reset_prop "sys.oem_unlock_allowed"                    "0"
check_reset_prop "ro.oem_unlock_supported"                   "0"

# Vendor 分区扩展
check_reset_prop "ro.vendor.boot.warranty_bit"               "0"
check_reset_prop "ro.vendor.warranty_bit"                    "0"
check_reset_prop "ro.vendor.boot.vbmeta.device_state"        "locked"
check_reset_prop "ro.vendor.boot.verifiedbootstate"          "green"
check_reset_prop "ro.vendor.boot.veritymode"                 "enforcing"
check_reset_prop "vendor.boot.vbmeta.device_state"           "locked"
check_reset_prop "vendor.boot.verifiedbootstate"             "green"
check_reset_prop "vendor.boot.veritymode"                    "enforcing"

# ---------- 3. 厂商特定属性 ----------
# Xiaomi / MIUI
check_reset_prop "ro.secureboot.lockstate"                   "locked"
# Realme
check_reset_prop "ro.boot.realmebootstate"                   "green"
check_reset_prop "ro.boot.realme.lockstate"                  "1"
check_reset_prop "ro.boot.realme.flash.locked"               "1"
# OPPO / OnePlus
check_reset_prop "ro.is_ever_orange"                         "0"
check_reset_prop "ro.boot.is_ever_orange"                    "0"
check_reset_prop "ro.boot.hw.is_ever_orange"                 "0"
check_reset_prop "ro.boot.orange.state"                      "0"

# ---------- 4. 启动模式与构建标签 ----------
contains_reset_prop "ro.bootmode"                 "recovery" "normal"
contains_reset_prop "ro.boot.bootmode"            "recovery" "normal"
contains_reset_prop "ro.vendor.boot.bootmode"     "recovery" "normal"
contains_reset_prop "vendor.boot.bootmode"        "recovery" "normal"
contains_reset_prop "ro.bootloader"               "engineering" "release"
contains_reset_prop "ro.build.description"        "test-keys" "release-keys"

# 批量修正所有 *build.tags 和 *build.type
for prop in $(resetprop | grep -oE 'ro.*\.build\.tags' 2>/dev/null); do
    check_reset_prop "$prop" "release-keys"
done
for prop in $(resetprop | grep -oE 'ro.*\.build\.type' 2>/dev/null); do
    check_reset_prop "$prop" "user"
done

# ---------- 5. 补全缺失的 VBMeta 属性 ----------
empty_reset_prop "ro.boot.vbmeta.device_state"               "locked"
empty_reset_prop "ro.boot.vbmeta.invalidate_on_error"        "yes"
empty_reset_prop "ro.boot.vbmeta.avb_version"                "1.2"
empty_reset_prop "ro.boot.vbmeta.hash_alg"                   "sha256"
empty_reset_prop "ro.boot.vbmeta.size"                       "4096"

# ---------- 6. 新增：清理 Flavor 与分区 Build.Type ----------
# 清除 LineageOS 等 ROM 的 flavor 节点
resetprop -n ro.build.flavor "" 2>/dev/null
resetprop -n ro.vendor.build.flavor "" 2>/dev/null

# 强制设定各分区 build.type 为 user（覆盖可能遗漏的分区）
check_reset_prop "ro.system.build.type"      "user"
check_reset_prop "ro.system_ext.build.type"  "user"
check_reset_prop "ro.vendor.build.type"      "user"
check_reset_prop "ro.product.build.type"     "user"
check_reset_prop "ro.odm.build.type"         "user"

# 删除 OEM 解锁状态属性（比赋值 0 更彻底）
resetprop --delete sys.oem_unlock_allowed 2>/dev/null

# 重置属性缓存
resetprop -c >/dev/null 2>&1 || true

exit 0