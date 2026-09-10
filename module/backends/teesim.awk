# TS-AUTO-ADD : replace ONLY profiles.default.apps inside TEE Simulator config.json
# everything else (other fields, other profiles) is preserved byte for byte.
#
# usage: awk -v listfile=<packages, one per line> -v statusfile=<marker> -f backends/teesim.awk config.json
# statusfile gets "ok" on success or "fail" when the apps array cannot be located.

function findstr(s, from, needle,   i, l) {
    l = length(needle)
    for (i = from; i + l - 1 <= length(s); i++)
        if (substr(s, i, l) == needle) return i
    return 0
}

# return index of the bracket closing the one at openpos (string aware)
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

BEGIN {
    n = 0
    while ((getline ln < listfile) > 0)
        if (ln != "") { n++; items[n] = ln }
    close(listfile)
}

{ buf = buf $0 "\n" }

END {
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

    # indentation of the "apps" line; items go two spaces deeper
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

    body = ""
    for (i = 1; i <= n; i++) {
        body = body ind "  \"" items[i] "\""
        if (i < n) body = body ","
        body = body "\n"
    }

    printf "%s", substr(buf, 1, ab - 1) "[\n" body ind "]" substr(buf, ae + 1)
    print "ok" > statusfile
}
