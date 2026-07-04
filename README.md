# TS-AUTO-ADD

自动为应用启用 Tricky Store 伪装功能，并整合系统安全属性欺骗与痕迹隐藏，基于 inotifyd 守护进程。

## 功能

* **自动化同步**：开机自启，后台监听 `/data/system/packages.list`

* **智能过滤**：实时更新 `/data/adb/tricky_store/target.txt`，始终保持 Play 商店、GMS、GSF 在内的系统应用


* **高效低耗**：事件驱动，零轮询，低功耗


* **属性伪装**：在 `post-fs-data` 阶段自动修改核心 `ro` 属性，伪装 Bootloader 锁状态（`locked`/`green`/`enforcing`）
* **专机优化**：针对小米 (MIUI/HyperOS) 及 真我 (Realme) 的专属锁状态属性进行针对性伪装
* **痕迹隐藏**：自动隐藏 Magisk in Recovery 模式下的 Recovery 启动痕迹
* **广泛兼容**：支持 Magisk / KernelSU



## 安装

1. 下载本模块 ZIP 包
2. 在 Magisk / KernelSU 管理器中选择安装


3. 重启设备



## 文件说明

* `module.prop` - 模块信息


* `customize.sh` - 安装与权限配置脚本


* `post-fs-data.sh` - 系统安全属性伪装脚本
* `service.sh` - 守护服务（负责应用包名监听）


* `uninstall.sh` - 卸载清理