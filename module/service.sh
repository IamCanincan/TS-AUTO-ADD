#!/system/bin/sh
#=============================================================================
# TS-AUTO-ADD 核心脚本（单文件）
#   合并白名单 taa_sys.txt 与第三方应用，写入 TrickyStore 的 target.txt 和
#   TeeSimulator 的 config.json。守护进程用 inotify 实时监听。
#
#   用法: sh service.sh [--once|--daemon|--help]
#     无参数   开机入口：首次同步后后台启动守护并退出
#     --once   手动同步一次
#     --daemon 守护循环（由开机入口后台调用，勿手动使用）
#=============================================================================

export PATH="/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"

MODDIR="${0%/*}"
[ "$MODDIR" = "$0" ] && MODDIR="."

# 模块自身运行时目录（不寄生在 TrickyStore/TeeSimulator 目录）
RUNDIR="/data/adb/ts_auto"
TAA_SYS_FILE="$RUNDIR/taa_sys.txt"
LOG_FILE="$RUNDIR/ts_auto.log"
TMP="$RUNDIR/.ts_tmp"
LOCK_DIR="$RUNDIR/.ts_lock"
DEBOUNCE_LOCK="$RUNDIR/.ts_debounce"
PID_FILE="$RUNDIR/.ts_daemon.pid"

# 输出目标（仅这两个文件写入目标模块目录）
TS_TARGET="/data/adb/tricky_store/target.txt"
TEESIM_DIR="/data/adb/teesim"

# 确保运行时目录存在（必须在写 PID / 日志 / 加锁之前）
mkdir -p "$RUNDIR" 2>/dev/null

DEBOUNCE_SEC=2

# ---------- 日志 ----------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null; }

# ---------- 文件锁（mkdir 原子性 + 陈旧锁回收）----------
lock() {
    local i=0
    while [ $i -lt 15 ]; do
        mkdir "$LOCK_DIR" 2>/dev/null && { echo $$ > "$LOCK_DIR/pid"; return 0; }
        [ -f "$LOCK_DIR/pid" ] && ! kill -0 "$(cat "$LOCK_DIR/pid")" 2>/dev/null && rmdir "$LOCK_DIR" 2>/dev/null
        sleep 1; i=$((i+1))
    done
    return 1
}
unlock() { rmdir "$LOCK_DIR" 2>/dev/null; }

# ---------- 白名单（不存在则用 Google 三件套初始化）----------
ensure_taa_sys() {
    mkdir -p "$RUNDIR" 2>/dev/null
    [ -f "$TAA_SYS_FILE" ] && return 0
    printf 'com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n' > "$TAA_SYS_FILE" 2>/dev/null
    chmod 640 "$TAA_SYS_FILE" 2>/dev/null
}

