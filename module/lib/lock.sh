#!/system/bin/sh
#=============================================================================
# lib/lock.sh - 并发锁
#
# 用途：串行化同一后端的写入操作（守护进程、手动同步、安装脚本之间互斥）。
#=============================================================================

# ---------- 加锁 ----------
# 说明：以「目录原子创建」实现互斥；等待超时后清理疑似遗留的锁目录再重试一次。
# 用法：acquire_lock <锁目录>
# 返回：0=取得锁，非 0=失败
acquire_lock() {
    local waited=0

    while [ "$waited" -lt "$LOCK_TIMEOUT" ]; do
        mkdir "$1" 2>/dev/null && return 0
        sleep 1
        waited=$((waited + 1))
    done

    log_warn "锁等待超时，清理遗留锁目录：$1"
    rmdir "$1" 2>/dev/null
    mkdir "$1" 2>/dev/null
}

# ---------- 解锁 ----------
# 说明：释放锁目录；不存在时静默忽略。
# 用法：release_lock <锁目录>
release_lock() {
    rmdir "$1" 2>/dev/null || true
}
