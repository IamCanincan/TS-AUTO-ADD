#!/system/bin/sh
# 开机启动：同步一次 + 启动事件驱动守护进程

MODDIR="${0%/*}"

(
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 2
    done
    sleep 5

    export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

    # 首次同步
    sh "$MODDIR/action.sh" >/dev/null 2>&1

    # 启动守护进程（监听 /data/app，包名集合对比）
    nohup sh "$MODDIR/action.sh" --daemon >/dev/null 2>&1 &
) &