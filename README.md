# TS-AUTO-ADD

自动维护 Tricky Store / TEE Simulator 的 target.txt，无需手动编辑。

## 功能
- 开机自启，后台监听应用安装/卸载/更新
- 实时同步包名列表到 target.txt
- 自定义常驻系统应用（fakesys.txt），修改后立即生效
- 自定义排除第三方应用（trueusr.txt），修改后立即生效
- 防抖机制，低功耗，零轮询
- 兼容 Magisk 与 KernelSU

## 安装
1. 确保已安装 Tricky Store 或 TEE Simulator
2. 下载本模块 ZIP 并刷入
3. 重启手机

## 自定义配置
- `/data/adb/tricky_store/fakesys.txt`：常驻系统应用，每行一个包名，默认含 Play 商店、GMS、GSF
- `/data/adb/tricky_store/trueusr.txt`：需排除的第三方应用，每行一个包名，默认为空

编辑后保存，target.txt 将在数秒内自动更新。
