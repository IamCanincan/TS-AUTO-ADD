#!/system/bin/sh
# common.sh - 基础函数库

. "${0%/*}/config.sh"

# ---------- 兼容性保护（KernelSU 可能缺失函数） ----------
type abort >/dev/null 2>&1 || abort() { echo "❌ $*"; exit 1; }
type ui_print >/dev/null 2>&1 || ui_print() { echo "$*"; }

# ---------- 颜色输出 ----------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi
print_info() { echo "${BLUE}▶${NC} $*"; }
print_ok()   { echo "${GREEN}✓${NC} $*"; }
print_warn() { echo "${YELLOW}⚠${NC} $*" >&2; }
print_err()  { echo "${RED}✗${NC} $*" >&2; }

# ---------- 日志轮转 ----------
rotate_log() {
    [ -f "$LOG_FILE" ] || return
    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$size" -gt "$MAX_LOG_SIZE" ] || return
    mv -f "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    chmod 644 "$LOG_FILE" 2>/dev/null
}
log_info() { rotate_log; echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_warn() { rotate_log; echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_err()  { rotate_log; echo "[ERR]  $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }

# ---------- 环境检测 ----------
detect_target_env() {
    local ts_exist=0 teesim_exist=0
    [ -d "$TS_BASE" ] || [ -d "/data/adb/modules/tricky_store" ] || [ -d "/data/adb/modules_update/tricky_store" ] && ts_exist=1
    [ -d "$TEESIM_BASE" ] || [ -d "/data/adb/modules/teesim" ] || [ -d "/data/adb/modules_update/teesim" ] && teesim_exist=1

    if [ "$ts_exist" -eq 1 ] && [ "$teesim_exist" -eq 1 ]; then
        return 2
    elif [ "$ts_exist" -eq 1 ]; then
        TARGET_TYPE="TS"
        TARGET_BASE="$TS_BASE"
        TAA_SYS_FILE="$TS_BASE/taa_sys.txt"
        return 0
    elif [ "$teesim_exist" -eq 1 ]; then
        TARGET_TYPE="TEESIM"
        TARGET_BASE="$TEESIM_BASE"
        TAA_SYS_FILE="$TEESIM_BASE/taa_sys.txt"
        return 1
    else
        return 3
    fi
}

# ---------- 文件锁（flock） ----------
acquire_lock() {
    local lock_dir="$1"
    mkdir -p "$lock_dir" 2>/dev/null
    local lock_file="$lock_dir/.lock"
    exec 200>"$lock_file"
    flock -w "$LOCK_TIMEOUT" 200 2>/dev/null
}
release_lock() {
    exec 200>&-
}

# ---------- 应用列表（兼容旧版） ----------
get_installed_packages() {
    local raw
    raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    echo "$raw" | sed -n 's/^package://p' | sed '/^$/d'
}

# ---------- 确保白名单存在 ----------
ensure_taa_sys() {
    local file="$1"
    [ -f "$file" ] && return
    mkdir -p "${file%/*}" 2>/dev/null
    printf "com.google.android.gms\ncom.android.vending\ncom.google.android.gsf\n" > "$file" 2>/dev/null
    chmod 640 "$file" 2>/dev/null
}

# ---------- 合并去重 ----------
merge_and_dedupe() {
    local sys_file="$1" user_list="$2"
    { [ -f "$sys_file" ] && cat "$sys_file"; echo "$user_list"; } | sort -u | sed '/^$/d'
}

# ---------- 更新模块描述 ----------
update_module_prop() {
    local prop_file="$1" new_desc="$2"
    [ -f "$prop_file" ] || return 1
    grep -q '^description=' "$prop_file" || echo "description=" >> "$prop_file"
    sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
}

# ---------- 查找 inotify ----------
find_inotify_cmd() {
    for cmd in inotifywait inotifyd; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd:$(command -v "$cmd")"
            return 0
        fi
    done
    for busybox in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox; do
        [ -x "$busybox" ] || continue
        if "$busybox" --list 2>/dev/null | grep -q "^inotifywait$"; then
            echo "inotifywait:$busybox inotifywait"
            return 0
        elif "$busybox" --list 2>/dev/null | grep -q "^inotifyd$"; then
            echo "inotifyd:$busybox inotifyd"
            return 0
        fi
    done
    return 1
}

# ---------- 计数 ----------
count_lines() {
    local input="$1"
    [ -z "$input" ] && echo 0 || printf '%s\n' "$input" | grep -c .
}

# ---------- 加载子模块 ----------
. "${0%/*}/sync.sh"
. "${0%/*}/daemon.sh"