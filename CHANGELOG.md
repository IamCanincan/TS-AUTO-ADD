## v1.6.57.6-yuzu - 2026-07-05
### 新增
- 整合`resetprop` 系统安全属性伪装，在 `post-fs-data` 阶段自动生效。
- 支持通用 Bootloader 状态欺骗（伪装 `locked`、`green`、`enforcing` 状态）。
- 新增对 小米 (MIUI/HyperOS) 及 真我 (Realme) 专属锁状态属性的针对性伪装。
- 自动隐藏 Magisk in Recovery 模式下的 Recovery 启动痕迹（`ro.bootmode`）。


-----


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
