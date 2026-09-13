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

## v3 有线网回归：根因与修复（2026-09-09 真机二分确认）

v3 首版真机表现：系统正常进入用户空间，但路由器里看不到设备。诊断日志：

```
mdio_bus stmmac-0: MDIO device at address 1 is missing.
dwmac-sun55i 4510000.ethernet end0: cannot attach to PHY (error: -ENODEV)
```

用 `extlinux.conf` 切到 `stock-dtb`（即 `/soc/mmc@4022000` 保持 `disabled`）后，`end0` 立即以 1 Gbps/全双工起来并拿到 DHCP 地址。**回归点确认为 `patch-emmc-dtb.sh`，不是 7.2 参考 DTB 的 PHY 配置。**

### 根因：eMMC 抢占了 PHY 的供电轨

参考 DTB 中 phandle `0x15` 是 `cldo3` / `vcc-codec-eth-sd`（固定 3.4 V，无 `regulator-always-on`），被四处引用：

| 引用位置 | 用途 |
| --- | --- |
| `vcc-pb-supply` / `vcc-pf-supply` / `vcc-ph-supply` | GPIO 端口 B / F / H 供电 |
| `ethernet@4510000` 的 `phy-supply` | **GMAC1 PHY（RTL8211F）供电** |

首版 `patch-emmc-dtb.sh` 把同一路 `0x15` 设成了 eMMC 的 `vmmc-supply`。eMMC 一启用，MMC 子系统对该共享轨执行 `mmc_regulator_set_ocr()` 上电时序（eMMC 要 3.3 V，而该轨固定 3.4 V 不可调，请求被拒），随后的 power up/off 循环会 gate 这路电源；PHY 掉电后 MDIO 在地址 1 扫不到设备，`end0` 永远 DOWN。

引脚复用**没有**冲突：mmc2 用 `PC0/1/5/6/8/9/10/11/13-16`，gmac1 用 `PJ0-15`，端口不同。

### 修复

eMMC 的 `vmmc-supply` 改用板级 `/vcc3v3`（phandle `0x1f`，3.3 V 固定、`regulator-always-on`）——这正是另外两个已验证可用的控制器 `mmc@4020000`（SD 卡）和 `mmc@4021000`（SDIO Wi-Fi）使用的同一路。`vqmmc-supply` 保持 `reg_cldo1` / `vcc-codec-sd`（1.9 V，带 always-on，无冲突）。

修复后与首版的 DTB 差异**只有一行**：

```diff
 			post-power-on-delay-ms = <0x1f4>;
 			bus-width = <0x08>;
 			vqmmc-supply = <0x16>;
-			vmmc-supply = <0x15>;
+			vmmc-supply = <0x1f>;
```

### 真机验证结果（2026-09-09，方案 A 就地安装）

把修好的 DTB 装到 SD 卡 FAT 并切 `DEFAULT armbian-h728`，冷启动后：

| 项目 | 结果 |
|---|---|
| 运行中的 `mmc@4022000` | `okay` / `bus-width=8` |
| eMMC 块设备 | `mmcblk2` 58.2 GiB（CJNB4R）+ `mmcblk2boot0/1` 各 4 MiB，29 个分区 |
| 实际协商时序 | `clock 52 MHz (actual 50 MHz)`、`8 bits`、**`MMC DDR52`**、`signal voltage 1.80 V` |
| 只读吞吐 | `h728-install-emmc --check` 读 256 MiB @ **101 MB/s**，只读检查通过 |
| PHY | `end0: PHY [stmmac-0:01] driver [Generic PHY]`，`Link is Up - 1Gbps/Full - flow control rx/tx` |
| IP | `10.0.0.164/24` + IPv6 |
| MDIO 回归 | `dmesg` 中**无** `MDIO device at address 1 is missing` |
| failed units | 0 |
| 温度 | 48 / 46 / 46 / 47 °C |

