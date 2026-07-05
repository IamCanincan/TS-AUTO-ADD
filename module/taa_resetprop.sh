#!/system/bin/sh

# 检查并重置系统属性（若当前值不符合预期则强制设置）
check_reset_prop() {
  local NAME="$1"
  local EXPECTED="$2"
  local VALUE="$(resetprop "$NAME")"
  if [ -z "$VALUE" ] || [ "$VALUE" != "$EXPECTED" ]; then
    resetprop -n "$NAME" "$EXPECTED"
  fi
}

# 若属性值包含指定字符串，则将其替换为新值（POSIX case 匹配）
contains_reset_prop() {
  local NAME="$1"
  local CONTAINS="$2"
  local NEWVAL="$3"
  local VALUE="$(resetprop "$NAME")"
  case "$VALUE" in
    *"$CONTAINS"*)
      resetprop -n "$NAME" "$NEWVAL"
      ;;
  esac
}

# 强制标记系统启动尚未完成
resetprop -w sys.boot_completed 0

# 伪装引导加载程序及验证状态为锁定/绿标
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
check_reset_prop "vendor.boot.vbmeta.device_state" "locked"
check_reset_prop "vendor.boot.verifiedbootstate" "green"
check_reset_prop "sys.oem_unlock_allowed" "0"

# MIUI 专用属性
check_reset_prop "ro.secureboot.lockstate" "locked"

# Realme 专用属性
check_reset_prop "ro.boot.realmebootstate" "green"
check_reset_prop "ro.boot.realme.lockstate" "1"

# 当 Magisk 处于 Recovery 模式时，隐藏从 Recovery 启动的痕迹
contains_reset_prop "ro.bootmode" "recovery" "unknown"
contains_reset_prop "ro.boot.bootmode" "recovery" "unknown"
contains_reset_prop "vendor.boot.bootmode" "recovery" "unknown"