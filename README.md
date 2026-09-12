# Armbian for X96Q Pro+ (Allwinner H728)

本项目为 X96Q Pro+ 电视盒子构建实验性 Armbian 镜像，目标是提供可从 SD 卡启动、可通过 SSH 管理，并支持八核 CPU、千兆以太网、USB、AIC8800D80 Wi-Fi 和可选 eMMC 安装的 Debian 系统。

设备仍处于主线 Linux 支持早期阶段。项目采用 Armbian 用户空间与构建框架，并将论坛作者提供的配套内核、模块和设备树重新打包；当前内核不是由本仓库从完整对应源码构建。请将本项目视为硬件适配和验证工程，而不是官方 Armbian 板卡支持。

## 当前状态

最新镜像已发布：[v3.1.1-ci.6.1](https://github.com/jianjunx/armbian_x96q-pro-plus/releases/tag/v3.1.1-ci.6.1)。
Actions [34678002094](https://github.com/jianjunx/armbian_x96q-pro-plus/actions/runs/34678002094)
从 `c0c117f` 构建、离线校验并上传全部 8 个文件成功。下载文件名含
`v3.1.1_SD.img.xz`；使用同一 Release 的 SHA256SUMS。新镜像需烧录复测。

2026-09-12：构建目标更新为 v3.1.1，固化 Wi-Fi SDIO 24 MHz 上限（实际约
22.22 MHz），内核包修订 +h728.5，保留 20 MHz 回退 DTB。现有系统已通过
三次冷启动和双向各 5 分钟传输（下载 64.3 / 上传 66.0 Mbit/s）；新镜像
需另行实测。下方 v3.1 下载链接与哈希仍指向保留的旧版。

2026-09-10：新完整 SD 镜像开发转入 [revision-v3.1](revision-v3.1/README.md)。
默认运行 SD 根系统，保留盒子现有 eMMC，不自动迁移。v3 修正后已验证
SD 启动和 SD 引导/eMMC 根系统的 SSH、千兆网络；独立 eMMC 启动仍失败。
这些真机结果更新了下表的早期状态，但不能替代 v3.1 镜像实测。

| 版本 | 用户空间 / 内核 | 状态 |
| --- | --- | --- |
| v3.1 | Debian 13 Trixie / `7.2.0-7-MANJARO-ARM` | 完整 SD 修复镜像，离线校验通过，待新镜像真机复测；禁用 eMMC 安装 |
| v3 | Debian 13 Trixie / `7.2.0-7-MANJARO-ARM` | 最新测试镜像；已通过离线校验，等待真机验证 |
| v2.1 | v2 上的 Wi-Fi 固件与 `schedutil` 补丁 | 已通过离线安装验证，等待真机验证 |
| v2 | Debian 12 Bookworm / `6.17.0-rc1-2-MANJARO-ARM+` | **真机确认可从 SD 启动**；八核、千兆有线网正常 |
| 初版 | Bookworm / Armbian 6.18.48 | 真机黑屏且无 DHCP；DTB 中 GMAC1、USB3、CPU OPP 配置不完整 |

v2 真机诊断还确认 USB2/USB3 root hub 已注册；当时未插外设，因此没有完成 USB 传输和供电测试。Wi-Fi 的 SDIO 设备与驱动能够初始化，但因固件缺失退出。空载诊断时两组 CPU 采用 `performance` 并处于最高频率，温度约 46–48°C。v2.1/v3 已加入 Wi-Fi 固件和 `schedutil`，实际无线连接、稳定性和降温效果仍需真机复测。

v3 还包含实验性 eMMC 支持：Linux DTB 启用 eMMC 并限制为 52 MHz SDR；独立编译的 eMMC U-Boot 启用 MMC slot 2。eMMC 实际写入和拔卡冷启动尚未验证。

## 获取和使用 v3.1

GitHub Actions 构建的实验性预发布：
[v3.1.0-ci.3.1](https://github.com/jianjunx/armbian_x96q-pro-plus/releases/tag/v3.1.0-ci.3.1)。
下载 `Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1_SD.img.xz` 和
`SHA256SUMS`。压缩包 SHA-256 为
`1f1612822f27a56c034073900599765499488647c9b42ef177a3e747c4ddcad5`；
解压后镜像 SHA-256 为
`57484562bc985bb1c240a963f84a7da327d9ffe9e080e4403026cb4d2a64d4e6`。
对应的 [Actions 运行](https://github.com/jianjunx/armbian_x96q-pro-plus/actions/runs/34463277020)
已完成离线校验。该镜像仍未经过 v3.1 真机启动和外设测试。

本地构建后的镜像路径：

```text
armbian-build/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1_SD.img
```

镜像约 4 GiB，需要至少 8 GB 的 SD 卡。SHA-256：

```text
d9357a2223d29fdfa8373c9a37b35b3384e53edb14013b4b2ae9f086f776f408
```

大文件由 `.gitignore` 排除，不进入 Git 历史。[Actions 构建发布流程](ci/README.md)
会在构建相关代码推送到 `main` 后，自动组装、校验并发布实验性 Release。
固定离线输入已归档到独立的 `build-inputs-v3` 预发布，并经过大小和哈希校验。
CI 每次生成新 UUID，因此本地镜像和 CI 镜像的哈希不同；始终以对应 Release
中的 `SHA256SUMS` 为准。

首次测试建议：

先完整备份现有可用 SD 卡。v3.1 烧录后默认运行全新 SD 系统，不再默认
进入现有 eMMC 根系统；eMMC 内容不迁移、不覆盖。修复范围、诊断和构建流程
见 [v3.1 说明](revision-v3.1/README.md)。后文的 v3 安装/构建说明为历史流程，
不要用旧安装器绕过 v3.1 的 eMMC 安装限制。

1. 将完整 `.img` 写入 SD 卡，并启用写后校验。
2. 盒子断电插卡，连接网线后上电，等待约 2 分钟。
3. 从路由器 DHCP 列表获取地址，使用 `root` / `1234` 登录 SSH，并完成 Armbian 首次登录流程。
4. 先验证有线网和系统稳定性，再检查 Wi-Fi、USB、调频与温度。

参考内核包含显示相关节点，但 v3 的 HDMI 尚未真机确认。首次启动仍以 DHCP、SSH 或 3.3 V UART0（115200/8N1）判断。系统进入用户空间约 60 秒后，会在 FAT 启动分区生成 `h728-diagnostics.txt`。

完整测试、回退和 eMMC 安装步骤见 [revision-v3/README.md](revision-v3/README.md)。eMMC 安装会清空盒子内置存储中的 Android 与用户数据；先运行只读检查：

```sh
sudo h728-install-emmc --check
```

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| `revision-v3/` | Trixie + Linux 7.2 镜像的分阶段构建、校验、Wi-Fi、调频和 eMMC 安装逻辑 |
| `revision-v2.1/` | 可安装到 v2 的 Wi-Fi 固件与调频补丁构建流程 |
| `revision-v2/` | 已真机启动的 v2 镜像重建与离线校验流程 |
| `armbian-patches/` | 对独立 `armbian-build` 上游仓库所做本地改动的可应用补丁 |
| `manjaro-linux-a523/` | 较早的 Manjaro A523/H728 内核配方和补丁快照 |
| `uboot-x96qproplus/` | 论坛作者公开的 X96Q Pro+ U-Boot 配方 |
| `MATERIALS.md` | 物料来源、历史决策、镜像和启动器说明 |
| `SHA256SUMS` | 下载物料和关键构建产物的固定哈希 |
| `source-metadata/` | 用于定位上游物料的公开元数据快照 |

以下本地目录不进入顶层 Git：

- `armbian-build/`：独立的 Armbian 上游 Git 克隆，当前基线为 `474593a`；本地板级提交为 `a486573`。
- `source-archives/`、`reference-packages/`：下载的源码与参考二进制包。
- `build-artifacts/`：构建出的 SD/eMMC U-Boot。
- `armbian-build/output/`、`armbian-build/cache/`：镜像、Deb 包、日志和阶段缓存。

在新的 Armbian 克隆中可应用：

```sh
git am ../armbian-patches/0001-add-x96q-pro-plus-h728-build-support.patch
```

## 构建模型

构建通过具备 loop、mount 和 chroot 权限的 ARM64 Linux 容器完成。现有开发环境使用名为 `h728-image-build` 的特权容器，并把本机 `armbian-build/` 映射为容器中的 `/armbian`。macOS 本身只保存源码和产物，不直接挂载 Linux 镜像分区。

v3 是分阶段流程：

```sh
bash /armbian/cache/h728-v3-input/prepare.sh
bash /armbian/cache/h728-v3-input/build-emmc-uboot.sh
bash /armbian/cache/h728-v3-input/upgrade.sh
bash /armbian/cache/h728-v3-input/finalize.sh
bash /armbian/cache/h728-v3-input/verify.sh
```

- `prepare.sh` 从已验证 v2 镜像复制独立工作镜像、扩容根分区、重打包新内核，并加入 Wi-Fi/调频补丁。
- `build-emmc-uboot.sh` 从固定 U-Boot/TF-A 源码构建 eMMC 专用启动器。
- `upgrade.sh` 将未启动过的 v2 用户空间离线升级为 Trixie，安装配套 Linux 7.2 包。
- `finalize.sh` 写入最终启动配置、诊断工具、首次启动身份处理和 eMMC 安装器。
- `verify.sh` 只读挂载最终镜像，检查文件系统、启动器偏移、内核/模块/DTB、固件、软件包、SSH、UUID 和 eMMC 工具。

各阶段的完整前置物料、容器路径和限制见 [v3 构建与使用文档](revision-v3/README.md)。离线 PASS 只能证明镜像内部一致，不能替代硬件启动和外设测试。

## 关键设计约束

- 内核 `Image`、模块与 DTB 必须来自同一参考包并成套替换，不能只交换 DTB 或单个驱动。
- Manjaro 内核模块为 `.ko.gz`；当前 Debian kmod 不支持这种压缩，重打包时必须解压为 `.ko` 并重新执行 `depmod`、生成 initramfs。
- SD U-Boot 写在镜像 8192 字节偏移。SD 版本沿用已在 v2 真机成功启动的启动器。
- eMMC 启动需要能枚举 MMC2 的专用 U-Boot；只复制根文件系统不足以拔卡启动。
- Trixie 使用清华 Debian、Debian Security 和 Armbian 软件源。板级内核、U-Boot 和 BSP 包保持 hold。
- 后续实验必须产出新文件名，保留 v2 和上一次可启动镜像作为回退。
- 不根据黑屏单独判断启动失败；使用 DHCP、SSH、诊断文件或 UART 证据。

## 下一步

当前最有价值的工作是真机测试 v3：

1. 确认 SD 冷启动、八核、有线网和 SSH。
2. 配置 AIC8800D80 Wi-Fi，验证扫描、关联和持续传输。
3. 分别用低功耗 U 盘测试各 USB 端口及 USB3 速率。
4. 同一室温下静置 10 分钟，记录负载、频率、cpuidle 和各温区，比较 v2。
5. 运行 `h728-install-emmc --check`；确认 SD 系统和 eMMC 识别无误后，再决定是否覆盖 Android。
6. 若 eMMC 安装完成，关机拔 SD 卡测试冷启动，并进行持续读写和断电恢复测试。

发现问题时请保留完整的 `h728-diagnostics.txt`；若系统未能生成该文件，请采集从上电开始的 UART 日志。诊断文件可能包含 IP、MAC 和登录元数据，公开提交前先做脱敏。

## 来源与许可

主要参考为 [Manjaro H728/A523 初始支持帖](https://forum.manjaro.org/t/allwinner-h728-a523-a527-t527-initial-support-thread/173654)、[Armbian build](https://github.com/armbian/build) 和论坛作者公开的内核/U-Boot 物料。详细 URL、版本和哈希见 [MATERIALS.md](MATERIALS.md) 与 [SHA256SUMS](SHA256SUMS)。

AIC8800D80 固件原包的许可字段为 `unknown`。本仓库不提交该固件二进制；重新分发镜像或固件包前，应单独确认授权条件。
