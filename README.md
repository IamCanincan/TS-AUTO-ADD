# TS-AUTO-ADD (v1.6.53.7-yuzu)

TS-AUTO-ADD 是一个基于 `inotifyd` 的后台守护程序，用于自动化维护 Tricky Store / TEE Simulator 的 `target.txt` 列表，并执行安全补丁日期自动追新与系统属性重置。

## 核心功能

* **配置自动化**：通过 `inotifyd` 监控 `/data/system/packages.list`，依据应用变更实时更新 `target.txt`。
* **状态看板管理**：模块 `description` 由后台进程托管，实时显示 [应用数 | 安全补丁日期 | 更新时间]。
* **补丁日期追新**：内置网络拉取机制，定期比对 Google 安全公告，将系统补丁日期校准至当月 05 日。
* **属性重置**：开机阶段自动执行 `taa_resetprop.sh`，覆盖并锁定关键 Boot 状态与调试属性。
* **环境兼容**：支持 Magisk、KernelSU 及 APatch 运行环境。

## 安装与部署

1. 确认 Tricky Store 或 TEE Simulator 已正常启用。
2. 在 Magisk/KernelSU 中安装本模块压缩包。
3. 重启设备以启动后台守护进程。

## 运行状态查询

安装后，模块详情页的简介将实时更新运行参数：
`[应用数: X | 补丁: YYYY-MM-05 | 更新: HH:MM]`

若需即时执行同步并刷新状态，在终端运行：

```bash
sh /data/adb/modules/ts-auto-add/action.sh

```

## 数据配置路径

所有运行时文件存储于 `/data/adb/tricky_store/`：

* `target.txt`：当前自动同步的应用包名列表。
* `security_patch.txt`：系统安全补丁日期配置文件。

## 属性重置覆盖清单

开机脚本强制执行以下属性校准：

* **安全状态**：`ro.boot.vbmeta.device_state` (locked), `ro.boot.verifiedbootstate` (green)。
* **调试状态**：`ro.debuggable` (0), `ro.build.tags` (release-keys), `ro.build.type` (user)。
* **痕迹隐藏**：移除 `recovery` 启动模式痕迹，修正各厂商预设的引导状态属性。

## 更新记录

详细变更请参阅模块根目录下的 `CHANGELOG.md`。