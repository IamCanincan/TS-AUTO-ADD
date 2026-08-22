#!/system/bin/sh
# sync.sh - 同步核心，只修改 default profile 的 apps 列表

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

            # 生成 apps 数组内容（缩进 6 个空格）
            local apps_json=$(sed 's/^/      "/; s/$/",/' "$tmp_file" | sed '$ s/,$//')

            if command -v awk >/dev/null 2>&1; then
                # 使用 awk 精确定位 "profiles" -> "default" -> "apps" 并进行替换
                awk -v new_apps="$apps_json" '
                    BEGIN { in_default=0; in_apps=0; printed=0; skip=0 }
                    # 检测 "profiles" 块开始（仅最外层）
                    /"profiles"[ \t]*:/ { in_profiles=1; print; next }
                    # 在 profiles 块内，遇到 "default" : { 标记
                    in_profiles && /"default"[ \t]*:/ { in_default=1; print; next }
                    # 在 default 块内，遇到 "apps" : [ 开始替换
                    in_default && /"apps"[ \t]*:/ {
                        print "      \"apps\": ["
                        print new_apps
                        print "      ],"
                        printed=1
                        skip=1
                        next
                    }
                    # 如果正在跳过 apps 数组内容，直到遇到 ] 结束
                    skip && /]/ {
                        skip=0
                        next
                    }
                    # 如果还在跳过，继续跳过
                    skip { next }
                    # 否则正常打印
                    { print }
                    # 当遇到 default 块的结束 } 时重置 in_default（但注意不要和 skip 冲突）
                    in_default && /}/ && !skip { in_default=0 }
                    # 当遇到 profiles 块的结束 } 时重置 in_profiles
                    in_profiles && /}/ && !skip { in_profiles=0 }
                    END {
                        # 如果 default 中没有 apps 字段，则添加
                        if (!printed) {
                            print "      \"apps\": ["
                            print new_apps
                            print "      ],"
                        }
                    }
                ' "$json" > "${json}.tmp" && mv -f "${json}.tmp" "$json" && chmod 644 "$json" 2>/dev/null
                write_ok=$?
                log_info "已更新 config.json (只修改 default profile)"
            else
                log_warn "awk 不可用，跳过 config.json 更新"
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