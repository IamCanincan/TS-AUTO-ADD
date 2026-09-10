#!/system/bin/sh
#=============================================================================
# lib/applist.sh - 常驻列表与应用列表生成
#
# rules.txt 规则：
#   每行一个包名；以 # 开头的行视为注释；空行忽略；行首行尾空白会去掉。
#=============================================================================

# ---------- 常驻列表 ----------
# 说明：rules.txt 不存在时写入默认内容（Google 三件套 + 中文说明注释）
# 用法：ensure_rules_file <rules.txt 路径>
ensure_rules_file() {
    local file="$1"

    [ -f "$file" ] && return 0

    printf '%s\n' \
        "# TS-AUTO-ADD 常驻应用列表" \
        "# 每行一个包名；以 # 开头的行是注释，空行会被忽略。" \
        "# 这里列出的包名会始终并入目标列表（即使应用当前未安装）。" \
        "" \
        "com.android.vending" \
        "com.google.android.gms" \
        "com.google.android.gsf" > "$file" 2>/dev/null

    chmod 640 "$file" 2>/dev/null
    chown root:root "$file" 2>/dev/null
    chcon system_data_file "$file" 2>/dev/null || true
}

# ---------- 读取常驻列表 ----------
# 说明：输出 rules.txt 中有效的包名：去掉行首行尾空白、忽略注释行与空行。
#       sed 会为每行补齐换行符，因此调用方无需再处理“末行无换行”的情况。
# 用法：read_rules
read_rules() {
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^#/d; /^$/d' "$RULES_FILE" 2>/dev/null
}

# ---------- 应用列表生成 ----------
# 说明：常驻列表 + 已安装第三方应用，去重排序后写入指定文件，并设置 TAA_COUNT。
# 用法：build_app_list <输出文件>
build_app_list() {
    local tmp="$1"
    local apps_raw user_list

    mkdir -p "$TAA_DIR" 2>/dev/null
    ensure_rules_file "$RULES_FILE"

    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    user_list=$(echo "$apps_raw" | sed -n 's/^package://p')

    # 常驻列表与应用清单合并去重；空行来自应用清单为空的情况，直接过滤
    { read_rules; echo "$user_list"; } | sort -u | sed '/^$/d' > "$tmp" 2>/dev/null

    TAA_COUNT=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')
}
