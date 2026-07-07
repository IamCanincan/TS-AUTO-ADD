#!/system/bin/sh
#=============================================================================
# common.sh - 公共原子函数库
# 优化策略：控制网络边界超时、精简 shell 中的 fork() 外部进程调用
#=============================================================================

# [锁机制] 基于文件系统 mkdir 调用的原子性（Atomic）实现轻量级互斥
# 超时降低至 15 秒，客观上加速了并发时的状态释放，避免长时间持锁引发死锁
acquire_lock() {
    local lock_dir="$1"
    local timeout=15 
    local waited=0
    while [ $waited -lt $timeout ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo " [警告] 锁获取超时，强行接管..." >&2
    rmdir "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || return 1
    return 0
}

release_lock() {
    rmdir "$1" 2>/dev/null
}

clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

# [Tricky Store 规约] 强刷安全补丁为每月 5 号以满足某些特异性 TEE 验证规则
force_to_05() {
    local in_date="$1"
    [ -n "$in_date" ] || return
    case "$in_date" in *-01) echo "${in_date%-01}-05" ;; *) echo "$in_date" ;; esac
}

get_system_date() {
    force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")"
}

# [网络安全边界] 
# [客观风险] 无网环境或受限网络下，curl/wget 会长时间阻塞并持有 TCP 状态，导致系统无线电及 CPU 无法深睡眠
# [优化行为] 将连接超时强限制在 3 秒，传输限时 6 秒，一旦失败立刻释放网络套接字，防止耗电
fetch_online_date() {
    local url="$1" html="" patch=""
    local user_agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
    
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 3 -m 6 -Ls -A "$user_agent" "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 6 --connect-timeout=3 --no-check-certificate -U "$user_agent" -qO- "$url" 2>/dev/null)
    else
        return 1
    fi
    
    # 纯文本解析过滤
    patch=$(echo "$html" | sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' | head -n1)
    [ -n "$patch" ] && echo "$patch" || return 1
}

# 比较时间戳：客观去除 '-' 符号转化为纯整数，利用 Shell 内建的原生算术比对代替调用外部 expr 命令
pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    [ "$(echo "$d1" | tr -d '-')" -ge "$(echo "$d2" | tr -d '-')" ] && echo "$d1" || echo "$d2"
}

update_module_status() {
    local prop_file="$1" base_dir="$2" patch_config="$3"
    [ -f "$prop_file" ] || return 0
    local app_count=0
    [ -f "$base_dir/target.txt" ] && app_count=$(wc -l < "$base_dir/target.txt")
    local patch_date="未配置"
    [ -f "$patch_config" ] && patch_date=$(grep '^boot=' "$patch_config" | cut -d'=' -f2)
    [ -z "$patch_date" ] && patch_date="未知"
    
    local status_text="[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
    sed -i "s@^description=.*@description=${status_text}@" "$prop_file" 2>/dev/null
}

update_security_patch_core() {
    local base_dir="$1" patch_config="$2" cache_file="$3" prop_file="$4" force_mode="${5:-0}"
    local system_date=$(get_system_date)
    [ -z "$system_date" ] && return 1
    local sys_ym="${system_date%-*}"

    # [缓存控制机制] 当本地保存的月份与当前系统月份一致且非强刷模式时，不触发网络请求，零网络开销
    local need_online=0
    if [ -f "$cache_file" ] && [ "$force_mode" -eq 0 ]; then
        [ "$(cat "$cache_file")" != "$sys_ym" ] && need_online=1
    else
        need_online=1
    fi

    local final_date="$system_date"
    if [ $need_online -eq 1 ]; then
        local net_date="" retry=0
        while [ $retry -lt 2 ] && [ -z "$net_date" ]; do
            for url in "https://source.android.com/docs/security/bulletin/pixel" "https://source.android.google.cn/docs/security/bulletin/pixel"; do
                net_date=$(fetch_online_date "$url")
                [ -n "$net_date" ] && break
            done
            [ -z "$net_date" ] && { retry=$((retry+1)); sleep 3; }
        done
        
        if [ -n "$net_date" ]; then
            local newer=$(pick_newer "$system_date" "$net_date")
            if [ "$newer" = "$net_date" ] && [ "$net_date" != "$system_date" ]; then
                final_date="$net_date"
            fi
            echo "$sys_ym" > "$cache_file"
        fi
    fi

    # [I/O 隔离] 写入 .tmp 临时文件再通过 mv 替换原始目标，利用 POSIX 标准的覆盖原子性防止配置在写一半时由于断电引发损坏
    echo -e "system=$final_date\nboot=$final_date\nvendor=$final_date" > "${patch_config}.tmp"
    chmod 644 "${patch_config}.tmp"
    mv -f "${patch_config}.tmp" "$patch_config"
    
    update_module_status "$prop_file" "$base_dir" "$patch_config"
}