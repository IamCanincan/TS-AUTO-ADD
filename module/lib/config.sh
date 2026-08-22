#!/system/bin/sh
# config.sh - 所有可调参数

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
LOG_FILE="/data/adb/ts_auto.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024))   # 5MB
LOCK_TIMEOUT=15
WATCH_DIR="/data/system"
DEBOUNCE_SECONDS=5

[ -f "/data/adb/ts_auto_config.override" ] && . "/data/adb/ts_auto_config.override"