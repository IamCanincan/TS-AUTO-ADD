#!/system/bin/sh
# 系统属性重置
command -v resetprop >/dev/null 2>&1 || exit 0
[ -f "/data/adb/disable_prop_handler" ] && exit 0

check_reset_prop() {
    local key="$1" expected="$2" current
    current="$(resetprop "$key" 2>/dev/null)"
    [ -z "$current" ] || [ "$current" != "$expected" ] && resetprop -n "$key" "$expected" 2>/dev/null
}
contains_reset_prop() {
    local key="$1" match="$2" target="$3" current
    current="$(resetprop "$key" 2>/dev/null)"
    case "$current" in *"$match"*) resetprop -n "$key" "$target" 2>/dev/null ;; esac
}
empty_reset_prop() {
    local key="$1" target="$2" current
    current="$(getprop "$key" 2>/dev/null)"
    [ -z "$current" ] && resetprop -n "$key" "$target" 2>/dev/null
}

fetch_boot_hash() {
    local hash
    if [ -r "/proc/cmdline" ]; then
        hash="$(grep -oE 'androidboot\.vbmeta\.digest=[a-fA-F0-9]{64}' /proc/cmdline 2>/dev/null | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')"
        [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    fi
    if command -v dmesg >/dev/null 2>&1; then
        hash="$(dmesg 2>/dev/null | grep -iE 'vbmeta.*digest|digest.*vbmeta' | grep -oE '[a-fA-F0-9]{64}' | head -n 1 | tr '[:upper:]' '[:lower:]')"
        [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    fi
    hash="$(resetprop ro.boot.vbmeta.digest 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [ "${#hash}" -eq 64 ] && echo "$hash" && return 0
    return 1
}
detected_hash="$(fetch_boot_hash)"
[ -n "$detected_hash" ] && check_reset_prop "ro.boot.vbmeta.digest" "$detected_hash"

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

check_reset_prop "ro.vendor.boot.warranty_bit"               "0"
check_reset_prop "ro.vendor.warranty_bit"                    "0"
check_reset_prop "ro.vendor.boot.vbmeta.device_state"        "locked"
check_reset_prop "ro.vendor.boot.verifiedbootstate"          "green"
check_reset_prop "ro.vendor.boot.veritymode"                 "enforcing"
check_reset_prop "vendor.boot.vbmeta.device_state"           "locked"
check_reset_prop "vendor.boot.verifiedbootstate"             "green"
check_reset_prop "vendor.boot.veritymode"                    "enforcing"

check_reset_prop "ro.secureboot.lockstate"                   "locked"
check_reset_prop "ro.boot.realmebootstate"                   "green"
check_reset_prop "ro.boot.realme.lockstate"                  "1"
check_reset_prop "ro.boot.realme.flash.locked"               "1"
check_reset_prop "ro.is_ever_orange"                         "0"
check_reset_prop "ro.boot.is_ever_orange"                    "0"
check_reset_prop "ro.boot.hw.is_ever_orange"                 "0"
check_reset_prop "ro.boot.orange.state"                      "0"

contains_reset_prop "ro.bootmode"                 "recovery" "normal"
contains_reset_prop "ro.boot.bootmode"            "recovery" "normal"
contains_reset_prop "ro.vendor.boot.bootmode"     "recovery" "normal"
contains_reset_prop "vendor.boot.bootmode"        "recovery" "normal"
contains_reset_prop "ro.bootloader"               "engineering" "release"
contains_reset_prop "ro.build.description"        "test-keys" "release-keys"

for prop in $(resetprop | grep -oE 'ro.*\.build\.tags' 2>/dev/null); do
    check_reset_prop "$prop" "release-keys"
done
for prop in $(resetprop | grep -oE 'ro.*\.build\.type' 2>/dev/null); do
    check_reset_prop "$prop" "user"
done

empty_reset_prop "ro.boot.vbmeta.device_state"               "locked"
empty_reset_prop "ro.boot.vbmeta.invalidate_on_error"        "yes"
empty_reset_prop "ro.boot.vbmeta.avb_version"                "1.2"
empty_reset_prop "ro.boot.vbmeta.hash_alg"                   "sha256"
empty_reset_prop "ro.boot.vbmeta.size"                       "4096"

resetprop -n ro.build.flavor "" 2>/dev/null
resetprop -n ro.vendor.build.flavor "" 2>/dev/null

check_reset_prop "ro.system.build.type"      "user"
check_reset_prop "ro.system_ext.build.type"  "user"
check_reset_prop "ro.vendor.build.type"      "user"
check_reset_prop "ro.product.build.type"     "user"
check_reset_prop "ro.odm.build.type"         "user"

resetprop --delete sys.oem_unlock_allowed 2>/dev/null
resetprop -c >/dev/null 2>&1 || true
exit 0