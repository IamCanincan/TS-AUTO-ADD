#!/system/bin/sh
#=============================================================================
# Tricky Store 后端实现：把应用列表原子写入 target.txt
# 由 lib/common.sh 的 detect_backend 按需 source，run_sync 调用 sync_target_list
#=============================================================================

# 用法：sync_target_list <target.txt 路径> <临时文件路径>
# 依赖：build_app_list（lib/common.sh）生成列表并设置 TAA_COUNT
# 返回码：0=已写入；1=内容一致未写入；2=结果为空
sync_target_list() {
    local target="$1" tmp="$2"
    build_app_list "$tmp"

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" 2>/dev/null
        TAA_COUNT=0
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
