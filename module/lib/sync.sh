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
                local err_log="${json}.awk_err"
                local tmp_out="${json}.tmp"

                # 使用 index() 替代正则，完全避免特殊字符问题
                awk -v new_apps="$apps_json" '
                    BEGIN { in_default=0; skip=0; printed=0; }
                    {
                        # 检测进入 default 块：行包含 "default" 且包含 "{"
                        if (!in_default && index($0, "\"default\"") && index($0, "{")) {
                            in_default=1
                        }
                        # 在 default 块内检测 "apps"
                        if (in_default && index($0, "\"apps\"")) {
                            print "      \"apps\": ["
                            print new_apps
                            print "      ],"
                            printed=1
                            skip=1
                            next
                        }
                        # 跳过原 apps 数组内容直到遇到 "]"
                        if (skip && index($0, "]")) {
                            skip=0
                            next
                        }
                        if (skip) next
                        # 正常打印其他行
                        print
                        # 检测 default 块结束：缩进为 4 空格且包含 "}"
                        if (in_default && substr($0, 1, 4) == "    " && index($0, "}")) {
                            in_default=0
                        }
                    }
                    END {
                        if (!printed) {
                            print "      \"apps\": ["
                            print new_apps
                            print "      ],"
                        }
                    }
                ' "$json" > "$tmp_out" 2> "$err_log"

                if [ $? -eq 0 ] && [ -s "$tmp_out" ]; then
                    mv -f "$tmp_out" "$json" && chmod 644 "$json" 2>/dev/null
                    write_ok=$?
                    log_info "已更新 config.json (只修改 default profile)"
                else
                    if [ -s "$err_log" ]; then
                        log_err "awk 错误详情: $(cat "$err_log")"
                    else
                        log_err "awk 处理失败，但无具体错误输出"
                    fi
                    rm -f "$tmp_out" "$err_log" 2>/dev/null
                    write_ok=1
                fi
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