### 写入稳定性测试（2026-09-09）

在**未挂载**的 Android `userdata`（`mmcblk2p29`，54.2 GiB f2fs）内借用 8 GiB 偏移处的 512 MiB 窗口，做「备份 → 写入 → 校验 → 还原 → 再校验」闭环，对 eMMC 的持久影响为零：

| 项目 | 结果 |
|---|---|
| 写入 1 / 2 | **58.7 / 61.3 MB/s**，512 MiB `conv=fsync` |
| 读回校验 | 两次 SHA-256 均与写入模式**逐字节一致**（`drop_caches` + `blockdev --flushbufs` 后读回） |
| 还原校验 | 还原后 SHA-256 与备份 `orig.bin` **完全一致**，`RESTORE_OK` |
| `dmesg` mmc2 错误 | **无** |
| eMMC 健康度 | `life_time = 0x04 0x04`（约 30–40% 额定寿命已消耗）、`pre_eol_info = 0x01`（Normal） |

结论：eMMC 写入路径在 DDR52 下稳定，`h728-install-emmc --install` 的写入风险已排除。**未做的**：断电持久性（写后冷启动再读回）测试——当前结论基于 `fsync` + 缓存失效后的读回校验。

注意：`userdata` 还原写入只有 23.4 MB/s，慢于首次写入，属 eMMC 内部 GC/写放大现象，正确性已由校验覆盖。

### 附带结果：Wi-Fi 在同一版 DTB 下可用了

同一次冷启动后 `aic8800_fdrv` + `aic8800_bsp` 均加载，固件 `/usr/lib/firmware/aic8800_sdio/fw_*_8800d80_u02.bin` 全部加载成功，`wlan0`（`88:00:33:77:bc:36`）出现，`iw dev wlan0 scan` 扫到 12 个 BSS。此前（回滚到 stock DTB 的那次启动）的失败表现为 `aicwf_sdio_send_pkt fail-110`(ETIMEDOUT) → `rwnx_mod_init, set power on fail!`，推测是 aic8800 SDIO 初始化的时序竞态，而非固件缺失或与 eMMC 供电相关；**需要多冷启动几次确认是否稳定复现**。

`wlan0` 目前 `networkctl` 状态为 `off / unmanaged`——镜像里没有配置无线连接，属预期。

## DTB 回滚构建（二分实验）

这个开关的价值已经兑现：它把回归点精确锁定到 eMMC 补丁上。保留它以备后续回归分析。

如果 eMMC 启用导致有线/USB 等外设异常，可以只跳过 `patch-emmc-dtb.sh` 的 eMMC 补丁，**保持 7.2 内核、模块和参考 DTB 其余部分不变**，得到一个 `sun55i-h728-x96qpro+.dtb` 与参考原版逐字节相同的镜像，用于确认回归点是 eMMC 补丁本身，还是 7.2 参考 DTB 的非 eMMC 部分。

```sh
export H728_DTB_ROLLBACK=1
bash /armbian/cache/h728-v3-input/prepare.sh
bash /armbian/cache/h728-v3-input/build-emmc-uboot.sh
bash /armbian/cache/h728-v3-input/upgrade.sh
bash /armbian/cache/h728-v3-input/finalize.sh
H728_DTB_ROLLBACK=1 bash /armbian/cache/h728-v3-input/verify.sh
```

行为变化：

