# TS-AUTO-ADD (v1.9.86.1-yuzu)

TS-AUTO-ADD 是一个专为 **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** 设计的 Magisk 辅助模块，通过后台守护进程自动维护应用包名列表（`target.txt`）与安全补丁日期（`security_patch.txt`），并可在开机时重置关键系统属性，有效提升 Play Integrity 通过率。

---

## ✨ 核心功能

- **自动同步应用列表**  
  合并系统白名单（`taa_sys.txt`）与所有第三方用户应用，去重后生成 `target.txt`，供 Tricky Store 使用。

- **智能安全补丁追新**  
  定期从 Google 安全公告页面抓取最新补丁日期，并与系统日期比对，自动选用较新版本写入 `security_patch.txt`（system/boot/vendor 统一）。采用月份缓存，仅当月变化或手动 `--force` 时联网，节省流量。

- **事件驱动实时监听**  
  自动探测 `inotifywait` 或 `inotifyd`，监听 `/data/system/packages.list` 及 `taa_sys.txt` 的变更，触发即时同步。内置防抖机制，避免频繁写入。

- **系统属性伪装**  
  开机阶段执行 `taa_resetprop.sh`，重置关键属性（如 `ro.boot.verifiedbootstate`、`ro.debuggable` 等），模拟设备处于锁定、绿标状态。

- **统一进程管理**  
  所有后台子进程 PID 记录于 `.ts_daemon_pids.list`，卸载时可一次性全部终止，无残留。

- **本地日志记录**  
  运行日志同时输出至 `/data/local/tmp/ts_auto.log` 及系统日志（`logcat`），方便离线排查。

- **兼容性广泛**  
  支持 Magisk、KernelSU、APatch，并自动适配 `inotifywait` / `inotifyd` 两种监控模式。

---

## 📥 安装与部署

### 前置条件
- 已安装 **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** 模块，且 `/data/adb/tricky_store/target.txt` 文件存在（可为空）。
- 系统具备 `inotifywait` 或 `inotifyd` 其中之一（绝大多数 Android 系统已内置）。

### 安装步骤
1. 在 Magisk 管理器中刷入本模块 ZIP 包。
2. 安装脚本将自动：
   - 检测 inotify 支持，若无则中止安装。
   - 创建工作目录及默认系统白名单 `taa_sys.txt`（含 Google 三件套）。
   - 生成初始 `target.txt`，合并白名单与当前第三方应用。
   - 将 `taa_resetprop.sh` 部署至 `/data/adb/service.d`。
   - 更新模块描述信息。
3. **重启设备** 以启动后台守护服务。

---

## 🛠 使用方法

### 手动同步
若需立即触发一次完整同步（应用列表 + 安全补丁），执行：

```bash
sh /data/adb/modules/ts-auto-add/action.sh
```

强制忽略月份缓存，重新在线获取补丁日期：

```bash
sh /data/adb/modules/ts-auto-add/action.sh --force
```

### 查看运行状态
- **模块描述**：在 Magisk 模块详情页，`description` 字段会动态显示：
  ```
  [系统: X | 用户: Y | 补丁: system=YYYY-MM-DD boot=YYYY-MM-DD vendor=YYYY-MM-DD | 更新: HH:MM]
  ```
- **本地日志**：`/data/local/tmp/ts_auto.log`
- **系统日志**：`logcat | grep TS-AUTO`

### 自定义系统白名单
- 文件路径：`/data/adb/tricky_store/taa_sys.txt`
- 每行一个包名，默认包含：
  ```
  com.android.vending
  com.google.android.gms
  com.google.android.gsf
  ```
- 修改此文件后，守护进程会自动触发同步，将新增的包名合并进 `target.txt`（无需重启）。

---

## 📂 数据与配置路径

所有运行时文件位于 **`/data/adb/tricky_store/`**：

