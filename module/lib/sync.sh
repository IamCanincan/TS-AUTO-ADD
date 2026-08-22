# sync.sh - 同步核心流程

do_sync() {
    log_info "开始同步包列表"
    ensure_taa_sys "$TAA_SYS_FILE"
    local user_list="$(get_installed_packages)"
    local user_count="$(count_lines "$user_list")"
    local sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"

    if [ "$user_count" -eq 0 ]; then
        log_warn "第三方应用列表为空，跳过本次同步"
        return
    fi

    local tmp_file="$TARGET_BASE/.ts_tmp"
    merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
    if [ -s "$tmp_file" ]; then
        write_target_config "$tmp_file"
        log_info "同步完成，系统白名单: $sys_count，第三方应用: $user_count"
    else
        log_warn "同步失败：合并结果为空"
    fi
    rm -f "$tmp_file" 2>/dev/null

    local current_time="$(date '+%H:%M')"
    local new_desc="✅ 运行中 (环境: ${TARGET_TYPE} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time})"
    update_module_prop "$PROP_FILE" "$new_desc"
}