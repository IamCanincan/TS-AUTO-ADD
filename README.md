## TS-AUTO-ADD (v1.9.86.1-yuzu)

TS-AUTO-ADD 是一个基于 `inotifyd` 的后台守护程序，用于自动化维护 Tricky Store / TEE Simulator 的 `target.txt` 列表，并执行安全补丁日期自动追新与系统属性重置。

---

### 核心功能

- **应用列表自动同步**  
  监控 `/data/system/packages.list` 的变化（应用安装/卸载），自动将系统中所有第三方应用包名与用户自定义白名单合并、去重后写入 `target.txt`。

- **用户白名单 `taa_sys.txt`**  
  用户可手动编辑 `/data/adb/tricky_store/taa_sys.txt`，每行一个包名，添加需要保留的系统应用。模块监控该文件变更并自动合并，文件误删时自动重建默认内容（含 Google 核心三件套）。

- **安全补丁日期自动更新**  
  每隔 12 小时检查系统月份变化，若更新则从 Google AOSP 安全公告页面抓取最新日期，取系统日期与网络日期中较新者写入 `security_patch.txt`。同一月份内仅请求一次，避免重复网络访问。

- **系统属性伪装**  
  开机阶段执行 `taa_resetprop.sh`，重置关键属性（如 `ro.boot.vbmeta.device_state=locked`、`ro.debuggable=0` 等），模拟锁定状态，有助于通过特定检测。

- **守护进程自愈**  
  主进程每 60 秒检查子进程存活状态，异常时自动重启，确保长期稳定运行。

- **手动工具 `action.sh`**  
  提供终端手动同步命令，支持 `--force` 强制刷新补丁日期。

---

### 安装与部署

1. 确认 Tricky Store 或 TEE Simulator 已正常安装并启用。
2. 在 Magisk / KernelSU / APatch 中刷入本模块压缩包。
3. **重启设备**以启动后台守护服务。

---

### 使用方法

#### 自动运行
安装并重启后，所有功能自动生效，无需用户干预。

#### 手动同步
在终端以 root 权限执行：
```bash
su -c /data/adb/modules/ts-auto-add/action.sh
```
强制刷新补丁日期（忽略月份缓存）：
```bash
su -c /data/adb/modules/ts-auto-add/action.sh --force
```

#### 自定义白名单
编辑 `/data/adb/tricky_store/taa_sys.txt`，每行一个包名，保存后模块自动检测并合并。

---

### 文件与路径说明

所有数据文件存储于 `/data/adb/tricky_store/`：

| 文件 | 说明 |
|------|------|
| `target.txt` | 最终生成的 Tricky Store 应用列表（自动维护） |
| `taa_sys.txt` | 用户自定义白名单，可手动编辑（默认含 Google 三件套） |
| `security_patch.txt` | 安全补丁日期配置（自动维护） |
| `.ts_lock` | 进程锁（优先使用 flock） |
| `.ts_tmp` | 临时文件，用于原子写入 |
| `.last_month` | 月份缓存，控制网络请求频率 |
| `.ts_daemon_main.pid` | 主守护进程 PID |

---

### 卸载说明

- 卸载模块会自动终止后台进程、删除 PID 文件、锁文件、临时缓存及专属白名单 `taa_sys.txt`。
- `target.txt` 和 `security_patch.txt` 被保留，以免影响其他模块或手动配置。

---

### 更新与兼容性

- 当前版本：**v1.9.86.1-yuzu**
- 支持 Magisk、KernelSU、APatch
- 要求系统支持 `inotifyd`（通常由 BusyBox 提供）

更详细的版本更新记录请参阅模块根目录下的 `CHANGELOG.md` 文件。