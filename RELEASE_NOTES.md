# 🚀 TS-AUTO-ADD v2.2.19.4-yuzu

### 📋 核心变更摘要

本次更新**以修复问题和提升稳定性为主**：修复了上一版遗留的四处缺陷（常驻列表粘连、写入失败被误报成功、inotify 探测错误、`inotifyd` 监听失效），并将**后端判定改为按模块 id 进行**、两个后端同时启用时**模块直接停止**且把原因写入模块描述。此外，日志改为 **logcat + 本地缓冲双写**（解决 `logcat` 记录很快被覆盖丢失的问题），`rules.txt` 支持 `#` 注释。

---

### ✨ 新增

#### 🧩 TEE Simulator 后端（按模块 id 判定）
- 判定依据改为 `/data/adb/modules` 下的模块 id：`tricky_store`（Tricky Store / OSS）与 `teesim`（TEE Simulator）；带 `disable` 标记的模块不计入。
- TEE Simulator 模式下**只替换 `/data/adb/teesim/config.json` 的 `profiles.default.apps`**：`keybox` / `mode` / `patchLevel` / 设备信息等字段，以及**其它 profile（如 `ccc`）均逐字节保留**。
- 定点替换由 `backends/teesim.awk` 完成，**无法可靠定位数组时放弃写入**，不会写坏配置；替换后内容与原来一致则不落盘。
- 两个后端**同时启用时模块直接停止**（不再做优先级选择）。

#### 📝 常驻列表支持注释
- `rules.txt` 支持以 `#` 开头的注释行与空行；默认内容自带中文说明注释。
- 同步前自动**补齐末行换行**、**清除 UTF-8 BOM**，避免包名被污染。

#### 📜 本地日志缓冲
- 除写入 `logcat`（tag 为 `TS-AUTO`）外，日志还会写入 `/data/adb/ts_auto.log`，每行带 `月-日 时:分:秒` 时间戳。
- 缓冲有固定上限：超过 64KB 时自动只保留末尾 200 行，不会无限增长；裁剪采用「先写临时文件、成功后再覆盖」的方式，不会因裁剪失败而丢日志。
- 文件权限为 `600`，且位于 `0700` 的 `/data/adb` 下，**仅 root 可读**，其它应用无法访问（旧版本放在 `/data/local/tmp`，该目录所有应用可读）。
- 之所以要加缓冲：`logcat` 是内存环形缓冲（默认几百 KB，且由全系统共用），系统繁忙时旧记录很快被挤掉、重启即清空，事后排查往往已经看不到；缓冲文件则可跨重启保留。
- 缓冲文件不可写时静默退化为只写 `logcat`，不影响同步流程。
- 管理器的“操作”按钮**优先展示缓冲内容**，安装完成时会打印日志路径；卸载时缓冲文件随模块一并删除。

#### 📣 状态写入模块描述
- 运行状态直接写进 `description`：正常 `✅ [… ]`、写入失败 `⚠️ [… 写入失败 …]`、后端冲突 `⛔ [模块已停止 …]`，不看日志也能在管理器界面看到原因。

---

### 🐛 修复

- **常驻列表末行无换行导致粘连**：用 `echo 包名 >> rules.txt` 追加的包名不再与上一行粘连（同步前自动补齐末行换行）；文件开头的 UTF-8 BOM 也会被清除。
- **写入失败被误报成功**：`target.txt` 替换失败（目录只读、文件被占用等）时如实返回失败 —— 描述标注 `⚠️`、手动同步退出码 `1`。
- **inotify 探测方式错误**：原先探测 busybox 时执行的是 `busybox --help`（不含 applet 帮助），导致仅装有 busybox 的设备被误判为“无 inotify 工具”而直接退出；现改为实际执行 applet 的 `--help`。
- **`inotifyd` 监听失效**：`inotifyd PROG FILE:mask` 会把 `PROG` 当作程序执行，原先传 `-` 不会产生任何输出；现改用 `echo` 打印事件，再由管道读取。

---

### ⚡ 优化

#### ➕ 日志改为双写（logcat + 本地缓冲）
- 日志同时写入 `logcat`（tag 为 `TS-AUTO`）与 `/data/adb/ts_auto.log`（超过 64KB 时只保留末尾 200 行），不再只依赖随时可能被系统刷掉的内存日志。
- 最省事的方式是在管理器里点模块的“操作”按钮 —— `action.sh` 会同步一次，并**附带打印最近 15 条日志**（管理器以 root 运行，无需自己 `su`）。
- 设备上手动查看（`/data/adb` 为 `0700`，**需要 root**；在终端 App 里先 `su`，或把命令写成 `su -c '...'`）：

  ```bash
  tail -n 50 /data/adb/ts_auto.log                      # 本地缓冲，跨重启保留（推荐）
  grep -E '后端|同步|失败|停止' /data/adb/ts_auto.log    # 只看关键行
  logcat -d -s TS-AUTO | tail -n 30                     # 系统日志（重启即清空）
  logcat -s TS-AUTO                                     # 实时跟随
  ```

