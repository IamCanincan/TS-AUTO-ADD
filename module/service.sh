#!/system/bin/sh
# 开机：等待系统就绪后启动守护进程（守护进程自带首次同步）

MODDIR="${0%/*}"

(
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 2
    done
    nohup sh "$MODDIR/action.sh" --daemon >/dev/null 2>&1 &
) &
