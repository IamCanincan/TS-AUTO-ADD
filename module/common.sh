#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 公共函数库
#=============================================================================

ts_base="/data/adb/tricky_store"
teesim_base="/data/adb/teesim"
log_file="/data/adb/ts_auto.log"
lock_timeout=15

# 全局变量（由 detect_target_env 设置）
target_type=""
target_base=""
taa_sys_file=""

# ---------- 环境检测 ----------
# 检测目标环境（TrickyStore / TeeSimulator），并设置全局路径
# 返回：0=TS，1=TEESIM，2=冲突（两者同时存在），3=未检测到
detect_target_env() {
    local ts_exist=0
    local teesim_exist=0

    [ -d "$ts_base" ] || [ -d "/data/adb/modules/tricky_store" ] || [ -d "/data/adb/modules_update/tricky_store" ] && ts_exist=1
    [ -d "$teesim_base" ] || [ -d "/data/adb/modules/teesim" ] || [ -d "/data/adb/modules_update/teesim" ] && teesim_exist=1

    if [ "$ts_exist" -eq 1 ] && [ "$teesim_exist" -eq 1 ]; then
        return 2
    elif [ "$ts_exist" -eq 1 ]; then
        target_type="TS"
        target_base="$ts_base"
        taa_sys_file="$ts_base/taa_sys.txt"
        return 0
    elif [ "$teesim_exist" -eq 1 ]; then
        target_type="TEESIM"
        target_base="$teesim_base"
        taa_sys_file="$teesim_base/taa_sys.txt"
        return 1
    else
        return 3
    fi
}

# ---------- 日志函数 ----------
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$log_file" 2>/dev/null
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$log_file" 2>/dev/null
}

log_err() {
    echo "[ERR] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$log_file" 2>/dev/null
}

# ---------- 文件锁 ----------
acquire_lock() {
    local lock_dir="$1"
    local waited=0
    while [ "$waited" -lt "$lock_timeout" ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    # 超时后强制清理并重试
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# ---------- 系统白名单初始化（默认谷歌三件套） ----------
ensure_taa_sys() {
    local file="$1"
    if [ ! -f "$file" ]; then
        mkdir -p "${file%/*}" 2>/dev/null
        # 默认包含 Google 服务框架、Play 服务和 Play 商店
        printf "com.google.android.gms\ncom.android.vending\ncom.google.android.gsf\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
    fi
}

# ---------- 模块描述更新 ----------
update_module_prop() {
    local prop_file="$1"
    local new_desc="$2"
    [ -f "$prop_file" ] && sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
}

# ---------- 查找 inotify 工具 ----------
# 返回格式：inotifywait:/path/to/cmd 或 inotifyd:/path/to/cmd，失败返回 1
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

# ---------- TeeSim config.json 生成 ----------
generate_teesim_json() {
    local pkg_list_file="$1"
    local json_file="$2"
    local default_keybox="Yurikey57.xml"

    [ -s "$pkg_list_file" ] || return 1

    local formatted_apps_file="${json_file}.apps.tmp"
    sed '/^$/d; s/"/\\"/g; s/^/        "/; s/$/",/' "$pkg_list_file" | sed '$ s/,$//' > "$formatted_apps_file"

    if [ -f "$json_file" ]; then
        awk -v apps_file="$formatted_apps_file" '
        /"apps"[ \t]*:[ \t]*\[/ {
            print "      \"apps\": ["
            system("cat \"" apps_file "\"")
            in_apps=1
            if ($0 ~ /\]/) {
                in_apps=0
                if ($0 ~ /\][ \t]*,/) print "      ],"
                else print "      ]"
            }
            next
        }
        in_apps {
            if ($0 ~ /\]/) {
                in_apps=0
                print $0
            }
            next
        }
        { print }
        ' "$json_file" > "${json_file}.tmp"
        if [ -s "${json_file}.tmp" ]; then
            mv -f "${json_file}.tmp" "$json_file" 2>/dev/null
        fi
    else
        cat <<EOF > "$json_file"
{
  "version": 1,
  "profiles": {
    "default": {
      "keybox": "${default_keybox}",
      "mode": "generation",
      "patchLevel": {
        "system": "",
        "vendor": "",
        "boot": ""
      },
      "osVersion": "",
      "brand": "",
      "device": "",
      "product": "",
      "manufacturer": "",
      "model": "",
      "serial": "",
      "imei": "",
      "meid": "",
      "imei2": "",
      "apps": [
$(cat "$formatted_apps_file")
      ]
    }
  }
}
EOF
    fi

    chmod 644 "$json_file" 2>/dev/null
    rm -f "$formatted_apps_file" "${json_file}.tmp" 2>/dev/null
}

# ---------- 目标配置写入 ----------
# 根据 target_type 将合并后的包列表写入对应配置文件
write_target_config() {
    local pkg_list="$1"
    case "$target_type" in
        TS)
            cp -f "$pkg_list" "$target_base/target.txt" 2>/dev/null
            chmod 644 "$target_base/target.txt" 2>/dev/null
            ;;
        TEESIM)
            generate_teesim_json "$pkg_list" "$target_base/config.json"
            ;;
        *)
            return 1
    esac
}