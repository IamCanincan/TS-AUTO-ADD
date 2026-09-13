# TS-AUTO-ADD (v2.2.19.4-yuzu)

[![Build CI Module](https://github.com/IamCanincan/TS-AUTO-ADD/actions/workflows/build_ci.yml/badge.svg)](https://github.com/IamCanincan/TS-AUTO-ADD/actions/workflows/build_ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/IamCanincan/TS-AUTO-ADD?label=release&color=blue)](https://github.com/IamCanincan/TS-AUTO-ADD/releases/latest)
[![License](https://img.shields.io/github/license/IamCanincan/TS-AUTO-ADD?color=green)](LICENSE)

TS-AUTO-ADD 是一个面向 **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** / **[Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)** / **TEE Simulator** 的 Magisk 辅助模块，通过后台守护进程自动维护应用包名列表，并可在开机时重置关键系统属性，有效提升 Play Integrity 通过率。

> 本模块**不再修改安全补丁**（`security_patch.txt`），仅维护应用列表与系统属性。

### 🔌 双后端自动探测

| 后端 | 判定依据（`/data/adb/modules` 下的模块 id） | 维护目标 |
|------|----------------------------------------------|----------|
| **TEE Simulator** | `teesim` | `/data/adb/teesim/config.json` 的 `profiles.default.apps` |
| **Tricky Store / OSS** | `tricky_store` | `/data/adb/tricky_store/target.txt` |

TEE Simulator 模式下**只替换 `default` profile 的 `apps`**，其余字段（`keybox` / `mode` / `patchLevel` / 设备信息等）与其它 profile 一律原样保留；无法可靠定位数组时放弃写入。

> ⛔ 两个模块**同时启用**时，模块直接停止运行（不做优先级选择），并把停止状态写入模块描述。

---

## ✨ 核心功能

- **自动同步应用列表**  
  合并 `rules.txt`（常驻列表）与已安装第三方应用，去重后写入当前后端的目标文件。应用安装/卸载时自动触发同步。

- **事件驱动实时监听**  
  自动探测 `inotifywait` 或 `inotifyd`，监听 `/data/system/packages.list` 及 `rules.txt` 的变更，仅在真正发生安装/卸载或常驻列表变化时执行同步。内置防抖机制与内容指纹比对，避免频繁刷新。

- **系统属性伪装**  
  开机早期（Zygote 启动前，`post-fs-data.sh`）执行属性重置，模拟设备处于锁定、绿标状态（如 `ro.build.type`、`ro.boot.verifiedbootstate`、`ro.debuggable` 等），确保 `Build.TYPE` 等静态字段在应用启动前即为干净值。

- **统一进程管理**  
  所有后台子进程 PID 记录于 `.ts_daemon_pids.list`，卸载时可一次性全部终止，无残留。

- **运行日志（logcat + 本地缓冲）**  
  日志同时写入系统日志（`logcat`，tag 为 `TS-AUTO`）与本地缓冲文件 `/data/adb/ts_auto.log`。`logcat` 是内存环形缓冲（默认仅几百 KB 且全系统共用），系统繁忙时旧记录很快被挤掉、重启即清空；缓冲文件容量固定（超过 64KB 自动只保留末尾 200 行）、跨重启保留，权限 `600` 且位于 `0700` 的 `/data/adb`，仅 root 可读。

- **兼容性广泛**  
  支持 Magisk、KernelSU、APatch，并自动适配 `inotifywait` / `inotifyd` 两种监控模式（含各框架自带的 busybox）。

---

## 🧩 模块结构

```
module/
├─ module.prop            # 模块元数据
├─ customize.sh           # 安装入口（框架按固定路径调用）
├─ post-fs-data.sh        # 开机早期入口：Zygote 前属性伪装
├─ service.sh             # 后台守护入口
├─ action.sh              # 手动同步入口（管理器“操作”按钮）
├─ uninstall.sh           # 卸载入口
├─ lib/
│  ├─ common.sh           # 函数库加载入口
│  ├─ core.sh             # 路径常量、运行期状态、日志（logcat + 本地缓冲）
│  ├─ lock.sh             # 并发锁
│  ├─ tools.sh            # 外部工具定位（awk / inotify）
│  ├─ applist.sh          # 常驻列表与应用列表生成
│  ├─ backend.sh          # 后端探测、后端写入、模块描述、同步入口
│  └─ props.sh            # 系统属性伪装
├─ backends/
│  ├─ tricky.sh           # Tricky Store 后端实现：写 target.txt
│  └─ teesim.awk          # TEE Simulator 后端实现：定点替换 default.apps
└─ META-INF/              # 刷机包脚本
```

- **入口脚本必须留在根目录**：Magisk / KernelSU / APatch 按固定路径调用 `customize.sh` / `post-fs-data.sh` / `service.sh` / `uninstall.sh`，管理器“操作”按钮调用 `action.sh`。
- `lib/` 放共享库，`backends/` 放后端实现（每个后端一个文件）；入口脚本与 `lib/common.sh` 中都不含后端专属逻辑。

---

## 📥 安装与部署

### 下载
- **发行版（推荐）**：到 [Releases](https://github.com/IamCanincan/TS-AUTO-ADD/releases) 下载 `TS-AUTO-ADD-<版本>.zip`（文件名与 `update.json` 中的 `zipUrl` 一致，管理器内更新也走这一份）。
- **CI 构建**：每次推送到 `main` 会自动构建，版本号附带时间戳后缀（`-ci`）。到 [Actions](https://github.com/IamCanincan/TS-AUTO-ADD/actions/workflows/build_ci.yml) 打开最近一次运行，在页面底部 Artifacts 下载 —— 仅供测试，不要当作正式版本。

### 前置条件
- 已安装以下**任一**后端模块：
  - **[Tricky Store](https://github.com/5ec1cff/TrickyStore)** 或 **[Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)**（模块 id `tricky_store`），`/data/adb/tricky_store/target.txt` 存在（可为空）；
  - **TEE Simulator**（模块 id `teesim`），`/data/adb/teesim/config.json` 存在。
- 系统具备 `inotifywait` 或 `inotifyd` 其中之一（绝大多数 Android 系统已内置；Magisk / KernelSU / APatch 自带的 busybox 亦可）。
- **两个后端不要同时启用**：同时启用时模块会停止运行，并在模块描述中提示。

### 安装步骤
1. 在 Magisk 管理器中刷入本模块 ZIP 包。
2. 安装脚本将自动：
   - 检测 inotify 支持，若无则中止安装。
   - 按模块 id 探测后端并初始化工作目录。
   - 创建默认 `rules.txt`（含 Google 三件套与中文注释）；旧版 `taa_sys.txt` 或另一后端的 `rules.txt` 自动继承。
   - 执行一次初始同步并更新模块描述信息。
3. **重启设备** 以启动后台守护服务。

---

## 🛠 使用方法

### 手动同步
若需立即触发一次完整同步（应用列表），执行：

```bash
sh /data/adb/modules/ts-auto-add/action.sh
```

### 查看运行状态
- **模块描述**：在模块详情页，`description` 字段动态显示：
  ```
  ✅ [后端 | 应用: X | 更新: HH:MM]
  ```
  写入失败时显示 `⚠️ [… 写入失败 …]`，后端冲突停止时显示 `⛔ [模块已停止 …]`。

- **运行日志**：日志同时写 `logcat`（tag `TS-AUTO`）与本地缓冲 `/data/adb/ts_auto.log`（超过 64KB 自动只保留末尾 200 行）。
  最省事的方式是在管理器里点模块的“操作”按钮：`action.sh` 会同步一次并附带打印最近 15 条日志，无需自己 `su`。

  以下命令供手动排查使用。

  设备上读日志**需要 root**（`/data/adb` 为 `0700`；在终端 App 里先 `su`，或用 `su -c '...'` 包裹）：

  ```bash
  tail -n 50 /data/adb/ts_auto.log                     # 本地缓冲，跨重启保留（推荐）
  grep -E '后端|同步|失败|停止' /data/adb/ts_auto.log   # 只看关键行
  logcat -d -s TS-AUTO | tail -n 30                    # 系统日志（重启即清空）
  logcat -s TS-AUTO                                    # 实时跟随（Ctrl+C 退出）
  logcat -c                                            # 先清空系统缓冲再操作，便于观察单次行为
  ```

  电脑上（需已开启 USB 调试；`adb` 读 `logcat` 不需要 root，读 `/data/adb` 需要）：

  ```bash
  adb logcat -s TS-AUTO                                       # 实时查看（不需要 root）
  adb shell su -c 'tail -n 50 /data/adb/ts_auto.log'          # 读本地缓冲（需要 root）
  adb shell su -c 'cat /data/adb/ts_auto.log' > ts_auto_log.txt   # 导出到电脑再慢慢看
  ```

  > 模块只在**开机**与**文件变化**（安装/卸载应用、修改 `rules.txt`）时写日志，没有事件时不会有输出，属正常现象。缓冲文件的每行都带 `月-日 时:分:秒` 时间戳，不依赖 `logcat` 缓冲是否还在。

### 自定义常驻列表
常驻列表 `rules.txt` 位于当前后端目录：

| 后端 | 路径 |
|------|------|
| TEE Simulator | `/data/adb/teesim/rules.txt` |
| Tricky Store / OSS | `/data/adb/tricky_store/rules.txt` |

- 每行一个包名；**以 `#` 开头的行是注释，空行会被忽略**（默认内容自带说明注释）。
- 默认包含 Google 三件套：
  ```
  com.android.vending
  com.google.android.gms
  com.google.android.gsf
  ```
- 修改此文件后，守护进程会自动触发同步（无需重启）；同步前会自动补齐末行换行并清除 UTF-8 BOM。

---

## 📂 数据与配置路径

运行时文件位于**当前后端目录**（`/data/adb/teesim/` 或 `/data/adb/tricky_store/`）：

| 文件 | 说明 |
|------|------|
| `config.json` | TEE Simulator 配置（模块仅维护 `profiles.default.apps`） |
| `target.txt` | Tricky Store / OSS 的应用列表（模块整体重写） |
| `rules.txt` | 常驻应用列表（始终并入目标，可手动编辑，支持 `#` 注释） |
| `.ts_daemon_pids.list` | 所有后台子进程 PID 列表 |
| `.ts_fingerprint` | 源数据指纹缓存（变更检测用） |
| `.ts_lock` / `.ts_debounce` / `.ts_tmp` | 运行时锁与临时文件 |

> 日志缓冲不放在后端目录，而是固定在 `/data/adb/ts_auto.log`（权限 `600`，仅 root 可读；超过 64KB 自动只保留末尾 200 行；卸载时自动删除）。

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

## 🔄 更新亮点（v2.2.19.4-yuzu）

- **新增 TEE Simulator 后端**：按模块 id `teesim` 探测，仅替换 `config.json` 中 `profiles.default.apps`，其余字段与其它 profile 原样保留。
- **后端冲突即停止**：Tricky Store 与 TEE Simulator 同时启用时模块停止运行，并把状态写入模块描述（`⛔`）。
- **常驻列表支持注释**：`rules.txt` 支持 `#` 中文注释与空行；同步前自动补齐末行换行、清除 UTF-8 BOM，避免包名被污染。
- **写入失败可见**：写入失败会标注到模块描述（`⚠️`），手动同步退出码为 `1`，不再“显示正常但其实没写进去”。
- **监听修复**：修正 inotify 探测方式（busybox 设备不再被误判为“无 inotify 工具”）与 `inotifyd` 事件的读取方式。
- **日志双写 + 本地缓冲**：日志除写入 `logcat` 外，另写 `/data/adb/ts_auto.log`（带时间戳，超 64KB 只保留末尾 200 行），解决 `logcat` 环形缓冲被系统刷掉后查不到记录的问题。
- **省电稳定**：无后台联网轮询；单进程 inotify 监听；内容指纹比对，仅在数据真实变化时同步。
- **属性伪装提前**：`apply_resetprop` 在 `post-fs-data.sh`（Zygote 前）执行，修复 `Build.TYPE` 检测。

更早的 2.x 改动（移除安全补丁、`taa_sys.txt` 更名 `rules.txt`、日志改系统日志、模块结构分层等）见 `CHANGELOG.md` 的 `v2.0.97.2-yuzu` / `v2.1.08.3-yuzu` 条目。

详细变更请参阅模块根目录下的 `CHANGELOG.md`。

---

## ❓ 常见问题

**Q：怎么看模块日志？为什么 logcat 里一会儿就没了？**  
A：日志同时写 `logcat`（tag `TS-AUTO`）与本地缓冲 `/data/adb/ts_auto.log`。`logcat` 的缓冲默认只有几百 KB 且由全系统共用，系统繁忙时旧记录很快被挤掉、重启即清空 —— 这正是“一会儿就没了”的原因；缓冲文件跨重启保留，排查请优先看它（超过 64KB 会自动只保留末尾 200 行）。设备上读这两处**都需要 root**（`/data/adb` 为 `0700`，终端里先 `su`，或用 `su -c '...'`）；电脑上 `adb logcat -s TS-AUTO` 不需要 root，读缓冲文件需要 `adb shell su -c '...'`。最省事的方式是在管理器里点模块的“操作”按钮 —— `action.sh` 会附带打印最近 15 条日志。完整命令与排查步骤见上方「🛠 使用方法 → 查看运行状态」。另外模块只在**开机**与**文件变化**时写日志，没有事件时没有输出属正常现象。

**Q：安装时提示“未找到 inotify 工具”？**  
A：请确认系统是否包含 `inotifywait` 或 `inotifyd`。部分精简 ROM 可能缺失，可尝试安装 Busybox 或更换 ROM（Magisk / KernelSU / APatch 自带的 busybox 会被自动识别）。

**Q：模块描述显示“模块已停止”？**  
A：说明 Tricky Store 与 TEE Simulator 同时启用。停用或卸载其中一个后重启即可恢复。

**Q：模块描述显示“写入失败”？**  
A：目标文件不可写（目录只读、文件被占用等）。检查对应后端目录的权限后重试（执行 `action.sh` 或等待下次事件触发）。

**Q：`target.txt` 未按预期更新？**  
A：先看本地缓冲 `tail -n 50 /data/adb/ts_auto.log`（或 `logcat -d -s TS-AUTO`）里的错误信息；确认 `pm` 命令可用；尝试手动执行 `action.sh` 测试。

**Q：如何临时禁用后台监听？**  
A：可删除后端目录下的 `.ts_daemon_pids.list` 并重启，或直接卸载模块。

---

## 📝 许可证

本模块遵循 **GPL-3.0** 开源协议，欢迎贡献代码与反馈问题。

---

**版本**：v2.2.19.4-yuzu  
**更新日期**：2026-09-13  
**维护者**：IamCanincan
