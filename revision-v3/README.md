# X96Q Pro+ H728 v3：Trixie + Linux 7.2

本版在独立镜像中将未启动过的 v2 发行底包离线升级到 Debian 13 Trixie，替换为作者提供的 `7.2.0-7-MANJARO-ARM` 内核、模块和设备树，并集成 Wi-Fi 固件、schedutil 调频及 eMMC 安装工具。未读取或迁移用户盒子里的个人数据。

镜像文件：`../armbian-build/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.img`。
大小 4 GiB，使用至少 8 GB 的 SD 卡。校验值与离线检查记录在镜像同目录。

SHA-256：`46b5720330065a731169f60bab260b0b46a23f8b1ec37e4497e690078ddebfec`。

## 首次启动

1. 将整个 `.img` 写入 SD 卡，启用写后校验。
2. 断电插卡，连接路由器网线，重新上电，等待约 2 分钟。
3. 从 DHCP 列表获取 IP，通过 SSH 登录：用户名 `root`，初始密码 `1234`，按提示修改密码和建立用户。
4. 先验证新内核及网卡，再验证 Wi-Fi、USB 与调频。新参考内核启用了显示相关节点，但 HDMI 未经真机验证，首次仍建议使用网络/串口。

```sh
cat /etc/os-release
uname -r
cat /sys/devices/system/cpu/online
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
ip -br address
iw dev
lsusb -t
sudo /usr/local/sbin/h728-diagnostics
```

预期系统为 Trixie，内核 `7.2.0-7-MANJARO-ARM`，八核在线，调频器为 schedutil。Wi-Fi 固件完整安装在 `/usr/lib/firmware/aic8800_sdio`；已安装 iw、rfkill、wpasupplicant 和 regulatory database，但没有预置无线网络名/密码。

默认按需调频，最低 408 MHz，保留各簇原有最高频率。观察同一环境静置约 10 分钟后的温度；若发生调频相关卡死/重启，可将 `/etc/default/cpufrequtils` 的 GOVERNOR 改为 performance 后重启验证。

每次启动进入用户空间后约 60 秒，启动分区会生成 `h728-diagnostics.txt`，随后周期更新。网络不可用时关机取卡，在电脑读取此文件；若没有文件，需要 3.3 V UART0、115200/8N1 的启动日志。

## 安装到 eMMC

先完成 SD 启动测试并备份盒子安卓和需要保留的数据。新镜像默认只启用 eMMC 控制器，不自动写入内置存储。

只读检测：

```sh
sudo h728-install-emmc --check
```

工具按 MMC 设备类型识别 eMMC，检查当前根目录来自另一张 SD 卡、目标未挂载/未作为 swap 使用/没有活跃设备映射，并进行前 256 MiB 只读测试。读取成功不代表写入或拔卡启动已经验证。

确定要覆盖后运行：

```sh
sudo h728-install-emmc --install
```

脚本会显示设备名和 CID，并要求手动输入包含两者的确认文字。**继续执行会清空 eMMC 用户区的分区和安卓数据**。随后创建 512 MiB FAT 启动分区和 ext4 根分区，进行 64 MiB 文件写入/直接读回校验，复制 SD 上正在运行的系统并重写 UUID，最后在 8 KiB 偏移写入专用 eMMC 启动器。安装不会自动重启。

这是在线文件级迁移，操作前停止数据库、容器等持续写入负载。安装完成后关机、拔 SD 卡，再测试 eMMC 启动。boot0/boot1 和 EXT_CSD 启动配置未更改；不同批次的 ROM/eMMC 启动行为仍须真机验证。若拔卡无法启动，可重新插入 SD 卡恢复访问，提供串口日志；不要反复猜测并更改 EXT_CSD。

eMMC 配置使用与旧版相同的板级电源、8 位总线及复位信号，先限制为 52 MHz SDR，不启用 HS200/DDR 高速时序。专用 U-Boot 开启 `CONFIG_MMC_SUNXI_SLOT_EXTRA=2` 并同样限制 eMMC 时序；SD 卡上的主启动器仍使用此前已成功启动的版本。

若新启用的 eMMC 节点影响 SD 启动，在电脑修改 FAT 分区中的两项设置回到作者原始设备树：

- `extlinux/extlinux.conf`：将 `DEFAULT armbian-h728` 改为 `DEFAULT stock-dtb`。
- `armbianEnv.txt`：将 fdtfile 改为 `allwinner/sun55i-h728-x96qpro+-stock.dtb`。

## 构建与验证记录

源码与脚本都在本目录；现有 Linux 构建容器 `h728-image-build` 把 `armbian-build` 映射为 `/armbian`。本目录复制到 `/armbian/cache/h728-v3-input` 后分阶段运行：

```sh
bash /armbian/cache/h728-v3-input/prepare.sh
bash /armbian/cache/h728-v3-input/build-emmc-uboot.sh
bash /armbian/cache/h728-v3-input/upgrade.sh
bash /armbian/cache/h728-v3-input/finalize.sh
bash /armbian/cache/h728-v3-input/verify.sh
```

前置物料沿用本项目缓存：原 v2 镜像、v2.1 修复包、7.2 参考包展开目录与从 Image 提取的配置、v2 输入模板。U-Boot/TF-A 源包复制到容器 `/tmp/h728-uboot-source.tar.gz`、`/tmp/h728-atf-source.tar.gz`；新内核原包位于 `/tmp/h728-kernel-7.2.pkg.tar.xz`。确切版本与哈希记录于顶层 SHA256SUMS。

`prepare.sh` 拒绝覆盖已有工作镜像。阶段标记和日志位于 `armbian-build/cache/h728-v3`。这是本地镜像集成流程，不是从空目录完整编译新内核；内核采用作者二进制包，U-Boot 从固定源码构建。

为允许标准 Debian 13 base-files，板级 BSP 被重新打包为 `26.11.0-trunk+h728.3`，仅调整对应依赖和包版本。Debian/Armbian 源均指向清华 Trixie，base-files 优先使用 Debian 来源。内核、启动器和 BSP 包保持 hold，防止普通升级替换本盒子的配套内容。

离线检查包括文件系统、引导偏移、内核与驱动版本、设备树增量、固件、initramfs、UUID、首次 SSH 身份生成及初始密码、软件包依赖和 eMMC 启动器配置。**新内核启动、Wi-Fi 关联、USB 传输、DVFS 稳定性以及 eMMC 实际安装/拔卡冷启动仍需要真机验证。** 原 v2 镜像保留作为回退。
