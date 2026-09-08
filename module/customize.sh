#!/system/bin/sh
SKIPUNZIP=0
MODPATH="${0%/*}"

chmod 755 "$MODPATH/action.sh" "$MODPATH/service.sh" 2>/dev/null
chmod 644 "$MODPATH/rules.txt" "$MODPATH/module.prop" 2>/dev/null

# 创建手动同步命令包装器（模块 id 固定为 ts-auto-add）
cat > /data/adb/ts-sync <<'EOF'
#!/system/bin/sh
MODDIR="/data/adb/modules/ts-auto-add"
[ -f "$MODDIR/action.sh" ] || { echo "TS-AUTO-ADD 未安装" >&2; exit 1; }
exec sh "$MODDIR/action.sh" "$@"
EOF
chmod 755 /data/adb/ts-sync

ui_print "========================================"
ui_print "  TS-AUTO-ADD 安装完成"
ui_print "  手动同步: /data/adb/ts-sync"
ui_print "  规则文件: $MODPATH/rules.txt"
ui_print "========================================"
exit 0