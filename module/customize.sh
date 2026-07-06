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
ui_print "[1/5] 检查及构建工作空间..."

BASE_DIR="/data/adb/tricky_store"
mkdir -p "$BASE_DIR"
if [ ! -f "$BASE_DIR/target.txt" ]; then
    touch "$BASE_DIR/target.txt"
    chmod 644 "$BASE_DIR/target.txt"
fi
ui_print "  ✓ 工作目录及基础配置文件已就绪"

if ! command -v inotifyd >/dev/null 2>&1; then
    ui_print "  ✗ 未找到 inotifyd 工具，系统不具备事件监听能力！"
    abort "安装终止。"
fi

ui_print " "
ui_print "[2/5] 设置核心脚本权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/action.sh" 2>/dev/null

ui_print " "
ui_print "[3/5] 清理历史残留与死锁句柄..."
rm -rf "$BASE_DIR/.ts_lock" "$BASE_DIR/.ts_pending" "$BASE_DIR/.ts_tmp"
rm -f "$BASE_DIR/.ts_daemon"*.pid "$BASE_DIR/.ts_patch.pid"

ui_print " "
ui_print "[4/5] 部署开机属性伪装服务..."
mkdir -p /data/adb/service.d
if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh"
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh"
    rm -f "$MODPATH/taa_resetprop.sh"
    ui_print "  ✓ 已安全挂载属性注入服务"
fi

ui_print " "
ui_print "[5/5] 执行首次全域基准合流..."
export PATH="/providers/active/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/product/bin:$PATH"
TAA_SYS_FILE="$BASE_DIR/taa_sys.txt"
if [ ! -f "$TAA_SYS_FILE" ]; then
    printf "com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n" > "$TAA_SYS_FILE"
    chmod 644 "$TAA_SYS_FILE"
fi

{
    cat "$TAA_SYS_FILE" 2>/dev/null; echo ""
    
    # 细节修复：同等注入兼容性向下兼容探测
    local apps_raw=""
    if command -v cmd >/dev/null 2>&1; then
        apps_raw=$(cmd package list packages -3 -u --user all 2>/dev/null)
    fi
    if [ -z "$apps_raw" ] && command -v pm >/dev/null 2>&1; then
        apps_raw=$(pm list packages -3 2>/dev/null)
    fi
    echo "$apps_raw" | sed -n 's/^package://p'
} | sort -u | sed '/^$/d' > "$BASE_DIR/.ts_tmp"

if [ -s "$BASE_DIR/.ts_tmp" ]; then
    mv -f "$BASE_DIR/.ts_tmp" "$BASE_DIR/target.txt"
    chmod 644 "$BASE_DIR/target.txt"
    ui_print "  ✓ 基准同步完成，初次录入全域包数: $(wc -l < "$BASE_DIR/target.txt")"
else
    rm -f "$BASE_DIR/.ts_tmp"
    ui_print "  ⚠ 首次抓取为空，将交由开机守护进程接管。"
fi

ui_print " "
ui_print "================================================"
ui_print "   TS-AUTO-ADD 部署完毕，请重启设备激活！"
ui_print "================================================"