| 项 | 默认 v3 | `H728_DTB_ROLLBACK=1` |
| --- | --- | --- |
| `patch-emmc-dtb.sh` | 启用 `/soc/mmc@4022000`，8-bit、52 MHz SDR | 不修改 DTB，`mmc@4022000` 保持 `disabled` |
| `/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb` | 参考 DTB + eMMC 补丁 | 与参考原版逐字节相同 |
| `/boot/dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb` | 参考原版 | 参考原版（两者内容相同） |
| extlinux 默认菜单标签 | "eMMC enabled (52 MHz SDR)" | "stock DTB (eMMC disabled, rollback build)" |
| `armbianEnv.txt` 的 `fdtfile` | `allwinner/sun55i-h728-x96qpro+.dtb` | `allwinner/sun55i-h728-x96qpro+.dtb`（内容相同，无需修改） |
| `verify.sh` 断言 | 校验 eMMC 补丁 delta、52 MHz、8-bit | 跳过 eMMC 断言，断言 `mmc@4022000` 为 `disabled` |
| 内核 / 模块 / U-Boot / 软件源 / 用户空间 | 不变 | 不变 |
| eMMC 安装器 `h728-install-emmc` | 可用 | 不可用：eMMC 节点 disabled，`--check` 会失败 |

回滚镜像是一个**仅供二分实验**的中间产物，**不应替换** v3 正式交付。AGENTS.md 要求每个可测行为变化都使用新文件名；建议产物名加 `-rollback` 后缀（例如 `Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3-rollback.img`），并保留 v3 原版作为后续恢复路径。

预期真机结果：

- 若 DHCP 立即拿到地址、有线 `end0` 拿到 carrier —— 回归点在 `patch-emmc-dtb.sh` 引入的 eMMC 节点，需要排查它对 GMAC1 PHY 供电或 regulator 共享的影响。
- 若仍无 carrier —— 回归点在 7.2 参考 DTB 本身的 GMAC1/PHY 配置，需要在 `manjaro-linux-a523`/`armbian-patches/` 里继续对照 6.17-2 参考 DTB 的 PHY 供电、复位与 RGMII 延迟。

## eMMC 独立启动失败：根因与修复（2026-09-13 串口定位）

接上 USB-TTL 串口（COM3，115200 8N1）后，拔 SD 卡冷启动 eMMC 的完整输出只有 7 行：

```
U-Boot SPL 2025.01-h728-emmc-v3 (Sep 09 2026 - 02:34:51 +0000)
DRAM: 4096 MiB
Trying to boot from MMC2
mmc_load_image_raw_sector: mmc block read error
Error: -38
SPL: failed to boot from all boot devices
### ERROR ### Please RESET the board ###
```

这把故障域直接切成两段：

| 加载阶段 | 结果 |
|---|---|
| BROM 从 eMMC 用户区 8 KiB 加载 SPL | **成功**（EXT_CSD=0x00 也照读，H728 BROM 不看 PARTITION_CONFIG） |
| SPL 的 sunxi_mmc 驱动从 SMHC2 读 U-Boot proper | **失败**（`mmc block read error` / `-ENOSYS`） |

同时从 SD 启动打断 autoboot 进 U-Boot CLI 验证过：**同一个 SMHC2 控制器，U-Boot proper 读 eMMC 完全正常**（`mmc read`/`fatls`/`fatload` 全过），协商结果是 **26 MHz / 1-bit**，`gpio status -a` 确认 PC0-16 全部正确复用为 mmc2 功能，MMC2 模块时钟 25 MHz。

### 根因：我们的"保守"补丁把 SPL 钉死在坏模式上

- SD blob（未打补丁的 U-Boot dts：含 `mmc-hs200-1_8v` + `mmc-ddr-1_8v`）的 U-Boot proper：模式协商逐级回退 HS200 → `-ENOSYS` → DDR → 失败 → … → **落到 26 MHz / 1-bit，恰好可用**。
- eMMC blob（打了首版 `uboot-emmc.patch`：删掉 hs200/ddr、限 52 MHz）的 SPL：没有回退触发条件，**直接进入 52 MHz / 8-bit SDR**——而这个模式在 U-Boot 的 sunxi 驱动下不工作（A523 需要新时序校准，U-Boot 驱动没有；Linux 内核有，所以内核 DDR52 正常）。

也就是说：**U-Boot（SPL 和 proper）在这块板子上唯一被证明可用的 eMMC 模式是 1-bit / 26 MHz**——BROM 用它，U-Boot proper 回退后也是它。

