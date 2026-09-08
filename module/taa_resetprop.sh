#!/system/bin/sh
#====================================================
# 系统属性注入脚本
#====================================================

# 检查 resetprop 命令可用性
if ! command -v resetprop >/dev/null 2>&1; then
    exit 0
fi

check_reset_prop() {
    local NAME="$1" EXPECTED="$2"
    local VALUE="$(resetprop "$NAME" 2>/dev/null)"
    if [ -z "$VALUE" ] || [ "$VALUE" != "$EXPECTED" ]; then
        resetprop -n "$NAME" "$EXPECTED" 2>/dev/null
    fi
}

contains_reset_prop() {
    local NAME="$1" CONTAINS="$2" NEWVAL="$3"
    local VALUE="$(resetprop "$NAME" 2>/dev/null)"
    case "$VALUE" in
        *"$CONTAINS"*) resetprop -n "$NAME" "$NEWVAL" 2>/dev/null ;;
    esac
}

# 核心属性配置列表，格式: [属性名] [期望值]
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

# 遍历列表并注入属性
echo "$PROPS_LIST" | while read -r name expected; do
    if [ -n "$name" ] && [ -n "$expected" ]; then
        check_reset_prop "$name" "$expected"
    fi
done

# 处理包含特定字符串的特殊属性
contains_reset_prop "ro.bootloader" "engineering" "release"
contains_reset_prop "ro.build.description" "test-keys" "release-keys"

exit 0