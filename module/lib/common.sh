#!/system/bin/sh
# common.sh - 核心函数库

# 自动定位模块目录（优先使用 MODDIR 环境变量）
if [ -z "$MODDIR" ] || [ ! -d "$MODDIR/lib" ]; then
    if [ -d "/data/adb/modules/ts-auto-add" ]; then
        MODDIR="/data/adb/modules/ts-auto-add"
    elif [ -d "/data/adb/modules_update/ts-auto-add" ]; then
        MODDIR="/data/adb/modules_update/ts-auto-add"
    else
        echo "❌ 无法定位模块目录" >&2
        return 1
    fi
fi

. "$MODDIR/lib/config.sh"

# ---------- 兼容性保护 ----------
type abort >/dev/null 2>&1 || abort() { echo "❌ $*"; exit 1; }
type ui_print >/dev/null 2>&1 || ui_print() { echo "$*"; }

[ -z "$PROP_FILE" ] && PROP_FILE="$MODDIR/module.prop"

# 颜色、日志、环境检测、锁、应用列表、白名单、合并、更新描述、inotify查找、计数等函数...
# （以下保持您已有实现，无需改动，仅略述）
# 注意：acquire_lock 使用 mkdir，release_lock 使用 rmdir
# 加载子模块：. "$MODDIR/lib/sync.sh" 和 . "$MODDIR/lib/daemon.sh"

# ---------- 加载子模块 ----------
. "$MODDIR/lib/sync.sh"
. "$MODDIR/lib/daemon.sh"