### 修复（2026-09-13，`uboot-emmc.patch` v2）

```diff
 &mmc2 {
 	vmmc-supply = <&reg_cldo3>;
 	vqmmc-supply = <&reg_cldo1>;
-	bus-width = <8>;
+	bus-width = <1>;
 	non-removable;
 	cap-mmc-hw-reset;
-	mmc-ddr-1_8v;
-	mmc-hs200-1_8v;
+	max-frequency = <26000000>;
 	status = "okay";
 };
```

已用 `git apply` 对上游 dts 干跑验证通过。**此补丁只影响 U-Boot 自身（SPL + proper），不影响 Linux 侧 DTB**（Linux 的 eMMC 仍是 8-bit DDR52，由 `patch-emmc-dtb.sh` 独立维护）。

### v2 无效：SPL 根本不解析设备树

按上面重编出的 v2 blob 刷入后（时间戳 `Sep 13 2026 - 05:29:59`），串口输出**一字未变**。
查编译产物 `out/emmc-uboot.config` 发现 `CONFIG_SPL_OF_CONTROL` 与 `CONFIG_SPL_DM`
**均未开启** —— SPL 是纯 legacy 构建，压根不读设备树，所以改 `bus-width` /
`max-frequency` 对它是空操作。SPL 走的是 `drivers/mmc/sunxi_mmc.c` 里
`#if !CONFIG_IS_ENABLED(DM_MMC)` 的 legacy 分支 `sunxi_mmc_init()`，其中对 A523 的
`sdc_no == 2` **硬编码**：

```c
cfg->host_caps = MMC_MODE_8BIT | MMC_MODE_HS_52MHz | MMC_MODE_HS;
cfg->f_max = 52000000;
```

正是 U-Boot proper 回退链里唯一会失败的那一级。
（扇区布局同时被排除：`spl_mmc.c` 算出 `0x40 + DATA_PART_OFFSET 0x10 = 0x50`，
正是安装器写入的位置。）

### v3 也无效：SPL 的多块读会卡死

v3 在设备树 hunk 之外另加一段，把上面那段硬编码降到 1-bit / 26 MHz
（时间戳 `Sep 13 2026 - 05:52:40`），**依然一字未变**。改用插桩拿到运行时真相：
SPL 的日志要开 **`CONFIG_SPL_LOG`**（只开 `CONFIG_LOG` 是哑的），开满后串口给出

```
H728DBG ios bw=1 clk=26000000            <- 时序修复确实生效
size=200 ... x3                          <- 三次 512 字节单块读全部成功
size=ba200                               <- 一次 1490 块 CMD18
mmc_load_image_raw_sector: mmc block read error
(error=-5)                               <- -EIO，卡在 CMD18 内部、CMD12 之前
```

### 第三个故障：启动目标里没有 eMMC

读 SD 卡上那个能用的 U-Boot 的 `printenv`，得到 `boot_targets=fel mmc0 usb0 pxe dhcp`
——**没有 mmc1**。原因在 `include/configs/sunxi-common.h`：
`BOOT_TARGET_DEVICES_MMC` 在 `CONFIG_MMC_SUNXI_SLOT_EXTRA != -1` 时展开为
`mmc_auto`，否则是死值 `mmc0`。`mmc_auto` 会按 `mmc_bootdev` 先跑 `bootcmd_mmc1`，
而 `board/sunxi/board.c` 从 `sunxi_get_boot_device()`（MMC2 → 1）赋 `mmc_bootdev=1`。
也就是说：**只要 SPL 能读出 proper，后面这条链是通的**；反过来说，任何没开
`SLOT_EXTRA` 的 U-Boot 就算从 eMMC 起来了也只会去找不存在的 mmc0。

### 最终修复（v4）

