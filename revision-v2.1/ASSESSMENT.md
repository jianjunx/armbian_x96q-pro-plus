# 真机反馈与升级评估：2026-09-09

依据用户提供的 `h728-diagnostics.txt`（报告时间 2026-09-08 21:48），仅把日志作为观测数据，未执行其中的内容。原始日志含网络地址与登录记录，不纳入仓库。

## 已确认的情况

| 项目 | 证据与判断 |
| --- | --- |
| SD 启动 | v2 成功进入系统并完成 SSH 登录。 |
| CPU | 0–7 全部在线；cpufreq-dt 暴露 policy0、policy4 两组调频域。lscpu 的缓存/cluster 显示不完整，不等于缺少 CPU 核心。 |
| 有线网 | end0 获得 DHCP 地址，1000 Mbps/full duplex，carrier=1。 |
| USB | USB2、USB3 root hub 已注册；报告没有外接设备，未验证传输或供电。 |
| Wi-Fi | SDIO 枚举 c8a1:0082/0182，aic8800 驱动开始初始化，读取 fw_patch_table_8800d80_u02.bin 时找不到文件，随后断电退出。当前第一阻塞点是固件，而非缺少 SDIO 设备或驱动。 |
| 温度 | CPU4 47.402°C、CPU0 45.848°C、GPU 45.848°C、DDR 47.550°C。没有同步负载/室温记录，不能推定持续空载异常。 |
| 调频 | 两组 governor 均为 performance，分别处于 1.416/1.8 GHz。v2 的 cpufrequtils 中 GOVERNOR/MIN_SPEED/MAX_SPEED 均为空，因此沿用内核默认 performance。 |

v2.1 安装器补齐作者原配套固件、设置 schedutil 和 408 MHz 最低频率，保持原最高频率限制。Armbian 现有 hardware-optimize 服务在启动时读取该配置；运行时立即应用，Wi-Fi 留待用户主动重启后重新初始化。新增诊断项包含负载、可用调频器、频率限制、cpuidle 与 SDIO 信息。

原始参考 DTB 没有显式 idle-states/cpu-idle-states 描述；仅凭这一点不能判断实际 WFI/PSCI 空闲能力。应先观察 schedutil 的温度收益，再依据 cpuidle 驱动与状态计数评估深度空闲；不猜测 PSCI state 编号或修改电压表。

## 较新内核

从作者的[下载目录](https://drive.google.com/drive/folders/1hAr_PB52fIBcZOgtx2WoGghv63H1-JzB) 下载了：

`reference-packages/linux-sunxi-7.2-7-aarch64.pkg.tar.xz`

- [具体文件](https://drive.google.com/file/d/1JitJsAmebTWXNIlwhJ_Z5p5pxqUnNqTW/view)
- SHA-256：`b45281c8ab874587f85e0d6926273a79f88f8ab637c46b3a67616f1f60d5aa1d`
- 模块目录版本：`7.2.0-7-MANJARO-ARM`；从 Image 提取的配置为 Linux/arm64 7.2.0-7，版本不含 rc。
- 包含 X96Q Pro+ 常规和 BSP 两种 DTB。常规 DTB 有 8 CPU、两组 OPP，启用 GMAC1、SDIO 和 USB3；还启用了显示相关节点，不能据此宣布 HDMI 已可用。
- 配置包含 DWMAC_SUN55I=m、PHY_SUN55I_USB3_PCIE=y、AIC8800_WLAN_SUPPORT=m；AIC 固件目录仍为 `/usr/lib/firmware/aic8800_sdio`。
- 默认 governor 仍为 performance；升级内核本身不会自动完成本次节能修正。
- 模块依旧采用 `.ko.gz`；在 Debian 上重新打包时须继续处理压缩兼容、depmod 和 initramfs。

此包已下载、解包和静态审查。本评估之后，它已被成套集成为 `revision-v3/` 的可烧录镜像，且通过离线一致性检查；**v3 尚未真机启动**。不能直接将 Manjaro 的 pacman 包交给 apt 安装，也不能单独替换 Image。后续应在 SD 卡上验证网卡、USB、Wi-Fi 与 DVFS，继续保留 v2 作为回退基线。

## Debian 13 Trixie

可以使用 Trixie 用户空间；Debian 用户空间版本与 H728 板级内核版本是不同层次，升级用户空间不会补齐 Wi-Fi 固件或自动完成设备树适配。本地 Armbian 框架包含 Trixie 支持，Armbian 仓库也提供 Trixie suite。

针对本项目，建议制作单独的 Trixie 测试镜像，先复用已验证的启动链和修复后的固件/调频配置，再逐项验证新内核。直接更换现有盒子的软件源并 full-upgrade 会把用户空间和硬件支持的变更混在一次测试里；这里没有执行这种升级。

Armbian 官方将 Bookworm → Trixie 这类原地升级列为实验且不支持，建议新镜像；参见[升级说明](https://docs.armbian.com/getting-started/updating/)和[发行版升级功能](https://docs.armbian.com/config/updates/)。国内源偏好继续使用清华或科大，Debian security 仓库也要使用对应的 trixie-security。

当前交付已包括可在 v2 上安装的 Wi-Fi/调频修复包，以及后续完成的 Trixie/7.2 v3 镜像。v3 的构建和测试状态以 `revision-v3/README.md` 为准。
