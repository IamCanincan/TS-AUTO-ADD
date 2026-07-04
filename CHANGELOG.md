# 更新日志 (CHANGELOG)

## v1.5.42.6-yuzu - 2026-07-05
### 新增
- **内置安全属性伪装**：新增 `taa_resetprop.sh` 脚本，在安装时自动部署至 `/data/adb/service.d` 目录，并赋予 `0755` 核心执行权限。
- **系统状态擦除**：开机自动通过 `resetprop` 重置并锁定关键 Boot 状态（如 `vbmeta.device_state` 设为 `locked`、`verifiedbootstate` 设为 `green` 等）。
- **设备指纹与调试隐藏**：自动关闭 `ro.debuggable`、设置 `ro.build.type` 为 `user` 且 `tags` 为 `release-keys`，完美伪装原厂状态。
- **深度清理联动**：在模块卸载时自动联动清理 `/data/adb/service.d/taa_resetprop.sh`，保证系统无文件残留。

---

## v1.4.31.5-yuzu - 2026-07-03
### 新增
- 首个稳定版发布
- 基于 inotifyd 的后台守护，实时监听 `/data/system/packages.list` 变化
- 自动维护 `/data/adb/tricky_store/target.txt`
- 固定保留 `com.android.vending`、`com.google.android.gms`、`com.google.android.gsf`
- 支持 Magisk 与 KernelSU
- 兼容 Tricky Store 或 TEE Simulator（二选一）

### 注意
- 此为初始版本，后续更新将在此文件中记录。