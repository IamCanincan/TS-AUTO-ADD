#!/system/bin/sh
SKIPUNZIP=0
MODPATH="${0%/*}"

chmod 755 "$MODPATH/action.sh" "$MODPATH/service.sh" 2>/dev/null
chmod 644 "$MODPATH/rules.txt" "$MODPATH/module.prop" 2>/dev/null

ui_print "========================================"
ui_print "  TS-AUTO-ADD 安装完成"
ui_print "  手动同步: /data/adb/ts-sync"
ui_print "  规则文件: $MODPATH/rules.txt"
ui_print "========================================"
exit 0