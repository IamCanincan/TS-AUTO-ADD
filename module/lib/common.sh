#!/system/bin/sh
# common.sh - 基础函数库，加载 config/sync/daemon

. "${0%/*}/config.sh"

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

# ---------- 日志 ----------
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

# ---------- 环境检测 ----------
detect_target_env() {
    local ts_exist=0 teesim_exist=0
    [ -d "$TS_BASE" ] || [ -d "/data/adb/modules/tricky_store" ] || [ -d "/data/adb/modules_update/tricky_store" ] && ts_exist=1
    [ -d "$TEESIM_BASE" ] || [ -d "/data/adb/modules/teesim" ] || [ -d "/data/adb/modules_update/teesim" ] && teesim_exist=1

    if [ "$ts_exist" -eq 1 ] && [ "$teesim_exist" -eq 1 ]; then
        return 2
    elif [ "$ts_exist" -eq 1 ]; then
        TARGET_TYPE="TS"; TARGET_BASE="$TS_BASE"; TAA_SYS_FILE="$TS_BASE/taa_sys.txt"; return 0
    elif [ "$teesim_exist" -eq 1 ]; then
        TARGET_TYPE="TEESIM"; TARGET_BASE="$TEESIM_BASE"; TAA_SYS_FILE="$TEESIM_BASE/taa_sys.txt"; return 1
    else
        return 3
    fi
}

# ---------- 锁 ----------
acquire_lock() {
    local lock_dir="$1" waited=0
    while [ "$waited" -lt "$LOCK_TIMEOUT" ]; do
        mkdir "$lock_dir" 2>/dev/null && return 0
        sleep 1; waited=$((waited + 1))
    done
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}
release_lock() { rmdir "$1" 2>/dev/null || true; }

# ---------- 应用列表 ----------
get_installed_packages() {
    local raw
    raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    echo "$raw" | sed -n 's/^package://p' | sed '/^$/d'
}

# ---------- 白名单 ----------
ensure_taa_sys() {
    local file="$1"
    if [ ! -f "$file" ]; then
        mkdir -p "${file%/*}" 2>/dev/null
        printf "com.google.android.gms\ncom.android.vending\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
    fi
}

# ---------- 合并去重 ----------
merge_and_dedupe() {
    local sys_file="$1" user_list="$2"
    { [ -f "$sys_file" ] && cat "$sys_file"; echo "$user_list"; } | sort -u | sed '/^$/d'
}

# ---------- 更新描述 ----------
update_module_prop() {
    local prop_file="$1" new_desc="$2"
    [ -f "$prop_file" ] || return 1
    grep -q '^description=' "$prop_file" || echo "description=" >> "$prop_file"
    sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
}

# ---------- inotify 查找 ----------
find_inotify_cmd() {
    local cmd
    for cmd in "inotifywait" "/data/adb/magisk/busybox inotifywait" "/data/adb/ksu/bin/busybox inotifywait"; do
        if command -v "${cmd%% *}" >/dev/null 2>&1; then
            if "${cmd%% *}" --help 2>&1 | grep -q -e '-m' -e '--monitor'; then
                echo "inotifywait:${cmd}"; return 0
            fi
        fi
    done
    for cmd in "inotifyd" "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd"; do
        if command -v "${cmd%% *}" >/dev/null 2>&1; then
            if "${cmd%% *}" --help 2>&1 | grep -q 'inotifyd'; then
                echo "inotifyd:${cmd}"; return 0
            fi
        fi
    done
    return 1
}

# ---------- 计数 ----------
count_lines() {
    local input="$1"
    [ -z "$input" ] && echo 0 || printf '%s\n' "$input" | grep -c .
}

# ---------- TeeSim JSON 更新 ----------
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
        default_inserted = 0
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
                # 本行已有 {，继续
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

            if (depth == 0 && !found_default && !default_inserted) {
                default_inserted = 1
                print "    \"default\": {"
                print "      \"keybox\": \"keybox.xml\","
                print "      \"mode\": \"patch\","
                print "      \"patchLevel\": {"
                print "        \"system\": \"today\","
                print "        \"vendor\": \"YYYY-MM-05\","
                print "        \"boot\": \"YYYY-MM-05\""
                print "      },"
                print "      \"osVersion\": \"\","
                print "      \"brand\": \"\","
                print "      \"device\": \"\","
                print "      \"product\": \"\","
                print "      \"manufacturer\": \"\","
                print "      \"model\": \"\","
                print "      \"serial\": \"\","
                print "      \"imei\": \"\","
                print "      \"meid\": \"\","
                print "      \"imei2\": \"\","
                print "      \"apps\": ["
                while ((getline app < apps_file) > 0) { print app }
                close(apps_file)
                print "      ],"
                print "      \"autoIncludeNewApps\": false"
                print "    }"
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
        if (!found_default && !default_inserted) {
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

# ---------- 写入目标配置 ----------
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

# ---------- 加载子模块 ----------
. "${0%/*}/sync.sh"
. "${0%/*}/daemon.sh"