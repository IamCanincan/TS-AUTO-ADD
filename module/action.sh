#!/system/bin/sh
# 模块调试管理工具: action.sh
# 职责: 供终端手动直接调用，实时触发全量校对流，并同步刷新 module.prop 状态

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
PATCH_CONFIG_FILE="$BASE/security_patch.txt"

clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

force_to_05() {
    local in_date="$1"
    if [ -n "$in_date" ]; then
        case "$in_date" in
            *-01) echo "${in_date%-01}-05" ;;
            *) echo "$in_date" ;;
        esac
    fi
}

update_module_status() {
    [ -f "$PROP_FILE" ] || return 0
    local app_count=0
    if [ -f "$BASE/target.txt" ]; then
        app_count=$(wc -l < "$BASE/target.txt")
    fi
    local patch_date="未配置"
    if [ -f "$PATCH_CONFIG_FILE" ]; then
        patch_date=$(grep '^boot=' "$PATCH_CONFIG_FILE" | cut -d'=' -f2)
        [ -z "$patch_date" ] && patch_date="未知"
    fi
    local status_text="[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
    
    local tmp_prop="${PROP_FILE}.tmp"
    rm -f "$tmp_prop"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            description=*)
                # 仅保留模块运行状态
                echo "description=${status_text}" >> "$tmp_prop"
                ;;
            *)
                echo "$line" >> "$tmp_prop"
                ;;
        esac
    done < "$PROP_FILE"
    
    if [ -f "$tmp_prop" ]; then
        mv -f "$tmp_prop" "$PROP_FILE"
        chmod 644 "$PROP_FILE"
    fi
}

fetch_online_date() {
    local url="$1"
    local html=""
    if command -v curl >/dev/null 2>&1; then
        html=$(curl --connect-timeout 5 -Ls "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        html=$(wget -T 5 --no-check-certificate -qO- "$url" 2>/dev/null)
    else
        return 1
    fi

    local all_dates=$(echo "$html" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | grep -E '\-01$|\-05$')
    [ -z "$all_dates" ] && return 1

    local kv_lines=$(echo "$html" | grep -iE 'security patch level|安全补丁级别|bulletin|公告')
    if [ -n "$kv_lines" ]; then
        local raw_date=$(echo "$kv_lines" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | grep -E '\-01$|\-05$' | sort -r | head -n 1)
        if [ -n "$raw_date" ]; then
            force_to_05 "$raw_date"
            return
        fi
    fi

    local raw_date_backup=$(echo "$all_dates" | sort -r | head -n 1)
    force_to_05 "$raw_date_backup"
}

pick_newer() {
    local d1="$1" d2="$2"
    [ -z "$d1" ] && { echo "$d2"; return; }
    [ -z "$d2" ] && { echo "$d1"; return; }
    local n1=$(echo "$d1" | tr -d '-')
    local n2=$(echo "$d2" | tr -d '-')
    [ "$n1" -ge "$n2" ] && echo "$d1" || echo "$d2"
}

clear
echo "===================================================="
echo "          TS-AUTO-ADD 核心配置与技术诊断工具"
echo "===================================================="
echo " 启动时间 : $(date '+%Y-%m-%d %H:%M:%S')"
echo " 工作路径 : $BASE"
echo "===================================================="

echo ""
echo "[阶段 1/2] 开始执行第三方应用包名深度同步..."
echo "----------------------------------------------------"
mkdir -p "$BASE"
APPS_3=$(pm list packages -3 2>/dev/null | sed -n 's/^package://p')
APPS_3_COUNT=$(echo "$APPS_3" | grep -c "$")

{
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
    echo "$APPS_3"
} | sort -u > "$BASE/.ts_tmp"

if [ -s "$BASE/.ts_tmp" ]; then
    if ! cmp -s "$BASE/.ts_tmp" "$BASE/target.txt"; then
        mv -f "$BASE/.ts_tmp" "$BASE/target.txt"
        chmod 644 "$BASE/target.txt"
    else
        rm -f "$BASE/.ts_tmp"
    fi
    TOTAL_LINES=$(wc -l < "$BASE/target.txt")
    echo " [状态] 阶段 1 (应用同步任务) 执行完毕 -> 成功"
else
    rm -f "$BASE/.ts_tmp"
    echo " [状态] 阶段 1 (应用同步任务) 执行完毕 -> 异常"
fi

echo ""
echo "[阶段 2/2] 开始执行安全补丁日期全网动态同步..."
echo "----------------------------------------------------"
SYS_PROP_DATE=$(force_to_05 "$(clean_date "$(getprop ro.build.version.security_patch)")")
rm -f "$BASE/.last_month"

URL1="https://source.android.google.cn/docs/security/bulletin/pixel"
NET_DATE=$(fetch_online_date "$URL1")

if [ -z "$NET_DATE" ]; then
    URL2="https://source.android.google.cn/docs/security/bulletin"
    NET_DATE=$(fetch_online_date "$URL2")
fi

FINAL_DATE=$(pick_newer "$SYS_PROP_DATE" "$NET_DATE")

if [ -f "$BASE/security_patch.txt" ]; then
    cp -f "$BASE/security_patch.txt" "$BASE/security_patch.txt.bak"
fi

cat << EOF > "$BASE/security_patch.txt"
system=prop
boot=$FINAL_DATE
vendor=$FINAL_DATE
EOF
chmod 644 "$BASE/security_patch.txt"
chown root:root "$BASE/security_patch.txt" 2>/dev/null

echo "     -> 当前容器文件内写入明细表:"
echo "        +----------------------------------------+"
while IFS= read -r line; do
    printf "        | %-38s |\n" "$line"
done < "$BASE/security_patch.txt"
echo "        +----------------------------------------+"
echo " [状态] 阶段 2 (补丁同步任务) 执行完毕 -> 成功"

# 强制刷新状态至 module.prop
update_module_status

echo ""
echo "===================================================="
echo " [结论] 模块诊断与强制覆盖圆满结束"
echo "===================================================="
exit 0