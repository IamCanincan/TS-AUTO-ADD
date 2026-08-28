#!/system/bin/sh
# ============================================================================
#  TS-AUTO-ADD · 核心引擎
#  监听 /data/app，对比包名集合，仅实际变化时同步
#  规则：+ 包含，- 排除，无前缀默认包含
#  用法：ts-sync [--daemon|--status|--log|--stop|--help]
# ============================================================================

MODDIR="${0%/*}"
TS_BASE="/data/adb/tricky_store"
TEESIM_BASE="/data/adb/teesim"
RULES_FILE="${MODDIR}/rules.txt"
LOG_FILE="/data/adb/ts_auto.log"
RUNDIR="/data/adb/ts_auto_runtime"
PID_FILE="${RUNDIR}/daemon.pid"
LOCK_DIR="${RUNDIR}/sync.lock"
DEBOUNCE_FILE="${RUNDIR}/.debounce"
CACHE_FILE="${RUNDIR}/package_cache"
DEBOUNCE_SECONDS=3
LOCK_TIMEOUT=10
LOG_WRITE_COUNT=0
LOG_CHECK_INTERVAL=10

# 颜色（终端输出）
if [ -t 1 ]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi
ok() { echo "${GREEN}✓${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*" >&2; }
err() { echo "${RED}✗${NC} $*" >&2; }
info() { echo "${BLUE}▶${NC} $*"; }

# 日志（延迟轮转检查）
log() {
    LOG_WRITE_COUNT=$((LOG_WRITE_COUNT + 1))
    if [ $LOG_WRITE_COUNT -ge $LOG_CHECK_INTERVAL ] && [ -f "$LOG_FILE" ]; then
        LOG_WRITE_COUNT=0
        [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 5242880 ] &&
            mv -f "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

# 环境检测：探测 TrickyStore / TeeSimulator
# 返回值：0=TrickyStore 1=TeeSimulator 2=同时存在(冲突) 3=未检测到
detect_env() {
    local ts=0 te=0
    { [ -d "$TS_BASE" ] || [ -d "/data/adb/modules/tricky_store" ]; } && ts=1
    { [ -d "$TEESIM_BASE" ] || [ -d "/data/adb/modules/teesim" ]; } && te=1
    if [ $ts -eq 1 ] && [ $te -eq 1 ]; then
        return 2
    fi
    if [ $ts -eq 1 ]; then
        TARGET="TS"; BASE="$TS_BASE"; TAA="$TS_BASE/taa_sys.txt"; return 0
    fi
    if [ $te -eq 1 ]; then
        TARGET="TEESIM"; BASE="$TEESIM_BASE"; TAA="$TEESIM_BASE/taa_sys.txt"; return 1
    fi
    return 3
}

# 文件锁
lock() {
    mkdir -p "$RUNDIR"
    local w=0
    while [ $w -lt $LOCK_TIMEOUT ]; do
        mkdir "$LOCK_DIR" 2>/dev/null && { echo $$ > "$LOCK_DIR/pid"; return 0; }
        [ -f "$LOCK_DIR/pid" ] && { kill -0 "$(cat "$LOCK_DIR/pid")" 2>/dev/null || rmdir "$LOCK_DIR" 2>/dev/null; }
        sleep 1; w=$((w+1))
    done
    return 1
}
unlock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

# 获取第三方应用列表
get_pkgs() {
    pm list packages -3 2>/dev/null | sed -n 's/^package://p' | sed '/^$/d'
}

# 计算包名集合指纹（用于判断是否真正变化）
get_package_fingerprint() {
    pm list packages -3 2>/dev/null | sed -n 's/^package://p' | sort | md5sum | awk '{print $1}'
}

# 检查包名集合是否变化
has_package_changed() {
    local current_fp="$(get_package_fingerprint)"
    [ -z "$current_fp" ] && return 1
    if [ -f "$CACHE_FILE" ]; then
        local cached_fp="$(cat "$CACHE_FILE" 2>/dev/null)"
        [ "$current_fp" = "$cached_fp" ] && return 1
    fi
    echo "$current_fp" > "$CACHE_FILE"
    return 0
}

# 合并规则（+ 包含，- 排除，无前缀默认包含）
merge_rules() {
    local out="$1"
    : > "$out"
    : > "${RUNDIR}/include.tmp"
    : > "${RUNDIR}/exclude.tmp"

    if [ -f "$RULES_FILE" ]; then
        grep -vE '^\s*(#|$)' "$RULES_FILE" | while read -r line; do
            case "$line" in
                "+"*) echo "${line#+}" >> "${RUNDIR}/include.tmp" ;;
                "-"*) echo "${line#-}" >> "${RUNDIR}/exclude.tmp" ;;
                *)    echo "$line" >> "${RUNDIR}/include.tmp" ;;
            esac
        done
    fi

    {
        [ -f "$TAA" ] && cat "$TAA" 2>/dev/null
        [ -f "${RUNDIR}/include.tmp" ] && cat "${RUNDIR}/include.tmp" 2>/dev/null
        get_pkgs
    } | sort -u > "$out"

    [ -f "${RUNDIR}/exclude.tmp" ] && grep -Fxv -f "${RUNDIR}/exclude.tmp" "$out" > "${out}.tmp" && mv "${out}.tmp" "$out"

    rm -f "${RUNDIR}/include.tmp" "${RUNDIR}/exclude.tmp"

    # 更新 taa_sys.txt（供目标模块自身使用）
    if [ -f "$RULES_FILE" ]; then
        grep -vE '^\s*(#|$)' "$RULES_FILE" | while read -r line; do
            case "$line" in
                "+"*) echo "${line#+}" ;;
                "-"*) ;;
                *)    echo "$line" ;;
            esac
        done | sort -u > "$TAA" 2>/dev/null
        chmod 640 "$TAA" 2>/dev/null
    fi
}

