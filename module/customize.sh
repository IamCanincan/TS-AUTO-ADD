#!/system/bin/sh
SKIPUNZIP=0

#====================================================
# TS-AUTO-ADD 安装脚本
#====================================================

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================"

ui_print " "
ui_print "[1/6] 检查并创建工作目录"

BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR"
if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt"
    chmod 644 "$BASE_DIR/target.txt"
fi
ui_print "  工作目录已就绪"

if ! command -v inotifyd >/dev/null 2>&1; then
    ui_print "  未找到 inotifyd 命令，系统不支持文件事件监听"
    abort "安装终止，请确认内核已启用 inotify 或安装 busybox 包含 inotifyd。"
fi
ui_print "  inotifyd 工具已存在"

ui_print " "
ui_print "[2/6] 设置核心脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[3/6] 清理历史残留文件"
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_pending" "$BASE_DIR/.ts_tmp"
rm -f "$BASE_DIR/.ts_daemon"*.pid "$BASE_DIR/.ts_patch.pid"

ui_print " "
ui_print "[4/6] 部署属性注入服务"
mkdir -p /data/adb/service.d
if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh"
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh"
    rm -f "$MODPATH/taa_resetprop.sh"
    ui_print "  已部署"
fi

ui_print " "
ui_print "[5/6] 执行首次应用列表同步"

# 配置文件路径改为模块目录下的 taa_sys.txt
TAA_SYS_FILE="$BASE_DIR/taa_sys.txt"
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
    chmod 640 "$TAA_SYS_FILE"
    chown root:root "$TAA_SYS_FILE" 2>/dev/null
    # 设置 SELinux 上下文以确保 inotifyd 可访问
    chcon system_data_file "$TAA_SYS_FILE" 2>/dev/null || \
    chcon u:object_r:adb_data_file:s0 "$TAA_SYS_FILE" 2>/dev/null || true
fi

apps_raw=""
if command -v cmd >/dev/null 2>&1; then
    apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
fi
if [ -z "$apps_raw" ] && command -v pm >/dev/null 2>&1; then
    apps_raw=$(pm list packages -3 2>/dev/null)
fi

{
    cat "$TAA_SYS_FILE" 2>/dev/null
    echo ""
    echo "$apps_raw" | sed -n 's/^package://p'
} | sort -u | sed '/^$/d' > "$BASE_DIR/.ts_tmp"

if [ -s "$BASE_DIR/.ts_tmp" ]; then
    mv -f "$BASE_DIR/.ts_tmp" "$BASE_DIR/target.txt"
    chmod 644 "$BASE_DIR/target.txt"
    count=$(wc -l < "$BASE_DIR/target.txt")
    ui_print "  同步完成，记录包数: $count"
else
    rm -f "$BASE_DIR/.ts_tmp"
    ui_print "  获取为空，由守护进程后续处理"
fi

ui_print " "
ui_print "[6/6] 更新模块描述信息"
sed -i "s/^description=.*/description=[应用数: $(wc -l < "$BASE_DIR/target.txt" 2>/dev/null || echo 0) | 补丁: 待同步]/" "$MODPATH/module.prop" 2>/dev/null

ui_print " "
ui_print "================================================"
ui_print "   TS-AUTO-ADD 部署完成，请重启设备"
ui_print "================================================"