#!/system/bin/sh
# ============================================================================
# TS-AUTO-ADD · 核心脚本
# 合并 rules.txt 白名单与第三方应用，写入 TrickyStore 的 target.txt 或
# TeeSimulator 的 config.json（profiles.default.apps）。
# 守护进程监听 /data/app 的安装/卸载自动同步。省电要点：事件驱动 + 防抖 +
# 包集合指纹去重，仅在真正变化时写入；无 inotify 时降级为低频轮询。
#
# 用法：ts-sync [--daemon|--status|--log|--stop|--help]
# ============================================================================

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:${PATH:-/bin}"

MODDIR="${0%/*}"

# ---- 路径与参数 ----
TS_DIR="/data/adb/tricky_store"
TEESIM_DIR="/data/adb/teesim"
RUNDIR="/data/adb/ts_auto_runtime"
RULES="$MODDIR/rules.txt"
LOG_FILE="/data/adb/ts_auto.log"
CACHE="$RUNDIR/packages.fp"
PID_FILE="$RUNDIR/daemon.pid"
LOCK_DIR="$RUNDIR/lock"
DEBOUNCE_FILE="$RUNDIR/debounce"

DEBOUNCE_SEC=3
LOCK_TIMEOUT=10
LOG_MAX_BYTES=5242880    # 5 MiB
POLL_INTERVAL=60         # 无 inotify 时的轮询间隔（秒）

# ---- 终端输出（非交互时去掉颜色）----
if [ -t 1 ]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi
ok()   { echo "${GREEN}✓${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*" >&2; }
err()  { echo "${RED}✗${NC} $*" >&2; }
info() { echo "${BLUE}▶${NC} $*"; }

# ---- 日志（超过上限轮转）----
log() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

# ---- 目标探测 -----------------------------------------------------------
# 返回 0=TrickyStore 1=TeeSimulator 2=冲突 3=未检测到；同时设置 TARGET / BASE。
detect_target() {
    local ts=0 te=0
    { [ -d "$TS_DIR" ] || [ -d /data/adb/modules/tricky_store ]; } && ts=1
    { [ -d "$TEESIM_DIR" ] || [ -d /data/adb/modules/teesim ]; } && te=1
    [ $ts -eq 1 ] && [ $te -eq 1 ] && return 2
    if [ $ts -eq 1 ]; then TARGET=TS; BASE="$TS_DIR"; return 0; fi
    if [ $te -eq 1 ]; then TARGET=TEESIM; BASE="$TEESIM_DIR"; return 1; fi
    return 3
}

# ---- 文件锁（mkdir 原子性；自动回收陈旧锁）-------------------------------
lock() {
    mkdir -p "$RUNDIR"
    local i=0
    while [ $i -lt "$LOCK_TIMEOUT" ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_DIR/pid"; return 0
        fi
        if [ -f "$LOCK_DIR/pid" ] && ! kill -0 "$(cat "$LOCK_DIR/pid")" 2>/dev/null; then
            rmdir "$LOCK_DIR" 2>/dev/null
        fi
        sleep 1; i=$((i+1))
    done
    return 1
}
unlock() { rmdir "$LOCK_DIR" 2>/dev/null; }

# ---- 第三方应用列表（规范排序，供指纹与合并复用）--------------------------
third_party() {
    pm list packages -3 2>/dev/null | sed -n 's/^package://p' | sort -u
}

# ---- 合并白名单 ----------------------------------------------------------
# 规则：+ 包含，- 排除，无前缀 = 包含。$2 复用已获取的第三方列表。
build_list() {
    local out="$1" list="$2" inc="$RUNDIR/inc.tmp" exc="$RUNDIR/exc.tmp" raw="$RUNDIR/raw.tmp"
    : > "$inc"; : > "$exc"
    if [ -f "$RULES" ]; then
        grep -vE '^[[:space:]]*(#|$)' "$RULES" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                "+"*) printf '%s\n' "${line#+}" >> "$inc" ;;
                "-"*) printf '%s\n' "${line#-}" >> "$exc" ;;
                *)    printf '%s\n' "$line"       >> "$inc" ;;
            esac
        done
    fi
    {
        cat "$inc" 2>/dev/null
        [ -n "$list" ] && printf '%s\n' "$list"
    } | sort -u > "$raw"
    if [ -s "$exc" ]; then
        grep -Fxv -f "$exc" "$raw" > "$out"
        rm -f "$raw"
    else
        mv -f "$raw" "$out"
    fi
    rm -f "$inc" "$exc"
}

