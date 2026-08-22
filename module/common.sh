#!/system/bin/sh
#==============================================================================
# 文件: common.sh
# 描述: TS-AUTO-ADD 模块公共函数库，提供环境检测、日志、锁、配置管理等
# 函数: 本文件不直接执行，由其他脚本引用
#==============================================================================

# ----------------------------- 常量定义 ------------------------------------
TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
LOG_FILE="/data/adb/ts_auto.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024))  # 日志文件轮转阈值（字节）
LOCK_TIMEOUT=15                     # 获取文件锁的最大等待秒数

# 全局变量（由 detect_target_env 设置，供其他函数使用）
TARGET_TYPE=""      # "TS" 或 "TEESIM"
TARGET_BASE=""      # 对应环境的数据目录
TAA_SYS_FILE=""     # 系统白名单文件路径

# ----------------------------- 终端颜色输出 --------------------------------
# 检测是否在交互式终端，决定是否启用 ANSI 颜色码
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

# 输出信息（蓝色圆点）
print_info() { echo "${BLUE}▶${NC} $*"; }
# 输出成功（绿色对勾）
print_ok()   { echo "${GREEN}✓${NC} $*"; }
# 输出警告（黄色警告符号，到 stderr）
print_warn() { echo "${YELLOW}⚠${NC} $*" >&2; }
# 输出错误（红色叉号，到 stderr）
print_err()  { echo "${RED}✗${NC} $*" >&2; }

# ----------------------------- 日志轮转与记录 ------------------------------
# 功能: 当日志文件超过 MAX_LOG_SIZE 时，重命名为 .old 并创建新文件
rotate_log() {
    [ -f "$LOG_FILE" ] || return
    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null
        touch "$LOG_FILE" 2>/dev/null
        chmod 644 "$LOG_FILE" 2>/dev/null
    fi
}

