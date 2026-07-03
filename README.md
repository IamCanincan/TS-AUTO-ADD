# TS-AUTO-ADD

自动为应用启用 Tricky Store 伪装功能，基于 inotifyd 守护进程。

## 功能
- 开机自启，后台监听 `/data/system/packages.list`
- 实时更新 `/data/adb/tricky_store/target.txt`
- 始终保持 Play 商店、GMS、GSF 在内的系统应用
- 事件驱动，零轮询，低功耗
- 支持 Magisk / KernelSU

## 安装
1. 下载本模块 ZIP 包
2. 在 Magisk / KernelSU 管理器中选择安装
3. 重启设备

## 文件说明
- `module.prop` - 模块信息
- `customize.sh` - 安装脚本
- `service.sh` - 守护服务
- `uninstall.sh` - 卸载清理
