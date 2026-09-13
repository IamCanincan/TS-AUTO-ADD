#!/system/bin/sh
#=============================================================================
# lib/core.sh - 基础设施：路径常量、运行期状态、日志（logcat + 本地缓冲）
#=============================================================================

# ---------- 路径常量 ----------
TSTORE_DIR="/data/adb/tricky_store"      # Tricky Store / OSS 的数据目录
TEESIM_DIR="/data/adb/teesim"            # TEE Simulator 的数据目录
TEESIM_CONFIG="$TEESIM_DIR/config.json"  # TEE Simulator 配置文件

TRICKY_MODULE="/data/adb/modules/tricky_store"   # Tricky Store / OSS 模块 id
TEESIM_MODULE="/data/adb/modules/teesim"         # TEE Simulator 模块 id

LOCK_TIMEOUT=15               # 锁等待上限（秒）

# 日志缓冲（本地文件，用于事后排查 logcat 丢失的记录）
TAA_LOG="/data/adb/ts_auto.log"   # /data/adb 为 0700，仅 root 可读，其它应用无法访问
TAA_LOG_MAX=65536                 # 缓冲上限（字节，64KB）
TAA_LOG_KEEP=200                  # 超限后保留的末尾行数

# ---------- 运行期状态 ----------
# 以下变量由 detect_backend 填充，其余为同步过程的中间结果
TAA_BACKEND=""                # 当前后端：teesim | tricky
TAA_DIR=""                    # 后端目录（rules.txt 与运行文件所在）
RULES_FILE=""                 # 常驻应用列表路径
TARGET_FILE=""                # 后端目标文件路径
AWK_CMD=""                    # 可用的 awk 命令（可能为空）
TAA_PATCH=""                  # TEE Simulator 定点替换脚本路径
TAA_COUNT=0                   # 最近一次生成的应用总数

# ---------- 日志 ----------
# 说明：日志写两处 —— logcat（tag 为 TS-AUTO）与本地缓冲文件 $TAA_LOG。
#       写本地缓冲的原因：logcat 是内存环形缓冲，系统繁忙时旧记录会被挤掉、重启即清空，
#       事后排查往往已经看不到；缓冲文件容量固定、跨重启保留，更适合事后翻查。
#       缓冲文件位于 /data/adb（0700，仅 root 可读），超过 $TAA_LOG_MAX 后自动裁剪为
#       末尾 $TAA_LOG_KEEP 行，不会无限增长；不可写时静默退化为只写 logcat。
#       仅在开机与文件变化时写日志，无事件不写，因此不产生额外耗电。
# 用法：log_info|log_warn|log_err <消息>

# 说明：向缓冲文件追加一行；超过上限时先裁剪为末尾若干行。任何失败都静默忽略。
# 用法：_taa_log_append <整行文本>
_taa_log_append() {
    local size keep_tmp="${TAA_LOG}.tmp"

    [ -d "${TAA_LOG%/*}" ] || return 0

    if [ ! -f "$TAA_LOG" ]; then
        : > "$TAA_LOG" 2>/dev/null || return 0
        chmod 600 "$TAA_LOG" 2>/dev/null
    else
        # 超限时裁剪：先写临时文件，成功才覆盖，避免裁剪失败导致日志全丢
        # （wc 的输出可能带空白或文件名，这里只保留数字，避免比较时出错）
        size=$(wc -c < "$TAA_LOG" 2>/dev/null | tr -dc '0-9')
        if [ -n "$size" ] && [ "$size" -gt "$TAA_LOG_MAX" ] 2>/dev/null; then
            if tail -n "$TAA_LOG_KEEP" "$TAA_LOG" > "$keep_tmp" 2>/dev/null; then
                chmod 600 "$keep_tmp" 2>/dev/null
                mv -f "$keep_tmp" "$TAA_LOG" 2>/dev/null
            fi
            rm -f "$keep_tmp" 2>/dev/null
        fi
    fi

    printf '%s\n' "$1" >> "$TAA_LOG" 2>/dev/null
}

# 说明：双写一条日志（level 为 logger 的级别名：info / warn / err）
# 用法：_taa_log <level> <消息>
_taa_log() {
    local level="$1" ts
    shift

    logger -t TS-AUTO -p "$level" "$*" 2>/dev/null || true

    ts=$(date '+%m-%d %H:%M:%S' 2>/dev/null)
    _taa_log_append "${ts:+$ts }$*"
}

log_info() { _taa_log info "$@"; }
log_warn() { _taa_log warn "$@"; }
log_err()  { _taa_log err  "$@"; }