- 电脑上查看（用 `adb` 读 `logcat` 不需要 root，读 `/data/adb` 下的文件则需要）：

  ```bash
  adb logcat -s TS-AUTO                                        # 实时查看系统日志
  adb shell su -c 'tail -n 50 /data/adb/ts_auto.log'           # 读本地缓冲
  adb shell su -c 'cat /data/adb/ts_auto.log' > ts_auto_log.txt   # 导出到电脑
  ```

#### 🧹 模块结构分类
- 文件分为三类：入口脚本（模块根目录）、`lib/` 共享库、`backends/` 后端实现。
- `lib/` 按功能拆分：`core`（常量/状态/日志）、`lock`、`tools`、`applist`、`backend`、`props`，由 `common.sh` 统一加载；后端实现各自独立成文件（`backends/tricky.sh` 写 `target.txt`、`backends/teesim.awk` 改 `config.json`）。

#### 📐 代码规范化
- 统一中文注释与函数文档格式（说明 / 用法 / 返回码）；界面与日志加入 `✅` / `⚠️` / `❌` / `⛔` 状态标记，便于快速分辨。
- 新增 `.gitattributes` 将脚本与文本文件固定为 LF，避免因 CRLF 导致 Android 上 shebang 失效（`/system/bin/sh^M: not found`）；CI 增加 `sh -n` 语法检查，语法检查不通过的代码不会被打包。

#### 🕐 属性伪装仍在开机早期执行
- `apply_resetprop` 在 `post-fs-data.sh`（Zygote 启动前）执行，在 `Build.TYPE` / `Build.TAGS` 等静态字段取值前即已生效，修复了这些字段显示为 `userdebug` 的问题。

#### 🔋 省电与稳定
- 无任何后台联网轮询；单进程同时监听 `packages.list` 与 `rules.txt`；2 秒防抖合并短时触发；通过内容指纹比对，仅在数据真实变化时同步。
- 日志只在开机与文件变化时写入（无事件不写），缓冲裁剪也只在超限时发生，不引入常驻开销。

---

### 🗑️ 移除

- **全局可读的临时日志**：不再产生 `/data/local/tmp/ts_auto.log`（该目录所有应用可读，存在被检测的风险）；升级与卸载时会清理遗留文件。
- **安全补丁功能**：不读取、不生成、不修改 `security_patch.txt`。
- **周期联网任务**：无后台定时拉取。

---

### 📥 安装与操作指南

| 项目 | 说明 |
|------|------|
| 支持环境 | **Tricky Store / Tricky Store OSS / TEE Simulator**，配合 Magisk / KernelSU / APatch |
| 部署 | 刷入 ZIP 后重启 |
| 手动同步 | `sh /data/adb/modules/ts-auto-add/action.sh` |
| 状态查看 | 模块描述：`✅ [后端 \| 应用: X \| 更新: HH:MM]` |
| 日志 | 管理器“操作”按钮；`tail -n 50 /data/adb/ts_auto.log`（需 root）或 `logcat -d -s TS-AUTO`（电脑 `adb logcat -s TS-AUTO`） |

### 📁 数据文件路径

| 后端 | 判定（模块 id） | 维护目标 | 常驻列表 |
|------|------------------|----------|----------|
| TEE Simulator | `teesim` | `/data/adb/teesim/config.json`（仅 `profiles.default.apps`） | `/data/adb/teesim/rules.txt` |
| Tricky Store / OSS | `tricky_store` | `/data/adb/tricky_store/target.txt` | `/data/adb/tricky_store/rules.txt` |

运行文件（位于当前后端目录下）：

| 文件 | 说明 |
|------|------|
| `.ts_daemon_pids.list` | 后台子进程 PID 列表 |
| `.ts_fingerprint` | 变更检测指纹缓存 |
| `.ts_lock` / `.ts_debounce` / `.ts_tmp` | 运行时锁 / 临时文件 |

日志缓冲固定存放在 `/data/adb/ts_auto.log`（**不在后端目录**；权限 `600`、仅 root 可读，超过 64KB 时只保留末尾 200 行，卸载时删除）。

### ⚠️ 注意事项
- **两个后端不要同时启用**：同时启用时模块直接停止，描述显示 `⛔ [模块已停止 …]`；停用或卸载其中一个后重启即可恢复。
- TEE Simulator 模式需要 `awk`（系统自带或框架 busybox）；缺失时模块会放弃写入配置并记录日志，装上 busybox 后会在下次同步时自动重试。
- 首次安装后请重启设备；编辑 `rules.txt` 会自动触发同步，无需重启。
- 排查问题请**优先查看本地缓冲** `/data/adb/ts_auto.log`：`logcat` 中的记录可能已经被系统挤掉。
- 如需禁用属性重置：编辑 `post-fs-data.sh`，注释掉 `apply_resetprop` 后重启。
- 卸载时只删除本模块自身的文件（含日志缓冲），`target.txt` / `config.json` 保持不动。

---

> 💡 **提示**：本版以修复问题为主，建议所有用户更新；升级后无需改动任何现有配置。

**版本**：v2.2.19.4-yuzu ｜ **更新日期**：2026-09-13