# 确保 TeeSim config.json 存在（已存在则不动，尊重用户自定义字段）
ensure_json() {
    [ -f "$TEESIM_BASE/config.json" ] && grep -q '"profiles"' "$TEESIM_BASE/config.json" 2>/dev/null && return
    mkdir -p "$TEESIM_BASE"
    cat > "$TEESIM_BASE/config.json" <<-'EOF'
{"version":1,"profiles":{"default":{"keybox":"keybox.xml","mode":"patch","patchLevel":{"system":"today","vendor":"YYYY-MM-05","boot":"YYYY-MM-05"},"osVersion":"","brand":"","device":"","product":"","manufacturer":"","model":"","serial":"","imei":"","meid":"","imei2":"","apps":["com.android.vending","com.google.android.gms","com.google.android.gsf"]}}}
EOF
    chmod 644 "$TEESIM_BASE/config.json"
}

# 同步主流程
do_sync() {
    log "开始同步"
    local tmp="${RUNDIR}/merged.tmp"
    merge_rules "$tmp"
    [ ! -s "$tmp" ] && { log "合并结果为空"; rm -f "$tmp"; return 0; }
    local count=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')

    case "$TARGET" in
        TS)
            cp -f "$tmp" "$BASE/target.txt" 2>/dev/null && chmod 644 "$BASE/target.txt" 2>/dev/null
            log "已更新 target.txt ($count 个包)"
            ok "已更新 target.txt ($count 个包)"
            ;;
        TEESIM)
            ensure_json
            local inner
            inner="$(awk '{printf "%s\"%s\"", (NR>1?",":""), $0}' "$tmp")"
            if awk -v apps="$inner" '
                BEGIN { RS="\0"; ORS="" }
                {
                    s=$0; p=index(s, "\"apps\"");
                    if (!p) exit 1
                    r=substr(s, p); c=index(r, ":");
                    b=index(substr(r, c), "[");
                    st=p+c+b-1; d=0; en=0;
                    for (i=st; i<=length(s); i++) {
                        x=substr(s, i, 1);
                        if (x=="[") d++;
                        if (x=="]") { d--; if (d==0) { en=i; break } }
                    }
                    if (!en) exit 1
                    printf "%s\"apps\":[%s]%s", substr(s, 1, p-1), apps, substr(s, en+1)
                }
            ' "$TEESIM_BASE/config.json" > "$TEESIM_BASE/config.json.tmp" 2>/dev/null \
               && [ -s "$TEESIM_BASE/config.json.tmp" ]; then
                mv -f "$TEESIM_BASE/config.json.tmp" "$TEESIM_BASE/config.json" 2>/dev/null
                chmod 644 "$TEESIM_BASE/config.json" 2>/dev/null
                log "已更新 config.json ($count 个包)"
                ok "已更新 config.json ($count 个包)"
            else
                rm -f "$TEESIM_BASE/config.json.tmp" 2>/dev/null
                err "config.json 更新失败（未找到 apps 字段或解析错误）"
                log "config.json 更新失败（未找到 apps 字段或解析错误）"
            fi
            ;;
    esac
    rm -f "$tmp"
    sed -i "s/^description=.*/description=✅ 已同步 $(date '+%H:%M')/" "$MODDIR/module.prop" 2>/dev/null
    log "同步完成"
}

