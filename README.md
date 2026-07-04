# TS-AUTO-ADD

自动维护 Tricky Store / TEE Simulator 的 target.txt，无需手动编辑。内置系统安全属性状态重置脚本。

## 功能
- **实时同步**：开机自启，基于 `inotify` 异步驱动后台监听应用安装/卸载/更新，低功耗、零轮询。
- **动态控制**：
  - 自定义常驻系统应用（`fakesys.txt`），修改后立即生效。
  - 自定义排除第三方应用（`trueusr.txt`），修改后立即生效。
- **防抖机制**：在短时间内触发大批量包名变动时，自动开启防抖，避免高频 I/O。
- **系统状态隐藏 (v1.5.42.6+)**：自动向 `/data/adb/service.d` 部署 `taa_resetprop.sh` 脚本并赋权 `755`。开机自动伪装 `locked`、`green`、`release-keys` 等关键 Boot 状态，深度清理调试指纹与解锁痕迹。
- **全面兼容**：完美支持 Magisk 与 KernelSU。

## 安装
1. 确保已安装并启用 Tricky Store 或 TEE Simulator。
2. 将最新版 `TS-AUTO-ADD-v1.5.42.6-yuzu.zip` 下载并刷入。
3. 重启手机。

## 自定义配置
模块在 `/data/adb/tricky_store/` 目录下提供以下配置能力：
- `fakesys.txt`：常驻系统应用，每行一个包名。默认包含 Play 商店、GMS、GSF。
- `trueusr.txt`：需排除的第三方应用，每行一个包名。默认为空。

*提示：编辑并保存上述文件后，`target.txt` 将在数秒内自动感知并完成更新。*

## 核心重置属性清单
内置的 `taa_resetprop.sh` 脚本在开机时会自动覆盖并锁定以下核心属性：
- `ro.boot.vbmeta.device_state` -> `locked`
- `ro.boot.verifiedbootstate` -> `green`
- `ro.boot.flash.locked` -> `1`
- `ro.build.tags` -> `release-keys`
- `ro.debuggable` / `ro.force.debuggable` -> `0`
- 自动隐藏 Magisk 恢复模式引发的 `recovery` 启动模式。