#!/system/bin/sh
#==============================================================================
# common.sh - TS-AUTO-ADD 模块公共函数库
#==============================================================================

# ----------------------------- 常量定义 ------------------------------------
TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
LOG_FILE="/data/adb/ts_auto.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024))   # 5 MiB
LOCK_TIMEOUT=15

# 全局变量（由 detect_target_env 填充）
TARGET_TYPE=""      # "TS" 或 "TEESIM"
TARGET_BASE=""
TAA_SYS_FILE=""

# ----------------------------- 日志记录 ------------------------------------
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

log_info() { rotate_log; echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_warn() { rotate_log; echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }
log_err()  { rotate_log; echo "[ERR]  $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null; }

# ----------------------------- 环境检测 ------------------------------------
# 返回值: 0=TS, 1=TEESIM, 2=冲突, 3=未检测到
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

# ----------------------------- 文件锁 ------------------------------------
acquire_lock() {
    local lock_dir="$1" waited=0
    while [ "$waited" -lt "$LOCK_TIMEOUT" ]; do
        mkdir "$lock_dir" 2>/dev/null && return 0
        sleep 1
        waited=$((waited + 1))
    done
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

release_lock() { rmdir "$1" 2>/dev/null || true; }

# ----------------------------- 应用列表获取 --------------------------------
get_installed_packages() {
    local raw
    raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    echo "$raw" | sed -n 's/^package://p' | sed '/^$/d'
}

# ----------------------------- 系统白名单初始化 --------------------------------
ensure_taa_sys() {
    local file="$1"
    if [ ! -f "$file" ]; then
        mkdir -p "${file%/*}" 2>/dev/null
        printf "com.google.android.gms\ncom.android.vending\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
    fi
}

# ----------------------------- 列表合并去重 --------------------------------
merge_and_dedupe() {
    local sys_file="$1" user_list="$2"
    { [ -f "$sys_file" ] && cat "$sys_file"; echo "$user_list"; } | sort -u | sed '/^$/d'
}

# ----------------------------- 模块描述更新 --------------------------------
# 功能: 更新 module.prop 中的 description 字段，若不存在则追加
update_module_prop() {
    local prop_file="$1" new_desc="$2"
    [ -f "$prop_file" ] || return 1
    grep -q '^description=' "$prop_file" || echo "description=" >> "$prop_file"
    sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
}

# ----------------------------- inotify 工具查找 --------------------------------
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

# ----------------------------- 行数统计 --------------------------------
count_lines() {
    local input="$1"
    [ -z "$input" ] && echo 0 || printf '%s\n' "$input" | grep -c .
}

# ----------------------------- TeeSimulator config.json 更新 --------------------
# 功能: 若 default 存在则更新其 apps；若不存在则添加 default（保留其他 profile）
# 返回: 0=成功, 1=失败（config.json 不存在或处理出错）
generate_teesim_json() {
    local pkg_list_file="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        log_warn "config.json 不存在，跳过更新"
        return 1
    fi
    [ -s "$pkg_list_file" ] || return 1

    local formatted_apps_file="${json_file}.apps.tmp"
    sed '/^$/d; s/"/\\"/g; s/^/        "/; s/$/",/' "$pkg_list_file" | sed '$ s/,$//' > "$formatted_apps_file"
    [ -s "$formatted_apps_file" ] || { rm -f "$formatted_apps_file"; return 1; }

    local tmp_file="${json_file}.tmp"
    awk -v apps_file="$formatted_apps_file" '
    BEGIN {
        depth = 0
        in_profiles = 0
        found_default = 0
        replace_mode = 0
        skip_depth = 0
        waiting_for_bracket = 0
        default_added = 0
        default_template = "    \"default\": {\n      \"keybox\": \"keybox.xml\",\n      \"mode\": \"patch\",\n      \"patchLevel\": {\n        \"system\": \"today\",\n        \"vendor\": \"YYYY-MM-05\",\n        \"boot\": \"YYYY-MM-05\"\n      },\n      \"osVersion\": \"\",\n      \"brand\": \"\",\n      \"device\": \"\",\n      \"product\": \"\",\n      \"manufacturer\": \"\",\n      \"model\": \"\",\n      \"serial\": \"\",\n      \"imei\": \"\",\n      \"meid\": \"\",\n      \"imei2\": \"\",\n      \"apps\": [\n"
        default_end = "      ],\n      \"autoIncludeNewApps\": false\n    }"
    }
    {
        open_cnt = 0; close_cnt = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") open_cnt++
            if (c == "}") close_cnt++
        }
        depth += open_cnt - close_cnt

        if (!in_profiles && $0 ~ /"profiles"[ \t]*:/ && depth == 0) {
            in_profiles = 1
            print $0
            if ($0 ~ /{/) {
                # 本行已有 {，继续处理
            }
            next
        }

        if (in_profiles) {
            if (!found_default && $0 ~ /"default"[ \t]*:/ && depth == 1) {
                found_default = 1
                if ($0 ~ /\[/) {
                    pre = substr($0, 1, index($0, "[") - 1)
                    print pre "["
                    while ((getline app < apps_file) > 0) { print app }
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
                    print $0
                    waiting_for_bracket = 1
                }
                next
            }

            if (waiting_for_bracket) {
                if ($0 ~ /\[/) {
                    pre = substr($0, 1, index($0, "[") - 1)
                    print pre "["
                    while ((getline app < apps_file) > 0) { print app }
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

            if (!found_default && depth == 0 && !default_added) {
                default_added = 1
                print default_template
                while ((getline app < apps_file) > 0) { print app }
                close(apps_file)
                print default_end
                if ($0 ~ /}/) {
                    print $0
                }
                next
            }

            if (default_added && depth == 0 && $0 ~ /}/) {
                print $0
                next
            }

            print $0
            if (depth == 0) {
                in_profiles = 0
            }
            next
        }

        print $0
    }
    END {
        if (!found_default && !default_added) {
            print "ERROR" > "/dev/stderr"
        }
    }
    ' "$json_file" 2> "${tmp_file}.status" > "$tmp_file"

    if [ -s "$tmp_file" ] && ! grep -q "ERROR" "${tmp_file}.status"; then
        mv -f "$tmp_file" "$json_file" 2>/dev/null
        chmod 644 "$json_file" 2>/dev/null
        log_info "config.json 更新成功"
        rm -f "${tmp_file}.status" "$formatted_apps_file" 2>/dev/null
        return 0
    else
        log_err "config.json 处理失败"
        rm -f "$tmp_file" "${tmp_file}.status" "$formatted_apps_file" 2>/dev/null
        return 1
    fi
}

# ----------------------------- 写入目标配置 --------------------------------
write_target_config() {
    local pkg_list="$1"
    case "$TARGET_TYPE" in
        TS)
            cp -f "$pkg_list" "$TARGET_BASE/target.txt" 2>/dev/null
            chmod 644 "$TARGET_BASE/target.txt" 2>/dev/null
            ;;
        TEESIM)
            generate_teesim_json "$pkg_list" "$TARGET_BASE/config.json" || {
                log_warn "更新 TeeSim 配置失败"
                return 1
            }
            ;;
        *)
            return 1
    esac
}