# 查找 inotify 工具
find_inotify() {
    for cmd in inotifywait inotifyd; do
        command -v "$cmd" >/dev/null 2>&1 && { echo "$cmd:$(command -v "$cmd")"; return 0; }
    done
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox; do
        [ -x "$bb" ] || continue
        "$bb" --list 2>/dev/null | grep -q "^inotifywait$" && { echo "inotifywait:$bb inotifywait"; return 0; }
        "$bb" --list 2>/dev/null | grep -q "^inotifyd$" && { echo "inotifyd:$bb inotifyd"; return 0; }
    done
    return 1
}

# 守护进程
start_daemon() {
    mkdir -p "$RUNDIR"; echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; exit 0' INT TERM EXIT
    log "守护进程启动 (pid=$$)"

    detect_env
    [ $? -gt 1 ] && { log "环境异常"; exit 1; }

    local info="$(find_inotify)"
    [ -z "$info" ] && { log "inotify 不可用"; exit 1; }
    local mode="${info%%:*}"; local cmd="${info#*:}"
    log "inotify 模式: $mode, 监听目录: /data/app"

    # 首次检查（延迟 3 秒，等待系统稳定）
    sleep 3
    if has_package_changed; then
        log "首次同步"
        lock && { do_sync; unlock; }
    else
        log "包名集合未变化，跳过首次同步"
    fi

    # 监听 /data/app 目录
    if [ "$mode" = "inotifywait" ]; then
        $cmd -m -e create,delete,moved_to,moved_from "/data/app" 2>/dev/null | while read -r line; do
            log "检测到 /data/app 变化: $line"
            local now=$(date +%s)
            [ -f "$DEBOUNCE_FILE" ] && [ $(($now - $(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0))) -lt $DEBOUNCE_SECONDS ] && continue
            echo "$now" > "$DEBOUNCE_FILE"
            if has_package_changed; then
                log "包名集合变化，执行同步"
                lock && { do_sync; unlock; }
            else
                log "包名集合未变化，跳过同步"
            fi
        done
    else
        $cmd - "/data/app:cd" 2>/dev/null | while read -r event file; do
            log "检测到 /data/app 变化: $event $file"
            local now=$(date +%s)
            [ -f "$DEBOUNCE_FILE" ] && [ $(($now - $(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0))) -lt $DEBOUNCE_SECONDS ] && continue
            echo "$now" > "$DEBOUNCE_FILE"
            if has_package_changed; then
                log "包名集合变化，执行同步"
                lock && { do_sync; unlock; }
            else
                log "包名集合未变化，跳过同步"
            fi
        done
    fi
}

# =============================================================================
# 入口
# =============================================================================
[ "$(id -u)" -ne 0 ] && { err "需要 root 权限"; exit 1; }

detect_env
case $? in
    0) ok "目标: TrickyStore" ;;
    1) ok "目标: TeeSimulator" ;;
    2) err "同时检测到 TrickyStore 和 TeeSimulator，冲突"; exit 1 ;;
    3) warn "未检测到目标模块，将等待环境就绪" ;;
esac

case "$1" in
    --daemon)    start_daemon; exit 0 ;;
    --status)
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null)
            kill -0 "$pid" 2>/dev/null && ok "守护进程运行中 (pid=$pid)" || warn "守护进程已停止"
        else
            warn "守护进程未运行"
        fi
        exit 0
        ;;
    --log)
        [ -f "$LOG_FILE" ] && tail -n 30 "$LOG_FILE" || warn "日志不存在"
        exit 0
        ;;
    --stop)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null && ok "已停止"
            rm -f "$PID_FILE"
        else
            warn "守护进程未运行"
        fi
        exit 0
        ;;
    --help)
        cat << 'EOF'
用法: ts-sync [选项]
  无参数       手动同步一次
  --daemon     启动守护进程（监听 /data/app，包名集合对比）
  --status     查看守护进程状态
  --log        查看最近日志
  --stop       停止守护进程
  --help       显示帮助

规则文件: rules.txt
  + 包名  包含（始终加入目标列表）
  - 包名  排除（即使已安装也不加入）
  无前缀  等同 +

省电机制:
  监听 /data/app（应用更新不触发）
  包名集合对比（真正变化才同步）
  防抖窗口 3 秒
  无事件时进程挂起，零 CPU 占用
EOF
        exit 0
        ;;
esac

# 默认：手动同步
info "手动同步中..."
lock || { err "获取锁失败"; exit 1; }
do_sync
unlock
ok "完成"