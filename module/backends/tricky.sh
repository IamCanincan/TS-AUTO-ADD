#!/system/bin/sh
#=============================================================================
# backends/tricky.sh - Tricky Store 后端实现
#
# 职责：把生成好的应用列表原子写入 /data/adb/tricky_store/target.txt
# 说明：由 lib/common.sh 的 detect_backend 按需 source，run_sync 负责调用
#=============================================================================

# 说明：列表有变化时原子替换 target.txt；内容一致则不落盘。
# 用法：sync_target_list <target.txt> <临时文件>
# 依赖：build_app_list（lib/common.sh）生成列表并设置 TAA_COUNT
# 返回：0=已写入 1=内容一致未写入 2=结果为空
sync_target_list() {
    local target="$1"
    local tmp="$2"

    build_app_list "$tmp"

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" 2>/dev/null
        return 2
    fi

    if cmp -s "$tmp" "$target" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi

    mv -f "$tmp" "$target" 2>/dev/null
    chmod 644 "$target" 2>/dev/null
    return 0
}
