#!/system/bin/sh
# TrickyStore 守护脚本，基于 inotifyd 监听 packages.list 自动更新 target.txt

BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"
PID_FILE="${BASE}/.ts_daemon.pid"

# 使用 mkdir 实现文件锁（兼容所有 Android 版本）
acquire_lock() { mkdir "$LOCK_DIR" 2>/dev/null; }
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

# 生成包列表并原子更新 target.txt
do_sync() {
    mkdir -p "$BASE"
    {
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        pm list packages -3 2>/dev/null | sed -n 's/^package://p'
    } | sort -u > "$TMP"

    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            logger -t TrickyStore "target.txt updated"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
        logger -t TrickyStore "sync failed: empty list"
    fi
}

# 防抖调度：3 秒内无新触发时执行一次同步
dispatch_sync() {
    touch "$PENDING"
    acquire_lock || exit 0
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 3
    done
    do_sync
    release_lock
}

case "$1" in
    "")
        # 无参数启动守护进程
        ;;
    *)
        dispatch_sync
        exit 0
        ;;
esac

# 结束旧守护实例，清理临时文件
if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE")"
    kill "$old_pid" 2>/dev/null
    sleep 0.3
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null
    rm -f "$PID_FILE"
fi
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

do_sync

# 后台 inotifyd 监听循环，异常自动恢复
(
    trap 'release_lock; rm -f "$PENDING" "$PID_FILE"; exit' EXIT INT TERM
    while true; do
        while [ ! -f "$WATCH_FILE" ]; do sleep 2; done
        inotifyd "$0" "$WATCH_FILE:w" >/dev/null 2>&1
        dispatch_sync
        sleep 1
    done
) &

echo $! > "$PID_FILE"
exit 0
