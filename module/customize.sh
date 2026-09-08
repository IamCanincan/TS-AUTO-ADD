#!/system/bin/sh
SKIPUNZIP=0

ui_print "================================================"
ui_print "   TS-AUTO-ADD 安装程序"
ui_print "================================================"

RUNDIR="/data/adb/ts_auto"

ui_print " "
ui_print "[1/4] 检查 inotify 支持"
ok=0
if command -v inotifywait >/dev/null 2>&1 || command -v inotifyd >/dev/null 2>&1; then
    ok=1
else
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox; do
        [ -x "$bb" ] && "$bb" --list 2>/dev/null | grep -qx inotifyd && ok=1
    done
fi
[ $ok -eq 0 ] && abort "  未检测到 inotify (inotifywait/inotifyd)，无法实时监听"

ui_print " "
ui_print "[2/4] 初始化运行时目录"
mkdir -p "$RUNDIR" 2>/dev/null
# 迁移旧版白名单（旧版寄生在 /data/adb/tricky_store）
if [ -f /data/adb/tricky_store/taa_sys.txt ] && [ ! -f "$RUNDIR/taa_sys.txt" ]; then
    mv -f /data/adb/tricky_store/taa_sys.txt "$RUNDIR/taa_sys.txt" 2>/dev/null
fi
if [ ! -f "$RUNDIR/taa_sys.txt" ]; then
    printf 'com.android.vending\ncom.google.android.gms\ncom.google.android.gsf\n' > "$RUNDIR/taa_sys.txt" 2>/dev/null
    chmod 640 "$RUNDIR/taa_sys.txt" 2>/dev/null
fi

ui_print " "
ui_print "[3/4] 配置脚本权限"
set_perm_recursive "$MODPATH" 0 0 0755 0644 || true
chmod 0755 "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" 2>/dev/null

ui_print " "
ui_print "[4/4] 生成初始应用列表"
sh "$MODPATH/service.sh" --once 2>/dev/null && ui_print "  初始列表生成完成" || ui_print "  初始列表为空，开机后由守护进程处理"

# 清理旧版寄生在 /data/adb/tricky_store 的运行时文件
rm -rf /data/adb/tricky_store/.ts_tmp /data/adb/tricky_store/.ts_lock /data/adb/tricky_store/.ts_debounce 2>/dev/null
rm -f /data/adb/tricky_store/.ts_daemon.pid /data/adb/tricky_store/.ts_daemon_pids.list /data/adb/tricky_store/.events.fifo 2>/dev/null
rm -f /data/local/tmp/ts_auto.log /data/adb/ts_auto.log /data/adb/service.d/taa_resetprop.sh 2>/dev/null

ui_print "================================================"
ui_print "  安装完成，重启生效"
ui_print "  手动同步: sh /data/adb/modules/ts-auto-add/service.sh --once"
ui_print "  白名单:   $RUNDIR/taa_sys.txt"
ui_print "================================================"