| 文件 | 说明 |
|------|------|
| `target.txt` | 最终输出的应用包名列表（供 Tricky Store 使用） |
| `taa_sys.txt` | 系统白名单（用户可手动编辑） |
| `security_patch.txt` | 安全补丁配置（system/boot/vendor 日期） |
| `.last_month` | 月份缓存（用于避免重复联网） |
| `.ts_daemon_pids.list` | 所有后台子进程 PID 列表 |
| `.ts_lock` | 互斥锁目录（运行时） |
| `.ts_debounce` | 防抖锁目录（运行时） |
| `.ts_tmp` | 临时文件（运行时） |
| `/data/local/tmp/ts_auto.log` | 模块运行日志 |

---

## ⚙️ 属性重置覆盖清单

开机阶段执行的 `taa_resetprop.sh` 会强制重置以下属性：

| 属性名 | 重置值 | 作用 |
|--------|--------|------|
| `ro.boot.vbmeta.device_state` | `locked` | 模拟 Bootloader 锁定 |
| `ro.boot.verifiedbootstate` | `green` | 模拟验证状态为绿标 |
| `ro.boot.flash.locked` | `1` | 锁定闪存状态 |
| `ro.boot.veritymode` | `enforcing` | 强制开启 verity |
| `ro.boot.warranty_bit` | `0` | 清除保修位 |
| `ro.warranty_bit` | `0` | 同上 |
| `ro.debuggable` | `0` | 关闭可调试 |
| `ro.force.debuggable` | `0` | 强制关闭调试 |
| `ro.secure` | `1` | 启用安全模式 |
| `ro.adb.secure` | `1` | 启用 ADB 安全 |
| `ro.build.type` | `user` | 设置为用户版 |
| `ro.build.tags` | `release-keys` | 发布密钥 |
| `ro.vendor.boot.warranty_bit` | `0` | 供应商保修位清零 |
| `ro.vendor.warranty_bit` | `0` | 同上 |
| `vendor.boot.warranty_bit` | `0` | 同上 |
| `ro.bootloader`（若含 `engineering`） | `release` | 隐藏工程版 Bootloader |
| `ro.build.description`（若含 `test-keys`） | `release-keys` | 隐藏测试密钥 |

> **提示**：若您不需要属性重置，可直接删除 `/data/adb/service.d/taa_resetprop.sh` 并重启。

---

## 🔄 更新亮点（v1.9.86.1-yuzu）

- **模块重构**：新增 `common.sh` 公共函数库，代码复用率提升 60%。
- **双 inotify 模式**：自动适配 `inotifywait` / `inotifyd`，兼容性更广。
- **防抖机制**：短时多次触发合并为一次同步，降低系统负载。
- **白名单分离**：`taa_sys.txt` 与用户应用分开管理，便于自定义。
- **本地日志**：写入 `/data/local/tmp/ts_auto.log`，便于排查。
- **补丁获取优化**：切换至 `source.android.com`，增加重试，成功率更高。
- **属性注入精简**：移除厂商专用属性，增强跨设备兼容性。
- **进程管理统一**：PID 列表化管理，卸载彻底无残留。

详细变更请参阅模块根目录下的 `CHANGELOG.md`。

---

## ❓ 常见问题

**Q：安装时提示“未找到 inotify 工具”？**  
A：请确认系统是否包含 `inotifywait` 或 `inotifyd`。部分精简 ROM 可能缺失，可尝试安装 Busybox 或更换 ROM。

**Q：`target.txt` 未按预期更新？**  
A：检查 `/data/local/tmp/ts_auto.log` 查看错误信息；确认 `pm` 命令可用；尝试手动执行 `action.sh` 测试。

**Q：安全补丁日期始终为系统日期，未联网更新？**  
A：模块会检测网络连通性（ping 223.5.5.5 或 8.8.8.8），若网络不通则推迟。可手动执行 `action.sh --force` 强制更新。

**Q：如何临时禁用后台监听？**  
A：可删除 `/data/adb/tricky_store/.ts_daemon_pids.list` 并重启，或直接卸载模块。

---

## 📝 许可证

本模块遵循 **GPL-3.0** 开源协议，欢迎贡献代码与反馈问题。

---

**版本**：v1.9.86.1-yuzu  
**更新日期**：2026-07-08  
**维护者**：IamCanincan