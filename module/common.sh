#!/system/bin/sh
#=============================================================================
# 公共函数库 (common.sh)
# 提供锁、日期处理、补丁获取、状态更新等共享功能
#=============================================================================

# ---------- 锁（纯 mkdir 目录锁） ----------
acquire_lock() {
    local lock_dir="$1"
    local timeout=30
    local waited=0
    while [ $waited -lt $timeout ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo " [警告] 锁获取超时，强制清理残留锁..." >&2
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

release_lock() {
    rmdir "$1" 2>/dev/null
}

# ---------- 日期工具 ----------
clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

force_to_05() {
    local in_date="$1"
    [ -n "$in_date" ] || return
    case "$in_date" in *-01) echo "${in_date%-01}-05" ;; *) echo "$in_date" ;; esac
}

get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

# ---------- 网络获取补丁日期 ----------
fetch_online_date() {
    local url="$1" html="" patch=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 5 -m 10 -Ls -A "$user_agent" "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 10 --connect-timeout=5 --no-check-certificate -U "$user_agent" -qO- "$url" 2>/dev/null)
    else
        return 1
    fi
    patch=$(echo "$html" | sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' | head -n1)
    [ -n "$patch" ] && echo "$patch" || return 1
}

pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    [ "$(echo "$d1" | tr -d '-')" -ge "$(echo "$d2" | tr -d '-')" ] && echo "$d1" || echo "$d2"
}

# ---------- 更新模块状态描述 ----------
update_module_status() {
    local prop_file="$1"
    local base_dir="$2"
    local patch_config="$3"
    [ -f "$prop_file" ] || return 0
    local app_count=0
    [ -f "$base_dir/target.txt" ] && app_count=$(wc -l < "$base_dir/target.txt")
    local patch_date="未配置"
    [ -f "$patch_config" ] && patch_date=$(grep '^boot=' "$patch_config" | cut -d'=' -f2)
    [ -z "$patch_date" ] && patch_date="未知"
    local status_text="[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
    sed -i "s@^description=.*@description=${status_text}@" "$prop_file" 2>/dev/null
}

# ---------- 安全补丁更新逻辑（供 action/service 共用） ----------
# 参数：$1 = BASE_DIR, $2 = PATCH_CONFIG_FILE, $3 = PATCH_CACHE_FILE, $4 = PROP_FILE, $5 = FORCE_MODE (0/1)
update_security_patch_core() {
    local base_dir="$1"
    local patch_config="$2"
    local cache_file="$3"
    local prop_file="$4"
    local force_mode="${5:-0}"

    local system_date=$(get_system_date)
    [ -z "$system_date" ] && { echo "无法获取系统补丁日期" >&2; return 1; }
    local sys_ym="${system_date%-*}"

    local need_online=0
    if [ -f "$cache_file" ] && [ $force_mode -eq 0 ]; then
        [ "$(cat "$cache_file")" != "$sys_ym" ] && need_online=1
    else
        need_online=1
    fi

    local final_date="$system_date"
    if [ $need_online -eq 1 ]; then
        local net_date=""
        local retry=0
        while [ $retry -lt 3 ] && [ -z "$net_date" ]; do
            for url in "https://source.android.com/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin/pixel"; do
                net_date=$(fetch_online_date "$url")
                [ -n "$net_date" ] && break
            done
            [ -z "$net_date" ] && { retry=$((retry+1)); sleep 2; }
        done
        if [ -n "$net_date" ]; then
            local newer=$(pick_newer "$system_date" "$net_date")
            if [ "$newer" = "$net_date" ] && [ "$net_date" != "$system_date" ]; then
                final_date="$net_date"
                echo "使用网络日期: $final_date" >&2
            else
                echo "系统日期较新或相同" >&2
            fi
            echo "$sys_ym" > "$cache_file"
        else
            echo "网络请求失败，保留系统日期" >&2
        fi
    else
        echo "缓存命中 ($sys_ym)" >&2
    fi

    # 写入配置文件
    [ -f "$patch_config" ] && cp -f "$patch_config" "${patch_config}.bak"
    cat << EOF > "$patch_config"
system=$final_date
boot=$final_date
vendor=$final_date
EOF
    chmod 644 "$patch_config"
    chown root:root "$patch_config" 2>/dev/null
    update_module_status "$prop_file" "$base_dir" "$patch_config"
    echo "补丁配置写入: $final_date" >&2
}