#!/system/bin/sh
#=============================================================================
# lib/props.sh - 系统属性伪装
#=============================================================================

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
