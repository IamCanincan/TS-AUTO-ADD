#!/system/bin/sh
# 模块ID: ts-auto-add
# 职责: 负责后台异步执行 target.txt 与 security_patch.txt 的数据校对与更新工作

MODDIR="/data/adb/modules/ts-auto-add"
PROP_FILE="$MODDIR/module.prop"
BASE="/data/adb/tricky_store"
TARGET="$BASE/target.txt"
WATCH_FILE="/data/system/packages.list"
TMP="${BASE}/.ts_tmp"
PENDING="${BASE}/.ts_pending"
LOCK_DIR="${BASE}/.ts_lock"
PID_FILE="${BASE}/.ts_daemon.pid"

PATCH_CONFIG_FILE="$BASE/security_patch.txt"
PATCH_BACKUP_FILE="$BASE/security_patch.txt.bak"
PATCH_CACHE_FILE="$BASE/.last_month"

acquire_lock() { mkdir "$LOCK_DIR" 2>/dev/null; }
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null; }

update_module_status() {
    [ -f "$PROP_FILE" ] || return 0
    
    local app_count=0
    if [ -f "$TARGET" ]; then
        app_count=$(wc -l < "$TARGET")
    fi
    
    local patch_date="未配置"
    if [ -f "$PATCH_CONFIG_FILE" ]; then
        patch_date=$(grep '^boot=' "$PATCH_CONFIG_FILE" | cut -d'=' -f2)
        [ -z "$patch_date" ] && patch_date="未知"
    fi
    
    # 仅保留模块运行状态，移除冗长描述
    local status_text="[应用数: ${app_count} | 补丁: ${patch_date} | 更新: $(date '+%H:%M')]"
    
    local tmp_prop="${PROP_FILE}.tmp"
    rm -f "$tmp_prop"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            description=*)
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

do_sync() {
    mkdir -p "$BASE"
    {
        printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n"
        pm list packages -3 2>/dev/null | sed -n 's/^package://p'
    } | sort -u > "$TMP"

    if [ -s "$TMP" ]; then
        if ! cmp -s "$TMP" "$TARGET"; then
            mv -f "$TMP" "$TARGET"
            chmod 644 "$TARGET"
            logger -t TrickyStore "target.txt updated"
        else
            rm -f "$TMP"
        fi
    else
        rm -f "$TMP"
        logger -t TrickyStore "sync failed: empty list"
    fi
    update_module_status
}

dispatch_sync() {
    touch "$PENDING"
    acquire_lock || exit 0
    while [ -f "$PENDING" ]; do
        rm -f "$PENDING"
        sleep 3
    done
    do_sync
    release_lock
}

clean_date() {
    echo "$1" | grep -oE '20[2-9][0-9]-[0-9]{2}-[0-9]{2}' | head -n 1
}

get_system_date() {
    clean_date "$(getprop ro.build.version.security_patch)"
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

update_security_patch() {
    mkdir -p "$BASE"
    local SYSTEM_DATE=$(force_to_05 "$(get_system_date)")
    if [ -z "$SYSTEM_DATE" ]; then
        logger -t TrickyStore "Error: System patch date is empty."
        return 1
    fi

    local SYS_YEAR=$(echo "$SYSTEM_DATE" | cut -d'-' -f1)
    local SYS_MONTH=$(echo "$SYSTEM_DATE" | cut -d'-' -f2)
    local SYS_YM="${SYS_YEAR}-${SYS_MONTH}"

    local NEED_ONLINE=0
    if [ -f "$PATCH_CACHE_FILE" ]; then
        local CACHED_MONTH=$(cat "$PATCH_CACHE_FILE")
        if [ "$CACHED_MONTH" != "$SYS_YM" ]; then
            NEED_ONLINE=1
        fi
    else
        NEED_ONLINE=1
    fi

    local FINAL_DATE="$SYSTEM_DATE"

    if [ "$NEED_ONLINE" -eq 1 ]; then
        local URL1="https://source.android.google.cn/docs/security/bulletin/pixel"
        local NET_DATE=$(fetch_online_date "$URL1")
        if [ -z "$NET_DATE" ]; then
            local URL2="https://source.android.google.cn/docs/security/bulletin"
            NET_DATE=$(fetch_online_date "$URL2")
        fi

        if [ -n "$NET_DATE" ]; then
            local NEWER=$(pick_newer "$SYSTEM_DATE" "$NET_DATE")
            if [ "$NEWER" = "$NET_DATE" ] && [ "$NET_DATE" != "$SYSTEM_DATE" ]; then
                FINAL_DATE="$NET_DATE"
            else
                FINAL_DATE="$SYSTEM_DATE"
            fi
            echo "$SYS_YM" > "$PATCH_CACHE_FILE"
        else
            FINAL_DATE="$SYSTEM_DATE"
        fi
    else
        FINAL_DATE="$SYSTEM_DATE"
    fi

    if [ -f "$PATCH_CONFIG_FILE" ]; then
        cp -f "$PATCH_CONFIG_FILE" "$PATCH_BACKUP_FILE"
    fi

    cat << EOF > "$PATCH_CONFIG_FILE"
system=prop
boot=$FINAL_DATE
vendor=$FINAL_DATE
EOF

    chmod 644 "$PATCH_CONFIG_FILE"
    chown root:root "$PATCH_CONFIG_FILE" 2>/dev/null
    logger -t TrickyStore "Security patch updated: $FINAL_DATE"
    update_module_status
}

case "$1" in
    "")
        ;;
    "--sync")
        dispatch_sync
        exit 0
        ;;
    *)
        dispatch_sync
        exit 0
        ;;
esac

if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE")"
    kill "$old_pid" 2>/dev/null
    sleep 0.3
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null
    rm -f "$PID_FILE"
fi
rm -f "$TMP" "$PENDING"
rm -rf "$LOCK_DIR"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

do_sync

(
    update_security_patch
    while true; do
        sleep 43200
        update_security_patch
    done
) &

(
    trap 'release_lock; rm -f "$PENDING" "$PID_FILE"; exit' EXIT INT TERM
    while true; do
        while [ ! -f "$WATCH_FILE" ]; do sleep 2; done
        inotifyd "$0" "$WATCH_FILE:w" >/dev/null 2>&1
        dispatch_sync
        sleep 1
    done
) &

echo $! > "$PID_FILE"
exit 0