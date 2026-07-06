#!/system/bin/sh
SKIPUNZIP=0

#=============================================================================
# 模块安装脚本 (customize.sh)
# 功能: 检查依赖环境、设置文件权限、清理历史文件并初始化系统应用配置文件。
#=============================================================================

ui_print "================================================="
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================="

#-----------------------------------------------------------------------------
# 步骤 1: 环境依赖检查
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[1/6] 检查依赖..."

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

#-----------------------------------------------------------------------------
# 步骤 2: 配置文件权限
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[2/6] 配置文件权限..."

chmod 0755 "$MODPATH/service.sh"
ui_print "  ✓ service.sh 权限设为 0755"

if [ -f "$MODPATH/action.sh" ]; then
    chmod 0755 "$MODPATH/action.sh"
    ui_print "  ✓ action.sh 权限设为 0755"
fi

chmod 0644 "$MODPATH/module.prop"
ui_print "  ✓ module.prop 权限设为 0644"

#-----------------------------------------------------------------------------
# 步骤 3: 准备运行环境与清理残留
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[3/6] 准备运行环境..."

mkdir -p /data/adb/tricky_store
ui_print "  ✓ 工作目录 /data/adb/tricky_store 已就绪"

rm -rf /data/adb/tricky_store/.ts_lock /data/adb/tricky_store/.ts_pending
rm -f /data/adb/tricky_store/.ts_daemon.pid /data/adb/tricky_store/.ts_patch.pid
rm -f /data/adb/tricky_store/.ts_tmp
ui_print "  ✓ 已清理残留临时文件"

#-----------------------------------------------------------------------------
# 步骤 4: 建立自定义系统应用配置文件
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[4/6] 配置自定义系统应用列表..."
TAA_SYS_FILE="/data/adb/tricky_store/taa_sys.txt"

if [ ! -f "$TAA_SYS_FILE" ]; then
    cat << EOF > "$TAA_SYS_FILE"
com.android.vending
com.google.android.gms
com.google.android.gsf
EOF
    chmod 0644 "$TAA_SYS_FILE"
    ui_print "  ✓ 已创建默认配置 taa_sys.txt"
else
    ui_print "  ✓ 发现已有 taa_sys.txt，保留用户自定义配置"
fi

#-----------------------------------------------------------------------------
# 步骤 5: 部署系统属性重置脚本
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[5/6] 部署 taa_resetprop.sh 脚本..."

mkdir -p /data/adb/service.d

if [ -f "$MODPATH/taa_resetprop.sh" ]; then
    cp -f "$MODPATH/taa_resetprop.sh" "/data/adb/service.d/taa_resetprop.sh"
    chmod 0755 "/data/adb/service.d/taa_resetprop.sh"
    ui_print "  ✓ 已将 taa_resetprop.sh 写入 /data/adb/service.d 并赋予 0755 权限"
    rm -f "$MODPATH/taa_resetprop.sh"
else
    ui_print "  ⚠ 未找到 taa_resetprop.sh，跳过部署"
fi

#-----------------------------------------------------------------------------
# 步骤 6: 执行安装时的首次全量同步
#-----------------------------------------------------------------------------
ui_print " "
ui_print "[6/6] 执行首次应用同步..."

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

#-----------------------------------------------------------------------------
# 卸载或清理安装残留
#-----------------------------------------------------------------------------
rm -f "$MODPATH/customize.sh"

ui_print " "
ui_print "================================================="
ui_print "  TS-AUTO-ADD 安装完成"
ui_print "  重启设备以激活后台守护服务。"
ui_print "================================================="
exit 0