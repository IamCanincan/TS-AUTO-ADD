#!/system/bin/sh
#=============================================================================
# lib/tools.sh - 外部工具定位
#
# 说明：工具可能来自系统（toybox）或各 Root 框架自带的 busybox，
#       因此按候选路径逐个探测，找到第一个可用者即返回。
#=============================================================================

# ---------- awk 定位 ----------
# 说明：优先系统自带 awk，其次 Magisk / KernelSU / APatch 的 busybox awk。
# 用法：find_awk
# 返回：0=成功（可用命令写入标准输出，可能形如 "busybox awk"）1=未找到
find_awk() {
    local b

    if command -v awk >/dev/null 2>&1; then
        echo "awk"
        return 0
    fi

    for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$b" ] && "$b" awk 'BEGIN{}' >/dev/null 2>&1; then
            echo "$b awk"
            return 0
        fi
    done
    return 1
}

# ---------- inotify 定位 ----------
# 说明：按 inotifywait → inotifyd 的顺序探测（前者事件信息更完整，优先使用）。
# 用法：find_inotify_cmd
# 返回：0=成功（输出 "模式:命令"）1=未找到
find_inotify_cmd() {
    local mode name

    for mode in inotifywait inotifyd; do
        for name in "$mode" "/data/adb/magisk/busybox $mode" "/data/adb/ksu/bin/busybox $mode"; do
            command -v ${name%% *} >/dev/null 2>&1 || continue

            # 用 --help 输出确认该 applet 具备对应能力
            if [ "$mode" = "inotifywait" ]; then
                ${name%% *} --help 2>&1 | grep -q -e '-m' -e '--monitor' || continue
            else
                ${name%% *} --help 2>&1 | grep -q 'inotifyd' || continue
            fi

            echo "$mode:$name"
            return 0
        done
    done
    return 1
}
