#!/system/bin/sh
#====================================================
# 系统属性注入脚本
# 功能：检查并设置系统属性以模拟 locked 状态
#====================================================

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

check_reset_prop "ro.boot.vbmeta.device_state" "locked"
check_reset_prop "ro.boot.verifiedbootstate" "green"
check_reset_prop "ro.boot.flash.locked" "1"
check_reset_prop "ro.boot.veritymode" "enforcing"
check_reset_prop "ro.boot.warranty_bit" "0"
check_reset_prop "ro.warranty_bit" "0"
check_reset_prop "ro.debuggable" "0"
check_reset_prop "ro.force.debuggable" "0"
check_reset_prop "ro.secure" "1"
check_reset_prop "ro.adb.secure" "1"
check_reset_prop "ro.build.type" "user"
check_reset_prop "ro.build.tags" "release-keys"
check_reset_prop "ro.vendor.boot.warranty_bit" "0"
check_reset_prop "ro.vendor.warranty_bit" "0"
check_reset_prop "vendor.boot.warranty_bit" "0"

contains_reset_prop "ro.bootloader" "engineering" "release"
contains_reset_prop "ro.build.description" "test-keys" "release-keys"

exit 0