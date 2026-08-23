#!/system/bin/sh
# sync.sh - 使用单行替换方式更新 apps 数组

do_sync() {
    log_info "开始同步包列表"
    ensure_taa_sys "$TAA_SYS_FILE"

    local user_list="$(get_installed_packages)"
    local user_count="$(count_lines "$user_list")"
    local sys_count="$( [ -f "$TAA_SYS_FILE" ] && grep -c . "$TAA_SYS_FILE" 2>/dev/null || echo 0 )"

    [ "$user_count" -eq 0 ] && { log_warn "第三方应用列表为空，跳过本次同步"; return 0; }

    local tmp_file="$TARGET_BASE/.ts_tmp"
    merge_and_dedupe "$TAA_SYS_FILE" "$user_list" > "$tmp_file" 2>/dev/null
    if [ ! -s "$tmp_file" ]; then
        log_warn "合并结果为空"
        rm -f "$tmp_file"
        return 0
    fi

    local write_ok=0
    case "$TARGET_TYPE" in
        TS)
            cp -f "$tmp_file" "$TARGET_BASE/target.txt" 2>/dev/null && chmod 644 "$TARGET_BASE/target.txt" 2>/dev/null
            write_ok=$?
            log_info "已更新 target.txt"
            ;;
        TEESIM)
            local json="$TARGET_BASE/config.json"
            if [ ! -f "$json" ]; then
                log_err "config.json 不存在，跳过"
                rm -f "$tmp_file"
                return 0
            fi

            # 检查 apps 出现次数
            local apps_count=$(grep -c '"apps"' "$json" 2>/dev/null || echo 0)
            if [ "$apps_count" -ne 1 ]; then
                log_warn "config.json 结构异常（apps 出现 $apps_count 次），重置为默认模板"
                cat > "$json" <<-EOF
{
  "version": 1,
  "profiles": {
    "default": {
      "keybox": "keybox.xml",
      "mode": "patch",
      "patchLevel": {
        "system": "today",
        "vendor": "YYYY-MM-05",
        "boot": "YYYY-MM-05"
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
      "apps": [],
      "autoIncludeNewApps": false
    }
  }
}
EOF
                apps_count=1
            fi

            # 生成紧凑的 apps 列表行
            local apps_line="      \"apps\": ["
            local first=1
            while read -r pkg; do
                [ -z "$pkg" ] && continue
                if [ $first -eq 1 ]; then
                    apps_line="$apps_line \"$pkg\""
                    first=0
                else
                    apps_line="$apps_line, \"$pkg\""
                fi
            done < "$tmp_file"
            apps_line="$apps_line ],"

            # 转义 apps_line 中的特殊字符（/、&、\）以供 sed 使用
            escaped_apps_line=$(printf '%s\n' "$apps_line" | sed 's/[\/&]/\\&/g')

            # 使用 sed 替换 "apps": [ ... ], 这一行（仅替换第一次匹配）
            sed -i "0,/\"apps\": [^]]*,/s//$escaped_apps_line/" "$json"
            if [ $? -eq 0 ]; then
                write_ok=0
                log_info "已更新 config.json (apps 列表)"
            else
                log_err "替换 apps 列表失败"
                write_ok=1
            fi
            ;;
    esac

    rm -f "$tmp_file"

    if [ $write_ok -eq 0 ]; then
        local current_time="$(date '+%H:%M')"
        local new_desc="✅ 运行中 (环境: ${TARGET_TYPE} | 系统: ${sys_count} | 用户: ${user_count} | 更新: ${current_time})"
        update_module_prop "$PROP_FILE" "$new_desc"
        log_info "同步完成"
    else
        log_warn "同步完成但写入配置失败"
    fi
    return 0
}