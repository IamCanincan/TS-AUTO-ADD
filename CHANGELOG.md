## 更新日志 (CHANGELOG)

---

### v1.8.75.9-yuzu - 2026-07-06

#### 优化

* **安全补丁配置统一**：`security_patch.txt` 中的 `system` 字段值由固定 `prop` 改为动态日期 `$FINAL_DATE`，与 `boot`、`vendor` 保持一致，避免配置不匹配。
* **应用列表生成健壮性**：在 `do_sync()` 中增加空行过滤（`sed '/^$/d'`），防止无第三方应用时 `target.txt` 出现空白行，确保行数统计准确。

---

### v1.7.64.8-yuzu - 2026-07-06

#### 新增

* **补丁更新进程 PID 管理**：新增 `.ts_patch.pid` 文件记录安全补丁后台更新进程的 PID，解决升级或重装时旧进程残留问题。
* **`action.sh` 手动工具增强**：
  * 引入互斥锁机制（`LOCK_DIR`），避免与后台守护进程同时操作冲突。
  * 增加 `--force` / `-f` 命令行参数，支持强制清除月份缓存并重新在线获取安全补丁日期。
  * 保留 `.last_month` 月份缓存，仅在月份变更或强制模式下发起网络请求，减少不必要流量。
* **`customize.sh` 安装脚本增强**：
  * 安装前清理新增的 `.ts_patch.pid` 文件。
  * 部署 `taa_resetprop.sh` 前检查文件是否存在，避免因缺失导致报错。

#### 修复

* **Shell 兼容性修复**：将 `taa_resetprop.sh` 中的 Bash 专有语法 `[[ ... = *...* ]]` 改为 POSIX 兼容的 `case` 匹配，确保在 Android 默认 shell（mksh / ash）下正常运行。
* **空值变量引用修复**：为 `check_reset_prop` 函数中的所有变量添加双引号，避免空值导致语法错误。
* **并发锁死锁风险**：为 `acquire_lock` 增加 30 秒超时，超时后强制删除残留锁目录，防止进程意外退出导致永久死锁。
* **网络请求被拒**：为 `fetch_online_date` 中的 curl / wget 添加 `User-Agent` 头，模拟浏览器访问，降低被服务器拒绝的可能。
* **卸载脚本不完整**：`uninstall.sh` 增加对 `.ts_patch.pid` 进程的终止和文件删除，确保完全卸载无残留。

#### 优化

* **安全补丁在线获取**：`update_security_patch` 与 `action.sh` 现支持循环尝试多个备用 URL，提高网络获取成功率。
* **注释客观化**：全面梳理所有脚本注释，使用中性技术描述，移除主观修饰词，提升可读性和维护性。
* **安装日志细化**：`customize.sh` 增加 `taa_resetprop.sh` 部署状态提示，安装过程更透明。

---

### v1.6.53.7-yuzu - 2026-07-06

#### 新增

* **简介动态托管机制**：彻底弃用模块原有的静态简介，改为由 `service.sh` 与 `action.sh` 统一接管，实现运行状态数据的实时全覆盖。
* **状态看板化**：简介行更新为客观运行状态展示：`[应用数: X | 补丁: YYYY-MM-05 | 更新: HH:MM]`。
* **架构一致性**：统一了后台守护服务与手动诊断工具的数据源，确保界面显示在任何触发场景下均保持高度一致。

---

### v1.5.42.6-yuzu - 2026-07-05

#### 新增

* **内置安全属性伪装**：新增 `taa_resetprop.sh`，实现开机 boot 状态锁定与调试标记清除。
* **系统状态擦除**：自动重置 `vbmeta.device_state` 为 `locked`，`verifiedbootstate` 为 `green` 等关键状态。
* **设备指纹隐藏**：强制重置 `ro.debuggable`、`ro.build.type` 及 `tags` 属性。
* **深度清理联动**：卸载时自动移除所有相关运行脚本，确保系统环境零残留。

---

### v1.4.31.5-yuzu - 2026-07-03

#### 新增

* 首个稳定版发布。
* 基于 inotifyd 的后台守护，实时监听 `/data/system/packages.list` 变化。
* 自动维护 `/data/adb/tricky_store/target.txt`，固定保留谷歌核心三件套。
* 兼容 Magisk、KernelSU 及 APatch 环境。

---

### 使用建议

* 模块安装后请重启一次设备。
* 如需立即强制更新状态数据，请在终端执行：  
  `sh /data/adb/modules/ts-auto-add/action.sh`  
  若需强制在线刷新安全补丁日期，可附加 `--force` 参数。