# ---- 确保 TeeSimulator config.json 存在（已存在则不动）--------------------
ensure_json() {
    [ -f "$BASE/config.json" ] && grep -q '"profiles"' "$BASE/config.json" 2>/dev/null && return 0
    mkdir -p "$BASE"
    cat > "$BASE/config.json" <<'EOF'
{"version":1,"profiles":{"default":{"keybox":"keybox.xml","mode":"patch","patchLevel":{"system":"today","vendor":"YYYY-MM-05","boot":"YYYY-MM-05"},"osVersion":"","brand":"","device":"","product":"","manufacturer":"","model":"","serial":"","imei":"","meid":"","imei2":"","apps":[]}}}
EOF
    chmod 644 "$BASE/config.json"
}

# ---- 将包列表写入 config.json 的 profiles.default.apps -------------------
# 不依赖 jq：读入整份 JSON 后整体替换 "apps" 数组，其它字段原样保留。
set_config_apps() {
    local list="$1" json="$BASE/config.json" apps tmp="$BASE/config.json.tmp"
    apps="$(awk '{ printf "%s\"%s\"", (NR > 1 ? "," : ""), $0 }' "$list")"
    if awk -v apps="$apps" '
        { buf = buf $0 }
        END {
            s = buf
            p = index(s, "\"apps\"")
            if (!p) exit 1
            st = p + index(substr(s, p), "[") - 1   # "apps" 数组的 "["
            d = 0; en = 0
            for (i = st; i <= length(s); i++) {
                x = substr(s, i, 1)
                if (x == "[") d++
                if (x == "]") { d--; if (d == 0) { en = i; break } }
            }
            if (!en) exit 1
            printf "%s\"apps\":[%s]%s", substr(s, 1, p - 1), apps, substr(s, en + 1)
        }
    ' "$json" > "$tmp" 2>/dev/null && [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$json" && chmod 644 "$json"
}

# ---- 一次同步 -------------------------------------------------------------
# $1 传 "force" 时忽略指纹缓存强制写入（手动同步）。返回 0=成功/跳过，1=失败。
sync_once() {
    local force="$1" list fp merged count r
    list="$(third_party)"
    fp="$(printf '%s' "$list" | md5sum | cut -d' ' -f1)"
    if [ -z "$force" ] && [ "$fp" = "$(cat "$CACHE" 2>/dev/null)" ]; then
        info "包列表未变化，跳过"
        return 0
    fi

    merged="$RUNDIR/merged.tmp"
    build_list "$merged" "$list"
    if [ ! -s "$merged" ]; then
        rm -f "$merged"
        warn "合并结果为空，未写入"
        return 1
    fi
    count=$(wc -l < "$merged" | tr -d ' ')
    case "$TARGET" in
        TS)     cp -f "$merged" "$BASE/target.txt" 2>/dev/null && chmod 644 "$BASE/target.txt" 2>/dev/null; r=$? ;;
        TEESIM) ensure_json && set_config_apps "$merged"; r=$? ;;
        *)      r=1 ;;
    esac
    rm -f "$merged"
    if [ $r -eq 0 ]; then
        echo "$fp" > "$CACHE" 2>/dev/null   # 仅写入成功后更新指纹
        log "已同步 $count 个包 → $TARGET"
        ok "已同步 $count 个包"
        return 0
    fi
    err "写入失败（$TARGET）"
    return 1
}

# ---- 探测 inotify 工具（设置 INOTIFY_CMD / INOTIFY_MODE）-----------------
find_inotify() {
    if command -v inotifywait >/dev/null 2>&1; then INOTIFY_CMD=inotifywait; INOTIFY_MODE=wait; return 0; fi
    if command -v inotifyd    >/dev/null 2>&1; then INOTIFY_CMD=inotifyd;    INOTIFY_MODE=d;    return 0; fi
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox; do
        [ -x "$bb" ] || continue
        "$bb" --list 2>/dev/null | grep -qx inotifywait && { INOTIFY_CMD="$bb inotifywait"; INOTIFY_MODE=wait; return 0; }
        "$bb" --list 2>/dev/null | grep -qx inotifyd    && { INOTIFY_CMD="$bb inotifyd";    INOTIFY_MODE=d;    return 0; }
    done
    return 1
}

