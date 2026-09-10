# TS-AUTO-ADD (v2.1.08.3-yuzu)

TS-AUTO-ADD 是一个专为 **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** 及其开源分支 **[Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)** 设计的 Magisk 辅助模块，通过后台守护进程自动维护应用包名列表（`target.txt`），并可在开机时重置关键系统属性，有效提升 Play Integrity 通过率。

> 本模块**不再修改安全补丁**（`security_patch.txt`），仅维护应用列表与系统属性。

---

## ✨ 核心功能

- **自动同步应用列表**  
  合并 `rules.txt`（常驻列表）与已安装第三方应用，去重后生成 `target.txt`，供 Tricky Store / Tricky Store OSS 使用。应用安装/卸载时自动触发同步。

- **事件驱动实时监听**  
  自动探测 `inotifywait` 或 `inotifyd`，监听 `/data/system/packages.list` 及 `rules.txt` 的变更，仅在真正发生安装/卸载或常驻列表变化时执行同步。内置防抖机制与内容指纹比对，避免频繁刷新。

- **系统属性伪装**  
  开机早期（Zygote 启动前，`post-fs-data.sh`）执行属性重置，模拟设备处于锁定、绿标状态（如 `ro.build.type`、`ro.boot.verifiedbootstate`、`ro.debuggable` 等），确保 `Build.TYPE` 等静态字段在应用启动前即为干净值。

- **统一进程管理**  
  所有后台子进程 PID 记录于 `.ts_daemon_pids.list`，卸载时可一次性全部终止，无残留。

- **本地日志记录**  
  运行日志输出至 root 专属的 `/data/adb/ts_auto.log`（`600` 权限）及系统日志（`logcat`），方便离线排查。

- **兼容性广泛**  
  支持 Magisk、KernelSU、APatch，并自动适配 `inotifywait` / `inotifyd` 两种监控模式。

---

## 📥 安装与部署

### 前置条件
- 已安装 **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** 或 **[Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)** 模块，且 `/data/adb/tricky_store/target.txt` 文件存在（可为空）。
- 系统具备 `inotifywait` 或 `inotifyd` 其中之一（绝大多数 Android 系统已内置）。

### 安装步骤
1. 在 Magisk 管理器中刷入本模块 ZIP 包。
2. 安装脚本将自动：
   - 检测 inotify 支持，若无则中止安装。
   - 创建工作目录及默认 `rules.txt`（含 Google 三件套）；旧版 `taa_sys.txt` 自动迁移。
   - 生成初始 `target.txt`，合并常驻列表与当前第三方应用。
   - 更新模块描述信息。
3. **重启设备** 以启动后台守护服务。

---

## 🛠 使用方法

### 手动同步
若需立即触发一次完整同步（应用列表），执行：

```bash
sh /data/adb/modules/ts-auto-add/action.sh
```

### 查看运行状态
- **模块描述**：在 Magisk 模块详情页，`description` 字段会动态显示：
  ```
  [应用: X | 更新: HH:MM]
  ```
- **本地日志**：`/data/adb/ts_auto.log`
- **系统日志**：`logcat | grep TS-AUTO`

### 自定义常驻列表
- 文件路径：`/data/adb/tricky_store/rules.txt`
- 每行一个包名，默认包含：
  ```
  com.android.vending
  com.google.android.gms
  com.google.android.gsf
  ```
- 修改此文件后，守护进程会自动触发同步，将新增的包名合并进 `target.txt`（无需重启）。

---

## 📂 数据与配置路径

运行时文件主要位于 **`/data/adb/tricky_store/`**，运行日志位于 **`/data/adb/ts_auto.log`**：

| 文件 | 说明 |
|------|------|
| `target.txt` | 最终输出的应用包名列表（供 Tricky Store / Tricky Store OSS 使用） |
| `rules.txt` | 常驻应用列表（始终并入 target.txt，可手动编辑） |
| `.ts_daemon_pids.list` | 所有后台子进程 PID 列表 |
| `.ts_fingerprint` | 源数据指纹缓存（变更检测用） |
| `.ts_lock` | 互斥锁目录（运行时） |
| `.ts_debounce` | 防抖锁目录（运行时） |
| `.ts_tmp` | 临时文件（运行时） |
| `/data/adb/ts_auto.log` | 模块运行日志 |

---

## ⚙️ 属性重置覆盖清单

开机早期（`post-fs-data.sh`，Zygote 启动前）强制重置以下属性：

| 属性名 | 重置值 | 作用 |
|--------|--------|------|
| `ro.build.type` | `user` | 设置为用户版（修复 `Build.TYPE` 显示 userdebug） |
| `ro.build.tags` | `release-keys` | 发布密钥 |
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
| `ro.vendor.boot.warranty_bit` | `0` | 供应商保修位清零 |
| `ro.vendor.warranty_bit` | `0` | 同上 |
| `vendor.boot.warranty_bit` | `0` | 同上 |
| `ro.bootloader`（若含 `engineering`） | `release` | 隐藏工程版 Bootloader |
| `ro.build.description`（若含 `test-keys`） | `release-keys` | 隐藏测试密钥 |

> **提示**：若您不需要属性重置，可在 `post-fs-data.sh` 中删除或注释 `apply_resetprop` 调用后重启。

---

## 🔄 更新亮点（v2.1.08.3-yuzu）

- **移除安全补丁功能**：不再读取、生成或修改 `security_patch.txt`，模块只维护应用列表与系统属性。
- **移除系统/用户区分**：`taa_sys.txt` 更名为 `rules.txt`，不再区分“系统应用/用户应用”，只显示总应用数。
- **省电稳定**：无后台联网轮询；inotify 监听合并为单进程；内容指纹比对，仅在数据真实变化时同步。
- **属性伪装提前**：`apply_resetprop` 移至 `post-fs-data.sh`（Zygote 前），修复 `Build.TYPE` 检测。
- **日志安全**：日志迁移至 root 专属的 `/data/adb/ts_auto.log`（`600` 权限）。
- **兼容范围收敛**：仅面向 Tricky Store / Tricky Store OSS。

详细变更请参阅模块根目录下的 `CHANGELOG.md`。

---

## ❓ 常见问题

**Q：安装时提示“未找到 inotify 工具”？**  
A：请确认系统是否包含 `inotifywait` 或 `inotifyd`。部分精简 ROM 可能缺失，可尝试安装 Busybox 或更换 ROM。

**Q：`target.txt` 未按预期更新？**  
A：检查 `/data/adb/ts_auto.log` 查看错误信息；确认 `pm` 命令可用；尝试手动执行 `action.sh` 测试。

**Q：如何临时禁用后台监听？**  
A：可删除 `/data/adb/tricky_store/.ts_daemon_pids.list` 并重启，或直接卸载模块。

---

## 📝 许可证

本模块遵循 **GPL-3.0** 开源协议，欢迎贡献代码与反馈问题。

---

**版本**：v2.1.08.3-yuzu  
**更新日期**：2026-09-10  
**维护者**：IamCanincan
