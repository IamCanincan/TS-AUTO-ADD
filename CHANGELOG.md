# 更新日志 (CHANGELOG)

## v1.6.53.7-yuzu (Current) - 2026-07-06

### 新增

* **简介动态托管机制**：彻底弃用模块原有的静态简介，改为由 `service.sh` 与 `action.sh` 统一接管，实现运行状态数据的实时全覆盖。
* **状态看板化**：简介行更新为客观运行状态展示：`[应用数: X | 补丁: YYYY-MM-05 | 更新: HH:MM]`。
* **架构一致性**：统一了后台守护服务与手动诊断工具的数据源，确保界面显示在任何触发场景下均保持高度一致。

---

## v1.5.42.6-yuzu - 2026-07-05

### 新增

* **内置安全属性伪装**：新增 `taa_resetprop.sh`，实现开机 boot 状态锁定与调试标记清除。
* **系统状态擦除**：自动重置 `vbmeta.device_state` 为 `locked`，`verifiedbootstate` 为 `green` 等关键状态。
* **设备指纹隐藏**：强制重置 `ro.debuggable`、`ro.build.type` 及 `tags` 属性。
* **深度清理联动**：卸载时自动移除所有相关运行脚本，确保系统环境零残留。

---

## v1.4.31.5-yuzu - 2026-07-03

### 新增

* 首个稳定版发布。
* 基于 inotifyd 的后台守护，实时监听 `/data/system/packages.list` 变化。
* 自动维护 `/data/adb/tricky_store/target.txt`，固定保留谷歌核心三件套。
* 兼容 Magisk、KernelSU 及 APatch 环境。

---

### 使用建议

* 模块安装后请重启一次设备。
* 如需立即强制更新状态数据，请在终端执行：`sh /data/adb/modules/ts-auto-add/action.sh`。