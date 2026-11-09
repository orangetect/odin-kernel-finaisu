# odin-kernel-finaisu

> 小米 MIX 4（odin / SM8350-AC）5.4 非 GKI 内核，内置 [FinaSU](https://github.com/LyraVoid/FinaSU)。
>
> 本仓库由 [cvbyisme/venus-kernel-finaisu](https://github.com/cvbyisme/venus-kernel-finaisu)（小米 11 / venus）移植而来，
> 内核源改为 [Inkypen79/kernel_xiaomi_odin](https://github.com/Inkypen79/kernel_xiaomi_odin)（默认 `resukisu` 分支），
> 机型配置参考 [Inkypen79/device_xiaomi_odin](https://github.com/Inkypen79/device_xiaomi_odin)。
>
> ⚠️ **本移植尚未在 MIX 4 实机上验证**。脚本与补丁只做了静态/离线验证（见文末「验证状态」），刷机风险自负。

---

## 目标设备

| 项 | 值 |
|---|---|
| 机型 | Xiaomi MIX 4（odin / 2106118C） |
| SoC | Snapdragon 888+ / SM8350-AC（lahaina 平台） |
| 内核基线 | Linux 5.4.302（`Inkypen79/kernel_xiaomi_odin`，默认 `resukisu` 分支） |
| 设备树基线 | `Inkypen79/device_xiaomi_odin`（LineageOS 23.2 分支） |
| 内核配置 | `arch/arm64/configs/odin_defconfig` |
| 分区 | A/B，`boot` + 独立 `dtbo` + `vendor_boot`；boot header v3 |
| 工具链 | ZyCromerZ Clang 14.0.6 |
| 内核类型 | **非 GKI**，vendor 树（`TARGET_KERNEL_SOURCE := kernel/xiaomi/odin`） |

### 为什么默认用 `resukisu` 分支

`lineage-24.0`（默认分支）是干净树，没有 KernelSU/SUSFS 的调用点；
`resukisu` 分支已经把 SUSFS v2.1.0 源码（`fs/susfs.c`、`include/linux/susfs*.h`）和
ReSukiSU 时代的 `ksu_handle_*` 调用点集成进内核，正好对应 venus 仓库所依赖的树形态。
CI 会把该分支里的 `KernelSU/` 子模块整体替换成 FinaSU，`drivers/kernelsu -> ../KernelSU/kernel`
符号链接仍然有效。

> `susfs` / `sukisu` 分支也带 SUSFS，但默认只维护 `resukisu`；需要时可在 workflow 里改 `kernel_ref` 输入。

---

## 快速开始

1. 到 **Actions** 手动运行 `Build odin kernel with FinaSU (SUSFS on, preflight v2)`（即 `build-susfs.yml`）
2. 下载 artifact `odin-finaus-kernel`，或直接取 Release 里的 `odin-FinaSU-*.zip`
3. 进 **TWRP** 刷入（或支持 AnyKernel3 的内核刷写 App）
4. 重启，打开 **FinaSU v1.5.0** 管理器 —— 首屏显示「工作中」即完成

**管理器版本要对上**：内核编入的是 FinaSU v1.5.0 的管理器签名与协议版本，
管理器 APK 与内核不匹配时会表现为「不识别 / 只读」。

**确认刷的是自编内核**：`uname -r` 形如 `5.4.302-Neko-CL-g<hash>`；
若仍是原厂 `5.4.x-qgki-...`，说明 boot 没刷进去。

### 刷机前

- 备份原厂 `boot.img`（有 TWRP 就备份 `boot_a`；A/B 机型注意当前 slot）
- 本包只写 **boot**，不改 `dtbo` / `vendor_boot`
- 首次刷建议准备好可进入的 TWRP 或原厂 boot，方便回滚

---

## 相对 venus 仓库改了什么

| 项 | venus（小米 11） | odin（MIX 4，本仓库） |
|---|---|---|
| 内核仓库 | `cvbyisme/android_kernel_xiaomi_sm8350_miyume` | `Inkypen79/kernel_xiaomi_odin` |
| 默认分支 | `main` | `resukisu`（已含 SUSFS + KSU hook） |
| defconfig | `venus_defconfig` | `odin_defconfig` |
| AnyKernel3 设备名 | `venus` | `odin` |
| 分区 | boot | boot（A/B，`IS_SLOT_DEVICE=1`） |
| devpts hook | 树里有 `ksu_handle_devpts` 调用点 → 需要 stub | **树里没有** → preflight/susfs-setup 自动跳过该步骤 |
| PELT 补丁 | 针对 miyume 的 schedutil 生成 | 按 odin 的 `cpufreq_schedutil.c` 重新生成（见下） |
| dtbs | 构建 `dtbs` | 不构建 dtbs（boot 内 DTB 由原机 boot 保留，dtbo 不动） |
| 产物命名 | `venus-*` | `odin-*` |

### PELT 补丁为什么必须重做

venus 的 `pelt-force.patch` 是针对 miyume 树的 `schedutil` 生成的，直接套到 odin 树会在
`get_next_freq()` 处失败：odin 的 `get_next_freq()` 已经在没有 vendor hook 时使用
`map_util_freq()`，不需要 venus 补丁里的那一段。

本仓库的 `scripts/sched-patches/pelt-force.patch` 只做两件事：

1. `use_pelt()` 在 `CONFIG_SCHED_WALT=y` 时返回可运行时控制的 `sugov_force_pelt`（默认 1）；
2. `sugov_get_util()` 在 `use_pelt()` 为真时走 PELT（`cpu_util_cfs()` + `schedutil_cpu_util()`），
   不再走 WALT util 路径。

这与 venus 的结论一致：**WALT 调度器保留（任务放置 / boost 不变），只把 schedutil 的 util 信号源换成 PELT**。

另外两个补丁（`s1-input-boost-off.patch`、`s2-io-is-busy-off.patch`）可以直接套用 odin 树，
已用 `git apply --check` 验证。

---

## 核心实现（沿用 venus 方案）

### 一、头文件法：5.4 兼容层

FinaSU 基线面向 5.10+，5.4 vendor 树缺头文件与 API。`scripts/preflight.sh` 负责：

- 生成 `include/linux/{pgtable,minmax,hex}.h` 壳
- 安装 `include/linux/ksu54_compat.h`（`TWA_*`、`*_user_nofault`、`untagged_addr()` 等）
- 通过 `KernelSU/kernel/Kbuild` 的 `ccflags-y += -include ...` 全局注入，**不改内核源文件**
- 处理 preinit / devpts / kernel_umount / SELinux 的 5.4 差异

> odin 树没有 `fs/devpts/inode.c` 的 `ksu_handle_devpts` 调用点，因此
> `susfs-setup.sh` step 8 与 `preflight.sh` 的 devpts stub 会自动跳过；
> 这不会降低功能，只是少一个 5.4 上的已知死代码。

### 二、SUSFS 版本对齐

`resukisu` 分支自带 **SUSFS v2.1.0** 源码；FinaSU v1.5.0 的 ksud 要求内核汇报
`v2.3.0`，否则判定 `unknown_protocol`（SUSFS 页只读）。`scripts/susfs-version.sh`
把版本字符串改成 `v2.3.0`，并修正 `KSTAT_SPOOF_CTIME_TV_SEC (1 < 8)` 笔误。
两者用户态协议（`CMD_SUSFS_*`、`st_susfs_*` 结构）一致。

### 三、uname procfs 伪装

`scripts/susfs-uname-proc.sh` 让 `/proc/version` 与
`/proc/sys/kernel/{osrelease,version}` 也走 SUSFS 的 uname 缓冲，
与 `uname(2)` 的伪装值保持一致（odin 的 `fs/proc/version.c` 与
`kernel/utsname_sysctl.c` 锚点已实测匹配）。

### 四、ksud 处理

- 默认 `embed_ksud=true`：从 FinaSU v1.5.0 APK 抽 `libksud.so`，AK3 刷入时覆盖
  设备上的 `/data/adb/ksud`，避免旧 ksud 与新管理器版本不匹配导致的后台重试耗电；
- `embed_ksud=false`：删除设备旧版，由管理器首次启动自行安装；
- 内核侧 `scripts/ksu-su-fallback.sh` 在 ksud 缺失时把 `su` 指向 `/system/bin/sh`，保证首次刷入能拿到 root shell。

### 五、功耗调优

| 组件 | 文件 | 作用 |
|---|---|---|
| 默认 governor | `scripts/power-tune.sh` | 把 `odin_defconfig` 的 `performance` 改为 `schedutil` |
| PELT 修复 | `scripts/sched-patches/pelt-force.patch` | schedutil 强制 PELT util 路径（必需） |
| 输入提升 | `scripts/sched-patches/s1-input-boost-off.patch` | `cpu-boost` 输入提升默认关 |
| IO 推频 | `scripts/sched-patches/s2-io-is-busy-off.patch` | WALT `io_is_busy` 默认 0 |

`scripts/sched-tune.sh` 在克隆内核后应用补丁，带幂等与 `git apply --check` 门禁，
内核树漂移时会显式失败而不是静默跳过。

> MIX 4 与小米 11 同属 SM8350 家族，WALT util 路径在早期启动时的风险相同，
> 因此沿用「schedutil + 强制 PELT」的组合。**这是移植假设，不是 MIX 4 实测结论。**

---

## 构建

所有 workflow 都是 `workflow_dispatch` 手动触发。

| 文件 | 作用 |
|---|---|
| `build-susfs.yml` | **主线**：FinaSU v1.5.0 + SUSFS + preflight v2 + 功耗调优 + 默认内嵌 ksud；发布 `odin-test-<n>` |
| `pure.yml` | 不含 root/SUSFS 的纯内核，用于排查基线 / 工具链 / 模块 vermagic |
| `pack.yml` / `pack-pure.yml` | 对已有 run 的 artifact 重新打 AnyKernel3 包 |
| `build.yml` / `fix.yml` / `fix-v121.yml` | 上游历史构建线，保留作参考（仍按 odin 配置运行） |

主线的关键步骤：

```text
clone kernel (resukisu) → sched-tune → 克隆 FinaSU 覆盖 KernelSU/
→ susfs-setup → susfs-version → susfs-uname-proc → preflight
→ ksu-su-fallback → clang 14.0.6 构建 odin_defconfig
→ 配置门禁 (KSU/SUSFS/KPROBES) → Image + Image.gz
→ AnyKernel3 (device=odin, BLOCK=/dev/block/bootdevice/by-name/boot)
```

### 常用输入

- `kernel_repo` / `kernel_ref`：默认 `Inkypen79/kernel_xiaomi_odin` / `resukisu`
- `ksu_ref`：FinaSU ref，默认 `v1.5.0`
- `disable_preinit` / `disable_susfs`：诊断开关（二分卡开机 / 卡 logo）
- `embed_ksud`：是否在 AK3 内嵌匹配版本的 ksud（默认 true）

### 脚本

| 文件 | 作用 |
|---|---|
| `scripts/preflight.sh` | 5.4 兼容层施工与验证 |
| `scripts/ksu54-compat.h` | 兼容头本体（`-include` 全局注入） |
| `scripts/susfs-setup.sh` | 把 SUSFS 接进 FinaSU 与内核树（5.4 适配） |
| `scripts/susfs-version.sh` | SUSFS 版本对齐到 v2.3.0 协议 |
| `scripts/susfs-uname-proc.sh` | `/proc/version` 与 osrelease 的 uname 伪装 |
| `scripts/power-tune.sh` | 默认 governor 改 `schedutil` |
| `scripts/sched-tune.sh` | 应用 `sched-patches/*.patch` |
| `scripts/ak3-ksud.sh` | AK3 内嵌 / 清理 ksud |
| `scripts/ksu-su-fallback.sh` | 内核侧 su fallback |
| `scripts/odin-selftest.sh` | 刷完自检（PASS/WARN/FAIL 表） |
| `scripts/collect-logs.sh` | 一键收集日志打包 zip |

> CI 里 `actions/checkout` 使用 `path: ci`，所以脚本路径是 `ci/scripts/*`。

---

## 刷完自检

```sh
curl -sL -o /sdcard/Download/odin-selftest.sh \
  https://raw.githubusercontent.com/<你的账号>/odin-kernel-finaisu/main/scripts/odin-selftest.sh
su -c 'sh /sdcard/Download/odin-selftest.sh'
```

检查项与 venus 版一致：内核身份、FinaSU feature、SELinux 域、三簇 governor、
input_boost / io_is_busy、zram、电池、安全补丁、模块、dmesg 异常、boot 备份。
报告落在 `/sdcard/Download/odin-selftest-<时间>.txt`。

想收集日志给别人排错：

```sh
su -c 'sh /sdcard/Download/collect-logs.sh'
# 产物 /sdcard/Download/odin-logs-<时间>.zip
```

---

## 风险与限制

- **未在 MIX 4 实机验证**：本仓库只完成静态验证（补丁可应用、脚本可在 odin 树跑通、配置门禁符号存在）。
- **ROM 依赖**：内核与 ROM 的 vendor / dtbo 强相关。设备树基线是 LineageOS 23.2；跨大版本 ROM 升级后可能需要重刷或回退。
- **boot header v3**：AK3 只替换 boot 里的 kernel，保留原机 DTB 与 ramdisk；`dtbo` 分区不动。
  如果 ROM 的 dtbo 与内核版本不匹配，可能出现相机 / 显示异常，需刷回原厂 boot。
- **SUSFS 协议**：内核汇报 v2.3.0，但内核实现是 v2.1.0；FinaSU v1.5.0 管理器的 SUSFS 页应可读写。
- **历史 workflow** 里的 v1.2.1 签名 / 管理器组合仅作参考，不要与主线 v1.5.0 混用。

---

## 验证状态（本仓库迁移时做过什么）

已在本地对 `Inkypen79/kernel_xiaomi_odin@resukisu` 的相关文件做离线验证：

| 项 | 结果 |
|---|---|
| `s1-input-boost-off.patch` / `s2-io-is-busy-off.patch` / `pelt-force.patch` | `git apply --check` 通过（resukisu 与 lineage-24.0 两棵树） |
| `susfs-setup.sh`（v2.1.0 树） | 在 odin 文件集上跑通，SUSFS 别名 / SELinux / mount / uname 步骤全部完成 |
| `susfs-version.sh` | v2.1.0 → v2.3.0、ctime 笔误修正通过 |
| `susfs-uname-proc.sh` | `fs/proc/version.c`、`kernel/utsname_sysctl.c` 锚点匹配 |
| `preflight.sh` | 全部检查 PASS；devpts 步骤因 odin 树无调用点而按预期 SKIP |
| `ksu-su-fallback.sh` | `sucompat.c` 锚点匹配，补丁成功 |
| `odin_defconfig` | `KSU=y`、`KSU_SUSFS*`、`KPROBES`、`EXT4_FS`、`THREAD_INFO_IN_TASK`、`OVERLAY_FS`、`MODULES` 均存在 |
| workflow YAML | `python -c yaml.safe_load` 语法检查通过 |

**没有做**：完整内核编译（本机无 Linux 工具链）与 MIX 4 实机刷入。

---

## 参考

- [cvbyisme/venus-kernel-finaisu](https://github.com/cvbyisme/venus-kernel-finaisu) —— 本仓库的直接来源
- [Inkypen79/kernel_xiaomi_odin](https://github.com/Inkypen79/kernel_xiaomi_odin) —— 内核源（5.4.302，LA.UM.9.14.r1-26500）
- [Inkypen79/device_xiaomi_odin](https://github.com/Inkypen79/device_xiaomi_odin) —— MIX 4 设备树（LineageOS 23.2）
- [LyraVoid/FinaSU](https://github.com/LyraVoid/FinaSU) —— root 方案
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) —— SUSFS
- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) —— 刷机包模板

## License

见 [LICENSE](LICENSE)。
