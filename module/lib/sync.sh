#!/system/bin/sh
# sync.sh - 使用 awk 替换 default 的 apps

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

            # 生成 apps 数组内容（缩进 6 空格，每行加引号和逗号）
            local apps_json=$(sed 's/^/      "/; s/$/",/' "$tmp_file" | sed '$ s/,$//')

            if command -v awk >/dev/null 2>&1; then
                # 使用 awk 处理：找到 default 块，然后在其中替换 apps 数组
                awk -v new_apps="$apps_json" '
                    BEGIN { depth=0; in_default=0; in_apps=0; skip=0; printed=0; line_buf=""; }
                    {
                        # 计算括号变化
                        open = gsub(/{/, "{", $0)
                        close = gsub(/}/, "}", $0)
                        # 但 gsub 改变了 $0，所以我们用原字符串，先复制
                        line = $0
                        open = 0; close = 0
                        for (i=1; i<=length(line); i++) {
                            c = substr(line, i, 1)
                            if (c == "{") open++
                            if (c == "}") close++
                        }
                        depth += open - close
                        
                        # 检查是否进入 default 块（depth 当前为1，且行匹配 "default"）
                        if (!in_default && depth == 1 && line ~ /"default"[ \t]*:/) {
                            in_default = 1
                            print line
                            next
                        }
                        
                        if (in_default) {
                            # 检查是否遇到 "apps"
                            if (!in_apps && line ~ /"apps"[ \t]*:/) {
                                # 输出新 apps 数组
                                print "      \"apps\": ["
                                print new_apps
                                print "      ],"
                                printed = 1
                                in_apps = 1
                                # 跳过直到匹配的 ]（我们记录当前 depth，当遇到 ] 且 depth 回到当前层级时停止）
                                skip_depth = depth - 1  # apps 数组括号内深度
                                skip = 1
                                next
                            }
                            
                            # 如果正在跳过 apps 数组
                            if (skip) {
                                # 遇到 ] 且深度等于 skip_depth，则结束跳过
                                if (line ~ /\]/ && depth == skip_depth) {
                                    skip = 0
                                    in_apps = 0
                                    next
                                }
                                # 否则跳过
                                next
                            }
                            
                            # 如果退出 default 块（depth 回到1）
                            if (depth == 1 && in_default) {
                                in_default = 0
                            }
                        }
                        
                        # 默认打印
                        if (!skip) {
                            print line
                        }
                    }
                    END {
                        if (!printed) {
                            print "WARNING: No apps array found in default profile." > "/dev/stderr"
                        }
                    }
                ' "$json" > "${json}.tmp" 2>>"$LOG_FILE"

                if [ $? -eq 0 ] && [ -s "${json}.tmp" ]; then
                    mv -f "${json}.tmp" "$json" && chmod 644 "$json" 2>/dev/null
                    write_ok=$?
                    log_info "已更新 config.json (只修改 default profile)"
                else
                    log_err "awk 处理失败，保留原文件"
                    rm -f "${json}.tmp" 2>/dev/null
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