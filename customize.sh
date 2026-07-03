#!/system/bin/sh
SKIPUNZIP=0

#====================================================
# TS-AUTO-ADD 模块安装脚本
# 功能：安装前检查、首次同步、权限设置
#====================================================

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "   Tricky Store 自动同步守护模块"
ui_print "================================================"

# ---- 1. 依赖检查 ----
ui_print " "
ui_print "[1/4] 检查依赖..."

# Tricky Store 配置必须存在
if [ ! -f "/data/adb/tricky_store/target.txt" ]; then
    ui_print "  ✗ 未找到 /data/adb/tricky_store/target.txt"
    ui_print "    请确保已安装并启用 Tricky Store 模块。"
    abort "安装终止。"
fi
ui_print "  ✓ Tricky Store 配置文件已就绪"

# inotifyd 是核心监听工具，必须可用
if ! command -v inotifyd >/dev/null 2>&1; then
    ui_print "  ✗ 未找到 inotifyd 命令"
    ui_print "    当前系统可能裁剪了 inotify 工具。"
    abort "安装终止。"
fi
ui_print "  ✓ inotifyd 可用"

# pm 用于列出第三方应用，仅警告
if ! command -v pm >/dev/null 2>&1; then
    ui_print "  ⚠ pm 命令不可用，首次应用列表获取可能失败。"
    ui_print "    守护服务将在开机后自动重试同步。"
else
    ui_print "  ✓ pm 命令可用"
fi

# ---- 2. 设置模块文件权限 ----
ui_print " "
ui_print "[2/4] 配置文件权限..."

# service.sh 需要可执行权限 (0755)，供 Magisk/KernelSU 开机启动以及 inotifyd 回调
chmod 0755 "$MODPATH/service.sh"
ui_print "  ✓ service.sh 权限设为 0755"

# module.prop 应为普通可读 (0644)
chmod 0644 "$MODPATH/module.prop"
ui_print "  ✓ module.prop 权限设为 0644"

# ---- 3. 工作目录与残留清理 ----
ui_print " "
ui_print "[3/4] 准备运行环境..."

# 确保目标目录存在
mkdir -p /data/adb/tricky_store
ui_print "  ✓ 工作目录 /data/adb/tricky_store 已就绪"

# 移除可能残留的旧锁文件及 PID，避免服务无法启动
rm -rf /data/adb/tricky_store/.ts_lock /data/adb/tricky_store/.ts_pending
rm -f /data/adb/tricky_store/.ts_daemon.pid /data/adb/tricky_store/.ts_tmp
ui_print "  ✓ 已清理残留临时文件"

# ---- 4. 首次全量同步 ----
ui_print " "
ui_print "[4/4] 执行首次应用同步..."

# 调用 service.sh 的同步分支 (参数 --sync)，复用防抖与写入逻辑
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

# ---- 5. 清理自身 ----
# 模块目录只保留 module.prop 和 service.sh，删除 customize.sh
rm -f "$MODPATH/customize.sh"

ui_print " "
ui_print "================================================"
ui_print "  TS-AUTO-ADD 安装完成"
ui_print "  重启设备以激活后台守护服务。"
ui_print "================================================"
exit 0
