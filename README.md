根据最新版本 v1.8.75.9-yuzu 的变更，已更新 README 内容如下：

```markdown
## TS-AUTO-ADD (v1.8.75.9-yuzu)

TS-AUTO-ADD 是一个基于 `inotifyd` 的后台守护程序，用于自动化维护 Tricky Store / TEE Simulator 的 `target.txt` 列表，并执行安全补丁日期自动追新与系统属性重置。

## 核心功能

* **配置自动化**：通过 `inotifyd` 监控 `/data/system/packages.list`，依据应用变更实时更新 `target.txt`。
* **状态看板管理**：模块 `description` 由后台进程托管，实时显示 `[应用数 | 安全补丁日期 | 更新时间]`。
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

### 手动同步

若需即时执行同步并刷新状态，在终端运行：

```bash
sh /data/adb/modules/ts-auto-add/action.sh
```

强制在线获取安全补丁日期（忽略本地缓存）：

```bash
sh /data/adb/modules/ts-auto-add/action.sh --force
```

## 数据配置路径

所有运行时文件存储于 `/data/adb/tricky_store/`：

* `target.txt`：当前自动同步的应用包名列表。
* `security_patch.txt`：系统安全补丁日期配置文件。

## 属性重置覆盖清单

开机脚本强制执行以下属性校准：

* **安全状态**：`ro.boot.vbmeta.device_state` (locked)，`ro.boot.verifiedbootstate` (green)。
* **调试状态**：`ro.debuggable` (0)，`ro.build.tags` (release-keys)，`ro.build.type` (user)。
* **痕迹隐藏**：移除 `recovery` 启动模式痕迹，修正各厂商预设的引导状态属性。

## 更新记录

详细变更请参阅模块根目录下的 `CHANGELOG.md`。

---

### v1.8.75.9-yuzu 主要更新

* **安全补丁配置统一**：`security_patch.txt` 中 `system` 字段改为动态日期，与 `boot`/`vendor` 保持一致，消除配置差异。
* **应用列表健壮性**：生成 `target.txt` 时自动过滤空行，防止无第三方应用时出现空白条目，确保统计准确。

### v1.7.64.8-yuzu 主要更新

* **进程管理完善**：增加补丁更新进程 PID 文件（`.ts_patch.pid`），解决升级后进程残留问题。
* **手动工具增强**：`action.sh` 增加互斥锁机制和 `--force` 参数，支持强制刷新安全补丁。
* **Shell 兼容性修复**：`taa_resetprop.sh` 改用 POSIX 兼容语法，确保在所有 Android 环境下正常运行。
* **锁机制优化**：增加超时（30 秒）并强制清理残留锁，避免死锁。
* **网络请求增强**：为 curl / wget 添加 `User-Agent` 头，提高访问成功率。
* **安装与卸载完善**：同步清理新增的 PID 文件和进程，确保无残留。
```