1. legacy 分支里把 A523 slot 2 的 `host_caps` 清掉 8BIT/4BIT/HS_52MHz，`f_max` 降到
   26 MHz（设备树那一份留给 U-Boot proper，两边都要改）。
2. legacy 分支里设 `cfg->b_max = 1`，让 SPL 全程单块读。多块读是**间歇性**失败
   （U-Boot CLI 读 1490 块成功，但 FAT 连续 cluster 读 8 块时一块失败一块成功），
   而单块读在 SPL 和 U-Boot proper 里**从未失败过一次**。只改 legacy 分支，
   U-Boot proper 的 DM 分支不受影响；全局改 `CONFIG_SYS_MMC_MAX_BLK_COUNT` 会让每次
   失败都付约 3 秒超时代价。
3. `mmc_bread()` 加兜底：多块读短读时逐块重试，stall 降级而不是判死。
4. `CONFIG_MMC_SUNXI_SLOT_EXTRA=2` 保持开启（第二个关键作用：让启动目标变成
   `mmc_auto`）。

补丁用 `revision-v3/gen-patches.py` 从 pinned 上游源码以 `difflib` 生成，不要手写
hunk —— 手写版本曾通过 `git apply` 却被容器里的 GNU `patch` 拒绝（空上下文行被剥成
空行）。构建走 `ci/podman-build-uboot-emmc.sh`（Podman + `ubuntu:24.04`，约 3 分钟），
`H728_UBOOT_DEBUG=1` 会额外打开 `CONFIG_SPL_LOG` 并打上插桩补丁。

## eMMC 独立启动已打通（2026-09-13 真机验证）

把 v4 blob（773113 B，sha `17f0895b…`）刷入 eMMC 用户区 8 KiB、**拔掉 SD 卡**冷启动，
串口完整链路：

```
U-Boot SPL 2025.01-h728-emmc-v3 (Sep 13 2026 - 07:09:12 +0000)
U-Boot 2025.01-h728-emmc-v3 ... H728 eMMC v3
Scanning mmc 1:1... -> Found /extlinux/extlinux.conf
Retrieving file: /Image -> /initrd.img-7.2.0-7-MANJARO-ARM -> /dtb/.../sun55i-h728-x96qpro+.dtb
Starting kernel ...
EXT4-fs (mmcblk2p2): mounted filesystem dd11ca3d-... 
dwmac-sun55i ... end0: Link is Up - 1Gbps/Full - flow control rx/tx
Welcome to Armbian-unofficial H728 v3 / Debian GNU/Linux 13 (trixie)!
x96q-pro-plus login:
```

启动后 SSH 登录确认（`10.0.0.163`）：

| 项目 | 实测 |
|---|---|
| 根文件系统 | `/dev/mmcblk2p2` ext4（eMMC），`/boot` 为 `mmcblk2p1` vfat `H728_BOOT` |
| eMMC 容量 | 58.2 GiB（CJNB4R），`mmcblk2boot0/1` 各 4 MiB |
| 有线 `end0` | 1 Gbps / Full，carrier=1，DHCP 拿到地址 |
| 启动耗时 | 约 32 秒到 login |
| 失败单元 | 仅 `exim4.service`（邮件服务，与本改动无关） |

**副作用**：这个 blob 编译进去的 `ethaddr` 与 SD 卡上那个 U-Boot 不同，MAC 为
`02:00:fb:5b:fb:44`，因此 DHCP 分到的 IP 从 SD 启动时的 `10.0.0.164` 变成
`10.0.0.163`。功能不受影响，但按 IP 记忆的登录方式要相应更新；如需固定，可在
U-Boot env 里写死 `ethaddr` 或在路由器上做静态绑定。

**遗留**：eMMC 多块读仍是间歇性失败，目前靠 `b_max = 1` 全程单块读规避，加载
~53 MiB 内核 + initrd 明显偏慢。要提速需要真正的时序修复（A523 新时序校准），
不是把 `b_max` 调大。
