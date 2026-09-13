#!/system/bin/sh
#=============================================================================
# lib/core.sh - 基础设施：路径常量、运行期状态、系统日志
#=============================================================================

# ---------- 路径常量 ----------
TSTORE_DIR="/data/adb/tricky_store"      # Tricky Store / OSS 的数据目录
TEESIM_DIR="/data/adb/teesim"            # TEE Simulator 的数据目录
TEESIM_CONFIG="$TEESIM_DIR/config.json"  # TEE Simulator 配置文件

TRICKY_MODULE="/data/adb/modules/tricky_store"   # Tricky Store / OSS 模块 id
TEESIM_MODULE="/data/adb/modules/teesim"         # TEE Simulator v4+ 模块 id

LOCK_TIMEOUT=15               # 锁等待上限（秒）

# ---------- 运行期状态 ----------
# 以下变量由 detect_backend 填充，其余为同步过程的中间结果
TAA_BACKEND=""                # 当前后端：teesim | tricky
TAA_DIR=""                    # 后端目录（rules.txt 与运行文件所在）
RULES_FILE=""                 # 常驻应用列表路径
TARGET_FILE=""                # 后端目标文件路径
AWK_CMD=""                    # 可用的 awk 命令（可能为空）
TAA_PATCH=""                  # TEE Simulator 定点替换脚本路径
TAA_COUNT=0                   # 最近一次生成的应用总数

# ---------- 系统日志 ----------
# 说明：只写系统日志（logcat，tag 为 TS-AUTO），不落任何文件；
#       时间戳由 logcat 自身记录，消息中不再重复拼时间。
#       查看：logcat -s TS-AUTO
# 用法：log_info|log_warn|log_err <消息>
log_info() { logger -t TS-AUTO -p info "$*" 2>/dev/null || true; }
log_warn() { logger -t TS-AUTO -p warn "$*" 2>/dev/null || true; }
log_err()  { logger -t TS-AUTO -p err  "$*" 2>/dev/null || true; }
