#!/system/bin/sh
#=============================================================================
# post-fs-data.sh - 开机早期（Zygote 启动前）系统属性伪装
#
# 必须在 Zygote 启动前执行，否则 ro.build.type / ro.build.tags 等属性
# 已被固化进 Java 的 Build.TYPE / Build.TAGS 静态字段（如 userdebug）。
#=============================================================================

MODDIR="${0%/*}"

# 覆盖各框架的 resetprop 所在目录，确保能定位到 resetprop 命令
export PATH="/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH"

. "$MODDIR/common.sh" 2>/dev/null || exit 0
apply_resetprop

exit 0