# ---- 防抖：短时间内的多次事件合并为一次 ----------------------------------
debounce_ok() {
    local now last
    now=$(date +%s)
    if [ -f "$DEBOUNCE_FILE" ]; then
        last=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
        [ $((now - last)) -lt "$DEBOUNCE_SEC" ] && return 1
    fi
    echo "$now" > "$DEBOUNCE_FILE"
    return 0
}

# ---- 降级轮询（无 inotify 或 mkfifo 失败时）-------------------------------
poll_loop() {
    log "降级为 ${POLL_INTERVAL}s 轮询"
    while [ -f "$PID_FILE" ]; do
        sleep "$POLL_INTERVAL"
        lock && { sync_once; unlock; }
    done
}

# ---- 守护进程 -------------------------------------------------------------
run_daemon() {
    mkdir -p "$RUNDIR"
    echo $$ > "$PID_FILE"
    log "守护进程启动 pid=$$（目标=$TARGET）"

    sleep 3                       # 等待系统稳定
    lock && { sync_once; unlock; }

    find_inotify || { poll_loop; return 0; }

    fifo="$RUNDIR/events.fifo"
    rm -f "$fifo"
    mkfifo "$fifo" 2>/dev/null || { poll_loop; return 0; }

    # watcher 输出经命名管道进入处理循环；停止时经 trap 一并清理。
    if [ "$INOTIFY_MODE" = wait ]; then
        $INOTIFY_CMD -m -e create,delete,moved_to,moved_from /data/app > "$fifo" 2>/dev/null &
    else
        $INOTIFY_CMD - /data/app:cd > "$fifo" 2>/dev/null &
    fi
    watcher=$!
    echo "$watcher" > "$RUNDIR/watcher.pid"
    trap 'kill "$watcher" 2>/dev/null; rm -f "$PID_FILE" "$RUNDIR/watcher.pid" "$fifo"; exit 0' INT TERM
    log "监听 /data/app（inotify:${INOTIFY_MODE}）"

    while IFS= read -r _; do
        [ -f "$PID_FILE" ] || break
        debounce_ok && lock && { sync_once; unlock; }
    done < "$fifo"

    rm -f "$fifo" "$RUNDIR/watcher.pid" "$PID_FILE"
}

# ============================================================================
# 入口
# ============================================================================
[ "$(id -u)" -ne 0 ] && { err "需要 root 权限"; exit 1; }

detect_target
case $? in
    0) info "目标: TrickyStore" ;;
    1) info "目标: TeeSimulator" ;;
    2) err "同时检测到 TrickyStore 与 TeeSimulator，请卸载其一"; exit 1 ;;
    3) warn "未检测到目标模块" ;;
esac

case "$1" in
    --daemon)
        [ -n "$TARGET" ] || { err "未检测到目标模块"; exit 1; }
        run_daemon; exit 0 ;;
    --status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            ok "守护进程运行中 pid=$(cat "$PID_FILE")"
        else
            [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
            warn "守护进程未运行"
        fi
        exit 0 ;;
    --log)
        [ -f "$LOG_FILE" ] && tail -n 30 "$LOG_FILE" || warn "日志不存在"
        exit 0 ;;
    --stop)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null && ok "已停止守护进程"
            rm -f "$PID_FILE"
        else
            warn "守护进程未运行"
        fi
        exit 0 ;;
    --help|-h)
        cat <<'EOF'
用法: ts-sync [选项]
  无参数       手动同步一次（忽略缓存，强制写入）
  --daemon     启动守护进程（inotify 实时监听，无则降级轮询）
  --status     查看守护进程状态
  --log        查看最近日志
  --stop       停止守护进程
  --help       显示帮助

规则文件: rules.txt
  + 包名   始终包含
  - 包名   始终排除
  无前缀   等同包含（+）

提示: 编辑 rules.txt 后执行一次 ts-sync 即可立即生效。
EOF
        exit 0 ;;
esac

# 默认：手动同步一次
[ -n "$TARGET" ] || { err "未检测到目标模块，无法同步"; exit 1; }
lock || { err "获取锁失败"; exit 1; }
sync_once force
unlock
