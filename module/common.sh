#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD - 公共函数库
#=============================================================================

TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
TAA_SYS_FILE="$TS_BASE/taa_sys.txt"
LOG_FILE="/data/adb/ts_auto.log"
LOCK_TIMEOUT=15

# ---------- 日志输出函数 ----------
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}

log_err() {
    echo "[ERR] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}

# ---------- 并发锁管理 ----------
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

    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
}

release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# ---------- 系统白名单基础配置 ----------
ensure_taa_sys() {
    local file="$1"
    if [ ! -f "$file" ]; then
        mkdir -p "${file%/*}" 2>/dev/null
        printf "com.google.android.gms\ncom.android.vending\nio.github.vvb2060.keyattestation\n" > "$file" 2>/dev/null
        chmod 640 "$file" 2>/dev/null
    fi
}

# ---------- 模块属性配置修改 ----------
update_module_prop() {
    local prop_file="$1"
    local new_desc="$2"

    if [ -f "$prop_file" ]; then
        sed -i "s/^description=.*/description=$new_desc/" "$prop_file" 2>/dev/null
    fi
}

# ---------- inotify 监控指令检测 ----------
find_inotify_cmd() {
    local cmd=""

    for cmd in "inotifywait" "/data/adb/magisk/busybox inotifywait" "/data/adb/ksu/bin/busybox inotifywait"; do
        if command -v ${cmd%% *} >/dev/null 2>&1; then
            if ${cmd%% *} --help 2>&1 | grep -q -e '-m' -e '--monitor'; then
                echo "inotifywait:${cmd}"
                return 0
            fi
        fi
    done

    for cmd in "inotifyd" "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd"; do
        if command -v ${cmd%% *} >/dev/null 2>&1; then
            if ${cmd%% *} --help 2>&1 | grep -q 'inotifyd'; then
                echo "inotifyd:${cmd}"
                return 0
            fi
        fi
    done

    return 1
}

# ---------- TeeSim config.json 应用节点增量更新 ----------
generate_teesim_json() {
    local pkg_list_file="$1"
    local json_file="$2"
    local default_keybox="Yurikey57.xml"

    [ -s "$pkg_list_file" ] || return 1

    local formatted_apps_file="${json_file}_apps.tmp"
    sed '/^$/d; s/"/\\"/g; s/^/        "/; s/$/",/' "$pkg_list_file" | sed '$ s/,$//' > "$formatted_apps_file"

    if [ -f "$json_file" ]; then
        awk '
        /"apps"[ \t]*:[ \t]*\[/ {
            print "      \"apps\": ["
            system("cat \"'"$formatted_apps_file"'\"")
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