# 记录不同级别的日志，自动调用 rotate_log
log_info() { rotate_log; echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_warn() { rotate_log; echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_err()  { rotate_log; echo "[ERR]  $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }

# ----------------------------- 目标环境检测 --------------------------------
# 功能: 检测系统中是否存在 TrickyStore 或 TeeSimulator
# 返回: 0=TS, 1=TEESIM, 2=冲突, 3=未检测到
# 副作用: 设置全局变量 TARGET_TYPE, TARGET_BASE, TAA_SYS_FILE
detect_target_env() {
    local ts_exist=0
    local teesim_exist=0

    # 检查模块安装目录和数据目录
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

# ----------------------------- 文件锁机制 ----------------------------------
# 功能: 通过创建目录实现互斥锁，防止并发同步
# 参数: 锁目录路径
# 返回: 0=成功获取锁，1=超时失败
acquire_lock() {
    local lock_dir="$1"
    local waited=0
    while [ "$waited" -lt "$LOCK_TIMEOUT" ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    # 超时后强制清理旧锁目录并重新创建
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

# 功能: 释放锁（删除目录）
release_lock() { rmdir "$1" 2>/dev/null || true; }

# ----------------------------- 应用列表获取 --------------------------------
# 功能: 获取系统中所有第三方（非系统）已安装应用包名
# 输出: 每行一个包名，已过滤空行
get_installed_packages() {
    local raw
    raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    echo "$raw" | sed -n 's/^package://p' | sed '/^$/d'
}

# ----------------------------- 系统白名单初始化 ----------------------------
# 功能: 如果白名单文件不存在，则创建并写入默认的 Google 服务包名
# 参数: 白名单文件路径
ensure_taa_sys() {
    local file="$1"
    if [ ! -f "$file" ]; then
        mkdir -p "${file%/*}" 2>/dev/null
        printf "com.google.android.gms\ncom.android.vending\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
    fi
}

# ----------------------------- 列表合并与去重 ------------------------------
# 功能: 合并系统白名单文件和用户应用列表，排序并去重
# 参数: 系统白名单文件路径，用户应用列表（字符串，换行分隔）
# 输出: 合并后的去重列表到 stdout
merge_and_dedupe() {
    local sys_file="$1"
    local user_list="$2"
    {
        [ -f "$sys_file" ] && cat "$sys_file"
        echo "$user_list"
    } | sort -u | sed '/^$/d'
}

# ----------------------------- 模块描述更新 --------------------------------
# 功能: 更新 module.prop 中的 description 行，若不存在则追加
# 参数: prop文件路径，新描述内容
# 返回: 0=成功，1=失败
update_module_prop() {
    local prop_file="$1"
    local new_desc="$2"
    [ -f "$prop_file" ] || return 1
    # 确保 description 行存在
    grep -q '^description=' "$prop_file" || echo "description=" >> "$prop_file"
    sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
}

# ----------------------------- inotify 工具查找 ----------------------------
# 功能: 在系统中搜索可用的 inotify 监控命令（inotifywait 或 inotifyd）
# 输出: 格式 "inotifywait:/path/to/cmd" 或 "inotifyd:/path/to/cmd"
# 返回: 0=找到，1=未找到
find_inotify_cmd() {
    local cmd
    for cmd in "inotifywait" "/data/adb/magisk/busybox inotifywait" "/data/adb/ksu/bin/busybox inotifywait"; do
        if command -v "${cmd%% *}" >/dev/null 2>&1; then
            if "${cmd%% *}" --help 2>&1 | grep -q -e '-m' -e '--monitor'; then
                echo "inotifywait:${cmd}"
                return 0
            fi
        fi
    done
    for cmd in "inotifyd" "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd"; do
        if command -v "${cmd%% *}" >/dev/null 2>&1; then
            if "${cmd%% *}" --help 2>&1 | grep -q 'inotifyd'; then
                echo "inotifyd:${cmd}"
                return 0
            fi
        fi
    done
    return 1
}

# ----------------------------- 统计行数辅助 --------------------------------
# 功能: 计算字符串中的行数（正确处理空字符串）
# 参数: 待统计的字符串
# 输出: 行数
count_lines() {
    local input="$1"
    if [ -z "$input" ]; then
        echo 0
    else
        printf '%s\n' "$input" | grep -c .
    fi
}

# ----------------------------- TeeSimulator config.json 更新 ---------------
# 功能: 仅替换 config.json 中 default profile 的 apps 数组，保留其他所有字段
# 参数: 包含应用列表的临时文件路径，config.json 路径
# 返回: 0=成功，1=失败（文件不存在或替换出错）
# 注意: 若 config.json 不存在，不创建新文件，直接返回 1
generate_teesim_json() {
    local pkg_list_file="$1"
    local json_file="$2"

    # 若目标文件不存在，记录警告并返回
    if [ ! -f "$json_file" ]; then
        log_warn "config.json 不存在，跳过更新"
        return 1
    fi

    [ -s "$pkg_list_file" ] || return 1

    # 格式化应用列表为 JSON 数组元素（缩进 8 个空格）
    local formatted_apps_file="${json_file}.apps.tmp"
    sed '/^$/d; s/"/\\"/g; s/^/        "/; s/$/",/' "$pkg_list_file" | sed '$ s/,$//' > "$formatted_apps_file"

    local tmp_file="${json_file}.tmp"
    # 使用 awk 处理：只替换 default 对象内的 apps 数组
    awk -v apps_file="$formatted_apps_file" '
    BEGIN {
        depth = 0          # 当前花括号嵌套深度
        in_default = 0     # 是否在 "default" 对象内
        replace_mode = 0   # 是否处于跳过原数组内容的模式
        skip_depth = 0     # 等待 depth 回到此值表示数组结束
        found = 0          # 是否已完成替换
        waiting_for_bracket = 0
    }
    {
        # 计算本行中的花括号变化，更新 depth
        open_cnt = 0; close_cnt = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") open_cnt++
            if (c == "}") close_cnt++
        }
        depth += open_cnt - close_cnt

        # 检测是否进入 "default" 对象（depth==1 表示在 profiles 对象内）
        if (!found && $0 ~ /"default"[ \t]*:/ && depth == 1) {
            in_default = 1
        }
        # 离开 default 对象（depth 回到 1 表示从 default 对象返回上一级）
        if (in_default && depth == 1) {
            in_default = 0
        }

        # 在 default 对象内找到 "apps" 键
        if (!found && in_default && $0 ~ /"apps"[ \t]*:/) {
            found = 1
            if ($0 ~ /\[/) {
                # "[" 在本行，直接输出新数组
                pre = substr($0, 1, index($0, "[") - 1)
                print pre "["
                while ((getline app < apps_file) > 0) {
                    print app
                }
                close(apps_file)
                after = substr($0, index($0, "[") + 1)
                if (after ~ /\]/) {
                    rest = substr(after, index(after, "]") + 1)
                    if (rest != "") print "      ]" rest
                    else print "      ]"
                } else {
                    replace_mode = 1
                    skip_depth = depth - 1
                }
            } else {
                # "[" 在下一行，先输出本行，设置等待标记
                print $0
                waiting_for_bracket = 1
            }
            next
        }

        # 等待 "[" 行
        if (waiting_for_bracket) {
            if ($0 ~ /\[/) {
                pre = substr($0, 1, index($0, "[") - 1)
                print pre "["
                while ((getline app < apps_file) > 0) {
                    print app
                }
                close(apps_file)
                after = substr($0, index($0, "[") + 1)
                if (after ~ /\]/) {
                    rest = substr(after, index(after, "]") + 1)
                    if (rest != "") print "      ]" rest
                    else print "      ]"
                } else {
                    replace_mode = 1
                    skip_depth = depth - 1
                }
                waiting_for_bracket = 0
            }
            next
        }

        # 替换模式：跳过原数组内容，直到 depth 降到 skip_depth
        if (replace_mode) {
            if (depth <= skip_depth) {
                replace_mode = 0
                if ($0 ~ /\]/) {
                    rest = substr($0, index($0, "]") + 1)
                    if (rest != "") print "      ]" rest
                    else print "      ]"
                } else {
                    print "      ]"
                }
            }
            next
        }

        # 默认原样输出
        print $0
    }
    ' "$json_file" > "$tmp_file" 2>/dev/null

    if [ -s "$tmp_file" ]; then
        mv -f "$tmp_file" "$json_file" 2>/dev/null
        chmod 644 "$json_file" 2>/dev/null
        log_info "config.json 的 default.apps 已更新"
    else
        log_warn "替换 default.apps 失败，保留原 config.json"
        rm -f "$tmp_file" 2>/dev/null
    fi

    rm -f "$formatted_apps_file" 2>/dev/null
    return 0
}

# ----------------------------- 写入目标配置文件 ----------------------------
# 功能: 根据检测到的 TARGET_TYPE，将合并后的应用列表写入对应的配置文件
# 参数: 包含应用列表的文件路径
# 返回: 0=成功，1=失败
write_target_config() {
    local pkg_list="$1"
    case "$TARGET_TYPE" in
        TS)
            cp -f "$pkg_list" "$TARGET_BASE/target.txt" 2>/dev/null
            chmod 644 "$TARGET_BASE/target.txt" 2>/dev/null
            ;;
        TEESIM)
            generate_teesim_json "$pkg_list" "$TARGET_BASE/config.json" || {
                log_warn "更新 TeeSim 配置失败（config.json 不存在或替换出错）"
                return 1
            }
            ;;
        *)
            return 1
    esac
}