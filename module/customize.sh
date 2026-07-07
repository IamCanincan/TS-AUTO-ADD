#!/system/bin/sh
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================"

ui_print " "
ui_print "[1/6] 检查并创建工作目录"
BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR" 2>/dev/null || abort "  无法创建目录 $BASE_DIR"

if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
fi
ui_print "  工作目录已就绪"

# 查找具有高兼容性的 inotifyd
INOTIFY_CMD=""
for cmd in "/data/adb/magisk/busybox inotifyd" "/data/adb/ksu/bin/busybox inotifyd" "inotifyd" "/system/bin/inotifyd"; do
    if $cmd --help 2>&1 | grep -q 'inotifyd' || command -v ${cmd%% *} >/dev/null 2>&1; then
        INOTIFY_CMD="$cmd"
        break
    fi
done

if [ -z "$INOTIFY_CMD" ]; then
    abort "  未找到 inotifyd 命令，系统不支持文件事件监听"
fi
ui_print "  检测到可用监听器: ${INOTIFY_CMD%% *}"

ui_print " "
ui_print "[2/6] 设置核心脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[3/6] 清理历史残留"
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_debounce" "$BASE_DIR/.ts_tmp" "$BASE_DIR"/.ts_daemon*.pid 2>/dev/null

ui_print " "
ui_print "[4/6] 部署属性注入服务"
mkdir -p /data/adb/service.d 2>/dev/null
if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh" 2>/dev/null
    rm -f "$MODPATH/taa_resetprop.sh" 2>/dev/null
    ui_print "  已部署"
fi

ui_print " "
ui_print "[5/6] 执行初始应用列表同步"
TAA_SYS_FILE="$BASE_DIR/taa_sys.txt"
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE" 2>/dev/null
    chmod 640 "$TAA_SYS_FILE" 2>/dev/null
    chown root:root "$TAA_SYS_FILE" 2>/dev/null
fi

apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null || pm list packages -3 2>/dev/null)
{
    cat "$TAA_SYS_FILE" 2>/dev/null
    echo ""
    echo "$apps_raw" | sed -n 's/^package://p'
} | sort -u | sed '/^$/d' > "$BASE_DIR/.ts_tmp" 2>/dev/null

if [ -s "$BASE_DIR/.ts_tmp" ]; then
    mv -f "$BASE_DIR/.ts_tmp" "$BASE_DIR/target.txt" 2>/dev/null
    chmod 644 "$BASE_DIR/target.txt" 2>/dev/null
    ui_print "  同步完成，记录包数: $(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0)"
else
    rm -f "$BASE_DIR/.ts_tmp" 2>/dev/null
    ui_print "  获取为空，由守护进程后续处理"
fi

ui_print " "
ui_print "[6/6] 更新模块描述"
count=$(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0)
sed -i "s/^description=.*/description=[应用数: ${count} | 补丁: 待同步]/" "$MODPATH/module.prop" 2>/dev/null || true

ui_print "================================================"
ui_print "   TS-AUTO-ADD 部署完成，请重启设备"
ui_print "================================================"