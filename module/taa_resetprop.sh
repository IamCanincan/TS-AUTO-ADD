#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 系统属性修改脚本
#=============================================================================

if ! command -v resetprop >/dev/null 2>&1; then
    exit 0
fi

check_reset_prop() {
    local name="$1"
    local expected="$2"
    local value=""

    value="$(resetprop "$name" 2>/dev/null)"
    if [ -z "$value" ] || [ "$value" != "$expected" ]; then
        resetprop -n "$name" "$expected" 2>/dev/null
    fi
}

contains_reset_prop() {
    local name="$1"
    local contains="$2"
    local newval="$3"
    local value=""

    value="$(resetprop "$name" 2>/dev/null)"
    case "$value" in
        *"$contains"*) resetprop -n "$name" "$newval" 2>/dev/null ;;
    esac
}

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

echo "$PROPS_LIST" | while read -r name expected; do
    if [ -n "$name" ] && [ -n "$expected" ]; then
        check_reset_prop "$name" "$expected"
    fi
done

contains_reset_prop "ro.bootloader" "engineering" "release"
contains_reset_prop "ro.build.description" "test-keys" "release-keys"

exit 0