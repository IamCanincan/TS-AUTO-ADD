#!/system/bin/sh
SKIPUNZIP=0

#====================================================
# TS-AUTO-ADD 模块安装脚本
# 功能：检查依赖、设置权限、清理残留、执行首次同步、
#       部署辅助脚本（taa_resetprop.sh）。
#====================================================

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================"

# ---- 1. 依赖检查 ----
ui_print " "
ui_print "[1/5] 检查依赖..."

if [ ! -f "/data/adb/tricky_store/target.txt" ]; then
    ui_print "  ✗ 未找到 /data/adb/tricky_store/target.txt"
    ui_print "    请确保已安装并启用 Tricky Store 模块。"
    abort "安装终止。"
fi
ui_print "  ✓ Tricky Store 配置文件已就绪"

if ! command -v inotifyd >/dev/null 2>&1; then
    ui_print "  ✗ 未找到 inotifyd 命令"
    ui_print "    当前系统可能裁剪了 inotify 工具。"
    abort "安装终止。"
fi
ui_print "  ✓ inotifyd 可用"

if ! command -v pm >/dev/null 2>&1; then
    ui_print "  ⚠ pm 命令不可用，首次应用列表获取可能失败。"
    ui_print "    守护服务将在开机后自动重试同步。"
else
    ui_print "  ✓ pm 命令可用"
fi

# ---- 2. 设置模块文件权限 ----
ui_print " "
ui_print "[2/5] 配置文件权限..."

chmod 0755 "$MODPATH/service.sh"
ui_print "  ✓ service.sh 权限设为 0755"

if [ -f "$MODPATH/action.sh" ]; then
    chmod 0755 "$MODPATH/action.sh"
    ui_print "  ✓ action.sh 权限设为 0755"
fi

chmod 0644 "$MODPATH/module.prop"
ui_print "  ✓ module.prop 权限设为 0644"

# ---- 3. 工作目录与残留清理 ----
ui_print " "
ui_print "[3/5] 准备运行环境..."

mkdir -p /data/adb/tricky_store
ui_print "  ✓ 工作目录 /data/adb/tricky_store 已就绪"

# 清理可能遗留的锁文件、PID 文件及临时文件
rm -rf /data/adb/tricky_store/.ts_lock /data/adb/tricky_store/.ts_pending
rm -f /data/adb/tricky_store/.ts_daemon.pid /data/adb/tricky_store/.ts_patch.pid
rm -f /data/adb/tricky_store/.ts_tmp
ui_print "  ✓ 已清理残留临时文件"

# ---- 4. 部署 taa_resetprop.sh 到 service.d ----
ui_print " "
ui_print "[4/5] 部署 taa_resetprop.sh 脚本..."

mkdir -p /data/adb/service.d

if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh"
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh"
    ui_print "  ✓ 已将 taa_resetprop.sh 写入 /data/adb/service.d 并赋予 0755 权限"
    rm -f "$MODPATH/taa_resetprop.sh"
else
    ui_print "  ⚠ 未找到 taa_resetprop.sh，跳过部署"
fi

# ---- 5. 首次全量同步 ----
ui_print " "
ui_print "[5/5] 执行首次应用同步..."

if "$MODPATH/service.sh" --sync; then
    ui_print "  ✓ 首次同步成功"
    if [ -s /data/adb/tricky_store/target.txt ]; then
        app_count=$(wc -l < /data/adb/tricky_store/target.txt)
        ui_print "    已写入 ${app_count} 个应用包名"
    fi
else
    ui_print "  ⚠ 首次同步未能完成"
    ui_print "    守护服务将在开机后自动重试，无需手动干预。"
fi

# ---- 6. 清理自身 ----
rm -f "$MODPATH/customize.sh"

ui_print " "
ui_print "================================================"
ui_print "  TS-AUTO-ADD 安装完成"
ui_print "  重启设备以激活后台守护服务。"
ui_print "================================================"
exit 0