## v1.4.31.5-yuzu - 2026-07-03
### 新增
- 首个稳定版发布
- 基于 inotifyd 的后台守护，实时监听 `/data/system/packages.list` 变化
- 自动维护 `/data/adb/tricky_store/target.txt`
- 固定保留 com.android.vending、com.google.android.gms、com.google.android.gsf
- 支持 Magisk 与 KernelSU
- 兼容 Tricky Store 或 TEE Simulator（二选一）

### 注意
- 此为初始版本，后续更新将在此文件中记录。
