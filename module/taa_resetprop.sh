#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 系统属性与 Bootloader 状态覆写脚本
#=============================================================================

# 检查 resetprop 依赖与执行阻断标记
if ! command -v resetprop >/dev/null 2>&1 || [ -f "/data/adb/disable_prop_handler" ]; then
    exit 0
fi

# ---------- POSIX 标准功能函数 ----------

# 条件写入系统属性（仅当目标值与当前值不一致时执行）
check_reset_prop() {
    local key="$1"
    local expected="$2"
    local current=""

    current="$(resetprop "$key" 2>/dev/null)"
    if [ -z "$current" ] || [ "$current" != "$expected" ]; then
        resetprop -n "$key" "$expected" 2>/dev/null
    fi
}

# 子串匹配与属性值覆写
contains_reset_prop() {
    local key="$1"
    local match="$2"
    local target="$3"
    local current=""

    current="$(resetprop "$key" 2>/dev/null)"
    case "$current" in
        *"$match"*) resetprop -n "$key" "$target" 2>/dev/null ;;
    esac
}

# 空值检测与默认值写入
empty_reset_prop() {
    local key="$1"
    local target="$2"
    local current=""

    current="$(getprop "$key" 2>/dev/null)"
    if [ -z "$current" ]; then
        resetprop -n "$key" "$target" 2>/dev/null
    fi
}

# 自动获取 SHA-256 格式的 Boot Hash 值
fetch_boot_hash() {
    local hash=""

    # 1. 从 /proc/cmdline 内核启动参数提取
    if [ -r "/proc/cmdline" ]; then
        hash="$(grep -oE 'androidboot\.vbmeta\.digest=[a-fA-F0-9]{64}' /proc/cmdline 2>/dev/null | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')"
        if [ "${#hash}" -eq 64 ]; then
            echo "$hash"
            return 0
        fi
    fi

    # 2. 从 dmesg 内核运行日志提取
    if command -v dmesg >/dev/null 2>&1; then
        hash="$(dmesg 2>/dev/null | grep -iE 'vbmeta.*digest|digest.*vbmeta' | grep -oE '[a-fA-F0-9]{64}' | head -n 1 | tr '[:upper:]' '[:lower:]')"
        if [ "${#hash}" -eq 64 ]; then
            echo "$hash"
            return 0
        fi
    fi

    # 3. 从系统原生属性读取
    hash="$(resetprop ro.boot.vbmeta.digest 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    if [ "${#hash}" -eq 64 ]; then
        echo "$hash"
        return 0
    fi

    return 1
}

# ---------- 1. Boot Hash 自动获取与写入 ----------

detected_hash="$(fetch_boot_hash)"
if [ -n "$detected_hash" ]; then
    check_reset_prop "ro.boot.vbmeta.digest"                 "$detected_hash"
fi

# ---------- 2. 基础 Bootloader 与 Verified Boot 状态覆写 ----------

# AOSP 基础验证属性
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

# Vendor 分区节点（兼容 Android 12+ 架构）
check_reset_prop "ro.vendor.boot.warranty_bit"               "0"
check_reset_prop "ro.vendor.warranty_bit"                    "0"
check_reset_prop "ro.vendor.boot.vbmeta.device_state"        "locked"
check_reset_prop "ro.vendor.boot.verifiedbootstate"          "green"
check_reset_prop "vendor.boot.vbmeta.device_state"           "locked"
check_reset_prop "vendor.boot.verifiedbootstate"             "green"

# ---------- 3. 厂商特定启动验证属性覆写 ----------

# 小米 / MIUI / HyperOS 系列
check_reset_prop "ro.secureboot.lockstate"                   "locked"

# Realme 系列
check_reset_prop "ro.boot.realmebootstate"                   "green"
check_reset_prop "ro.boot.realme.lockstate"                  "1"
check_reset_prop "ro.boot.realme.flash.locked"               "1"

# 欧加 (OPPO / OnePlus / Realme) 系列
check_reset_prop "ro.is_ever_orange"                         "0"
check_reset_prop "ro.boot.is_ever_orange"                    "0"
check_reset_prop "ro.boot.hw.is_ever_orange"                 "0"
check_reset_prop "ro.boot.orange.state"                      "0"

# ---------- 4. 启动模式 (Bootmode) 属性修改 ----------

contains_reset_prop "ro.bootmode"                 "recovery" "normal"
contains_reset_prop "ro.boot.bootmode"            "recovery" "normal"
contains_reset_prop "ro.vendor.boot.bootmode"     "recovery" "normal"
contains_reset_prop "vendor.boot.bootmode"        "recovery" "normal"

contains_reset_prop "ro.bootloader"            "engineering" "release"
contains_reset_prop "ro.build.description"       "test-keys" "release-keys"

# ---------- 5. VBMeta 依赖属性补全 ----------

empty_reset_prop "ro.boot.vbmeta.device_state"               "locked"
empty_reset_prop "ro.boot.vbmeta.invalidate_on_error"        "yes"
empty_reset_prop "ro.boot.vbmeta.avb_version"                "1.2"
empty_reset_prop "ro.boot.vbmeta.hash_alg"                   "sha256"
empty_reset_prop "ro.boot.vbmeta.size"                       "4096"

exit 0