# ---------- 采集合并（白名单 + 第三方应用，去重）----------
collect_app_list() {
    local apps_raw user_list
    ensure_taa_sys
    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
    user_list=$(echo "$apps_raw" | sed -n 's/^package://p')
    APP_USER_COUNT=$(echo "$user_list" | sed '/^$/d' | wc -l | tr -d ' ')
    APP_SYS_COUNT=$(sed '/^$/d' "$TAA_SYS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    (cat "$TAA_SYS_FILE" 2>/dev/null; echo "$user_list") | sort -u | sed '/^$/d'
}

# ---------- TeeSimulator config.json ----------
teesim_present() { [ -d "$TEESIM_DIR" ] || [ -d /data/adb/modules/teesim ]; }

ensure_teesim_config() {
    [ -f "$TEESIM_DIR/config.json" ] && grep -q '"profiles"' "$TEESIM_DIR/config.json" 2>/dev/null && return 0
    mkdir -p "$TEESIM_DIR" 2>/dev/null
    cat > "$TEESIM_DIR/config.json" <<'EOF'
{"version":1,"profiles":{"default":{"keybox":"keybox.xml","mode":"patch","patchLevel":{"system":"today","vendor":"YYYY-MM-05","boot":"YYYY-MM-05"},"osVersion":"","brand":"","device":"","product":"","manufacturer":"","model":"","serial":"","imei":"","meid":"","imei2":"","apps":[]}}}
EOF
    chmod 644 "$TEESIM_DIR/config.json" 2>/dev/null
}

# 将包列表写入 config.json 的 profiles.default.apps（不依赖 jq）
set_teesim_apps() {
    local list="$1" json="$TEESIM_DIR/config.json" apps tmp="$TEESIM_DIR/config.json.tmp"
    [ -f "$list" ] || return 1
    ensure_teesim_config || return 1
    apps="$(awk '{ printf "%s\"%s\"", (NR > 1 ? "," : ""), $0 }' "$list")"
    if awk -v apps="$apps" '
        { buf = buf $0 }
        END {
            s = buf
            p = index(s, "\"apps\"")
            if (!p) exit 1
            st = p + index(substr(s, p), "[") - 1
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
    mv -f "$tmp" "$json" 2>/dev/null && chmod 644 "$json" 2>/dev/null
}

# ---------- 同步一次 ----------
sync_once() {
    collect_app_list > "$TMP" 2>/dev/null
    [ -s "$TMP" ] || { rm -f "$TMP" 2>/dev/null; log "合并结果为空"; return 1; }
    if teesim_present; then
        set_teesim_apps "$TMP" && log "TeeSimulator config.json 已同步" || log "TeeSimulator config.json 同步失败"
    fi
    if ! cmp -s "$TMP" "$TS_TARGET" 2>/dev/null; then
        mv -f "$TMP" "$TS_TARGET" 2>/dev/null
        chmod 644 "$TS_TARGET" 2>/dev/null
        log "target.txt 已同步（系统 $APP_SYS_COUNT / 用户 $APP_USER_COUNT）"
        return 0
    fi
    rm -f "$TMP" 2>/dev/null
    log "应用列表无变化"
    return 0
}

# ---------- inotify 工具探测 ----------
find_inotify() {
    if command -v inotifywait >/dev/null 2>&1; then INOTIFY_CMD=inotifywait; INOTIFY_MODE=wait; return 0; fi
    if command -v inotifyd    >/dev/null 2>&1; then INOTIFY_CMD=inotifyd;    INOTIFY_MODE=d;    return 0; fi
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox; do
        [ -x "$bb" ] || continue
        "$bb" --list 2>/dev/null | grep -qx inotifyd && { INOTIFY_CMD="$bb inotifyd"; INOTIFY_MODE=d; return 0; }
    done
    return 1
}

# ---------- 防抖调度（2 秒合并突发事件）----------
dispatch_sync() {
    if mkdir "$DEBOUNCE_LOCK" 2>/dev/null; then
        (
            sleep "$DEBOUNCE_SEC"
            rmdir "$DEBOUNCE_LOCK" 2>/dev/null
            lock && { sync_once; unlock; }
        ) &
    fi
}

# ---------- 守护循环（后台运行）----------
daemon_loop() {
    echo $$ > "$PID_FILE"
    log "守护进程启动 pid=$$"

    find_inotify || { log "未找到 inotify，退出"; exit 1; }
    log "开始实时监听（$INOTIFY_MODE）"

    # 监听两个目录 + 白名单文件：
    #   /data/system    → packages.list（安装/卸载）
    #   $RUNDIR         → taa_sys.txt 原子替换
    #   $TAA_SYS_FILE   → taa_sys.txt 原地修改（如 echo 追加）
    while true; do
        if [ "$INOTIFY_MODE" = "wait" ]; then
            $INOTIFY_CMD -m -e modify -e create -e delete -e move /data/system "$RUNDIR" "$TAA_SYS_FILE" 2>/dev/null | while read -r line; do
                case "$line" in *packages.list*|*taa_sys.txt*) dispatch_sync ;; esac
            done
        else
            $INOTIFY_CMD - /data/system:wc "$RUNDIR:wc" "$TAA_SYS_FILE:wc" 2>/dev/null | while read -r line; do
                case "$line" in *packages.list*|*taa_sys.txt*) dispatch_sync ;; esac
            done
        fi
        sleep 2
    done
}

# ---------- 入口 ----------
[ "$(id -u)" -ne 0 ] && { echo "需要 root 权限" >&2; exit 1; }

case "$1" in
    --once)
        lock || { echo "获取锁失败" >&2; exit 1; }
        sync_once && echo "同步完成（系统 $APP_SYS_COUNT / 用户 $APP_USER_COUNT）" || echo "同步失败"
        unlock
        ;;
    --daemon)
        daemon_loop
        ;;
    --help|-h)
        cat <<'EOF'
用法: sh service.sh [选项]
  无参数   开机入口：首次同步 + 后台守护
  --once   手动同步一次
  --daemon 守护循环（后台）
  --help   显示帮助
EOF
        ;;
    *)
        # 开机入口：等待就绪 → 首次同步 → 后台守护 → 退出（快速退出，不阻塞开机）
        until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 2; done
        lock && { sync_once; unlock; }
        nohup sh "$MODDIR/service.sh" --daemon >/dev/null 2>&1 &
        ;;
esac
