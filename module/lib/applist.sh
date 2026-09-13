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

# ---------- 规则文件规范化 ----------
# 说明：修正两类会污染包名的写法问题（尽力而为，失败不影响后续流程）：
#       1) 末行缺少换行符——否则用户再用「echo 包名 >> rules.txt」追加时，
#          新包名会与最后一行粘成一行；
#       2) 文件开头带 UTF-8 BOM——会让第一个包名带上不可见前缀。
# 用法：normalize_rules_file <rules.txt 路径>
normalize_rules_file() {
    local file="$1"

    [ -f "$file" ] || return 0

    # 末行换行：tail -c1 取最后一个字节，取不到内容说明已以换行结尾
    if [ -n "$(tail -c 1 "$file" 2>/dev/null)" ]; then
        echo >> "$file" 2>/dev/null
    fi

    # UTF-8 BOM：与 BOM 三字节直接比较，命中则从第 4 字节起重写文件
    if [ "$(head -c 3 "$file" 2>/dev/null)" = "$(printf '\357\273\277')" ]; then
        if tail -c +4 "$file" > "${file}.bom" 2>/dev/null; then
            chmod 640 "${file}.bom" 2>/dev/null
            chown root:root "${file}.bom" 2>/dev/null
            chcon system_data_file "${file}.bom" 2>/dev/null || true
            mv -f "${file}.bom" "$file" 2>/dev/null
        fi
        rm -f "${file}.bom" 2>/dev/null
    fi

    return 0
}

# ---------- 读取常驻列表 ----------
# 说明：输出 rules.txt 中有效的包名：去掉行首行尾空白、忽略注释行与空行。
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
    normalize_rules_file "$RULES_FILE"

    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    user_list=$(echo "$apps_raw" | sed -n 's/^package://p')

    # 两段之间补一个空行：部分 sed 实现不会为「末行无换行」补行尾换行，
    # 补空行可避免 rules.txt 末行与应用清单首行粘连；空行随后被过滤
    { read_rules; echo; echo "$user_list"; } | sort -u | sed '/^$/d' > "$tmp" 2>/dev/null

    TAA_COUNT=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')
}
