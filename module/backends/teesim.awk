#=============================================================================
# backends/teesim.awk - TEE Simulator 后端定点替换
#
# 职责：只替换 config.json 中 profiles.default.apps 的内容；
#       其余字段、其余 profile 一律按原样保留（逐字节）。
#
# 用法：awk -v listfile=<每行一个包名> -v statusfile=<状态文件> -f backends/teesim.awk config.json
# 状态文件：成功写 "ok"；无法定位 apps 数组时写 "fail"（此时原样输出，不做修改）
#=============================================================================

# 说明：在字符串 s 中从 from 位置起查找 needle，返回下标（1 起），未找到返回 0
function findstr(s, from, needle,   i, l) {
    l = length(needle)
    for (i = from; i + l - 1 <= length(s); i++)
        if (substr(s, i, l) == needle) return i
    return 0
}

# 说明：返回与 openpos 处左括号配对的右括号下标，跳过字符串内的括号与转义
function matchclose(s, openpos,   i, c, depth, instr, esc) {
    depth = 0; instr = 0; esc = 0
    for (i = openpos; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (instr) {
            if (esc) { esc = 0 } else if (c == "\\") { esc = 1 } else if (c == "\"") { instr = 0 }
            continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") { depth--; if (depth == 0) return i }
    }
    return 0
}

# 说明：读取待写入的包名列表
BEGIN {
    n = 0
    while ((getline ln < listfile) > 0)
        if (ln != "") { n++; items[n] = ln }
    close(listfile)
}

# 说明：整文件读入缓冲区，便于按下标定点替换
{ buf = buf $0 "\n" }

END {
    # 定位 profiles -> default -> 该对象内的 apps 数组，任一步失败即放弃
    pp = findstr(buf, 1, "\"profiles\"")
    if (pp == 0) { print "fail" > statusfile; printf "%s", buf; exit }
    dp = findstr(buf, pp, "\"default\"")
    if (dp == 0) { print "fail" > statusfile; printf "%s", buf; exit }
    ob = findstr(buf, dp + 9, "{")
    if (ob == 0) { print "fail" > statusfile; printf "%s", buf; exit }
    cb = matchclose(buf, ob)
    if (cb == 0) { print "fail" > statusfile; printf "%s", buf; exit }
    ap = findstr(buf, ob, "\"apps\"")
    if (ap == 0 || ap > cb) { print "fail" > statusfile; printf "%s", buf; exit }
    ab = findstr(buf, ap + 6, "[")
    if (ab == 0 || ab > cb) { print "fail" > statusfile; printf "%s", buf; exit }
    ae = matchclose(buf, ab)
    if (ae == 0 || ae > cb) { print "fail" > statusfile; printf "%s", buf; exit }

    # 取 apps 所在行的缩进，数组元素在此基础上再缩进两格
    ls = ap
    while (ls > 1 && substr(buf, ls - 1, 1) != "\n") ls--
    ind = ""
    i = ls
    while (i < ap) {
        c = substr(buf, i, 1)
        if (c != " " && c != "\t") break
        ind = ind c
        i++
    }

    # 生成新数组内容（除最后一项外均补逗号）
    body = ""
    for (i = 1; i <= n; i++) {
        body = body ind "  \"" items[i] "\""
        if (i < n) body = body ","
        body = body "\n"
    }

    # 拼接：数组左括号之前 + 新数组 + 右括号之后
    printf "%s", substr(buf, 1, ab - 1) "[\n" body ind "]" substr(buf, ae + 1)
    print "ok" > statusfile
}
