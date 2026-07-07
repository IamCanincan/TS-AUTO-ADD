#!/system/bin/sh
#====================================================
# 系统属性注入脚本
# 优化策略：使用非阻塞注入限制，防止影响系统开机引导链
#====================================================

# [内核行为分析]
# 为什么使用 resetprop -n ？
# 默认的 resetprop 会触发 init 守护进程去更新 property_service 并重新加载关联的 .rc 触发器。
# 在某些高度定制的国产 ROM（如 HyperOS / OriginOS）中，开机时直接更改核心安全 boot 属性可能会激活 
# Android 系统的 Verified Boot 拒绝逻辑，从而导致系统卡第一屏或直接进入 Bootloop 状态。
# 使用 `-n` (no reload) 仅修改底层属性内存节点（property workspace memory），不通知 init 进程。
# 客观效果：彻底断绝因改写属性引发的死机、重启风险，具有最高的安全边界。

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

# 核心欺骗属性序列（伪装 Bootloader 加锁状态与安全环境）
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