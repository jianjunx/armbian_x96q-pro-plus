# H728 eMMC 独立启动故障复盘（2026-09-13）

> 结论：盒子现在**拔掉 SD 卡能从 eMMC 独立启动**到 login，SSH 可用（`10.0.0.163`）。
> 这条链上一共串着**三个彼此独立的故障**，任何一个没修，现象都完全相同——
> 停在 SPL 的同一行错误上。前两个靠硬件实测挖出，第三个靠代码分析提前发现。

---

## 1. 现象

把 v3 系统用 `h728-install-emmc --install` 装进 eMMC 后：

- 拔掉 SD 卡上电 → 路由器里找不到设备；
- 插回 SD 卡上电 → **同样进不去**（这一点最初被误判为"SD 卡坏了"）；
- HDMI 无信号，无法判断死在哪一级。

改用 USB-TTL 串口（COM3，115200 8N1）后，全部输出只有 7 行：

```
U-Boot SPL 2025.01-h728-emmc-v3 (Sep 09 2026 - 02:34:51 +0000)
DRAM: 4096 MiB
Trying to boot from MMC2
mmc_load_image_raw_sector: mmc block read error
Error: -38
SPL: failed to boot from all boot devices
### ERROR ### Please RESET the board ###
```

## 2. 故障域切分

Allwinner 的加载链是 BROM → SPL(`eGON.BT0`) → U-Boot proper → kernel。上面这段
日志把故障域干净地切成两半：

| 阶段 | 结果 |
|---|---|
| BROM 从 eMMC 用户区 8 KiB 读 SPL | **成功**（EXT_CSD=0x00 也照读，H728 BROM 不看 `PARTITION_CONFIG`） |
| SPL 的 sunxi_mmc 驱动从 SMHC2 读 U-Boot proper | **失败** |

关键对照实验：从 SD 卡启动、打断 autoboot 进 U-Boot CLI，**同一个 SMHC2 控制器读
eMMC 完全正常**（`mmc read` / `fatls` / `fatload` 全过），协商结果是 26 MHz / 1-bit，
`gpio status -a` 确认 PC0-16 全部复用为 mmc2 功能。

所以硬件、引脚、扇区布局都不用怀疑，问题在 **SPL 这一层特有的代码路径**。

---

## 3. 排查时间线

每一轮都记录了「假设 → 怎么验 → 拿到什么证据」。凡是"错误一字未变"的一律当作
**假设被证伪**，不再在原地打转。

### 轮次 1：假设是时序 → 改设备树（v2 补丁）→ **无效**

首版 `uboot-emmc.patch` 做了件"看起来很保守"的事：删掉 `mmc-hs200-1_8v` /
`mmc-ddr-1_8v`，把 eMMC 钉在 52 MHz。这反而**删掉了回退机制**——U-Boot proper 原本
是靠 hs200/ddr 返回 `-ENOSYS` 触发逐级回退，最终落到 26 MHz / 1-bit 才可用的；删掉
触发条件后 SPL 直接进入 52 MHz / 8-bit。

v2 改为：

```diff
 &mmc2 {
-	bus-width = <8>;
+	bus-width = <1>;
-	mmc-ddr-1_8v;
-	mmc-hs200-1_8v;
+	max-frequency = <26000000>;
 };
```

刷入后（时间戳 `Sep 13 2026 - 05:29:59`）**错误一字未变**。

### 轮次 2：发现 SPL 根本不读设备树 → 改驱动硬编码（v3 补丁）→ **仍无效**

查编译产物 `out/emmc-uboot.config`：

```
# CONFIG_SPL_OF_CONTROL is not set
# CONFIG_SPL_DM is not set
```

SPL 是纯 legacy 构建，**压根不解析设备树**，所以 v2 改的 `bus-width` /
`max-frequency` 对它完全是空操作。SPL 走的是 `drivers/mmc/sunxi_mmc.c` 里
`#if !CONFIG_IS_ENABLED(DM_MMC)` 的 legacy 分支 `sunxi_mmc_init()`，其中对 A523 的
`sdc_no == 2` **硬编码**：

```c
cfg->host_caps = MMC_MODE_8BIT | MMC_MODE_HS_52MHz | MMC_MODE_HS;
cfg->f_max = 52000000;
```

正是 U-Boot proper 回退链里唯一会失败的那一级。

同时排除了扇区布局：`spl_mmc.c` 算出 `0x40 + DATA_PART_OFFSET(0x10) = 0x50`，
正是安装器写入的位置，`-38` 不是扇区问题。

v3 在设备树 hunk 之外，再加一段把上面那段硬编码降到 1-bit / 26 MHz
（时间戳 `Sep 13 2026 - 05:52:40`）——**依然一字未变**。

### 轮次 3：开调试日志 → 踩到 Kconfig 坑

不再猜了，编一个带日志的 SPL。第一次开了 `CONFIG_LOG` + `LOGLEVEL=7` +
`SPL_LOGLEVEL=7`，产物里确认都进了，但串口**一行额外输出都没有**（520→仍是 255 字节）。

原因：SPL 有独立的日志开关 `# CONFIG_SPL_LOG is not set`。**只开 `CONFIG_LOG` 是哑的。**
补上 `CONFIG_SPL_LOG` 后输出立刻从 255 字节涨到 520 字节。

### 轮次 4：插桩 → 拿到运行时真相

在驱动里加临时 `printf`，打印 `set_ios` 的实际宽度/时钟、每次命令的参数、以及每个
错误返回点。结果：

```
H728DBG ios bw=1 clk=26000000        <- v3 的时序修复确实生效了
size=200 ... x3                      <- 三次 512 字节单块读全部成功
size=ba200                           <- 一次 1490 块 CMD18（762880 字节）
mmc_load_image_raw_sector: mmc block read error
(error=-5)                           <- -EIO
```

**时序方向到此为止**：修复已生效，还有第二个独立故障——**一次大块多块读卡死**。
失败点在 CMD18 内部、CMD12 之前。

### 轮次 5：代码分析提前发现第三个故障

读 SD 卡上那个能用的 U-Boot 的 `printenv`，得到：

```
boot_targets=fel mmc0 usb0 pxe dhcp
```

**里面没有 mmc1**。原因在 `include/configs/sunxi-common.h`：

```c
#if CONFIG_MMC_SUNXI_SLOT_EXTRA != -1
#define BOOT_TARGET_DEVICES_MMC(func) func(MMC, mmc_auto, na)
#else
#define BOOT_TARGET_DEVICES_MMC(func) func(MMC, mmc0, 1)
#endif
```

`mmc_auto` 会按 `mmc_bootdev` 先跑 `bootcmd_mmc1`，而 `board/sunxi/board.c` 从
`sunxi_get_boot_device()`（MMC2 → 1）赋 `mmc_bootdev=1`。

也就是说：**只要 SPL 能读出 proper，后面这条链是通的；但任何没开 `SLOT_EXTRA` 的
U-Boot 就算从 eMMC 起来了也只会去找不存在的 mmc0。** 这个故障硬件还没跑到就会撞上，
是纯靠读代码提前发现的。

### 轮次 6：b_max + 兜底 → 打通

`mmc_bread()` 会按 `cfg->b_max` 拆分大请求，所以让 SPL 全程单块读。插桩版冷启动
（时间戳 `Sep 13 2026 - 06:48:37`）统计：`bread fail 20 / bread recovered 19 /
single fail 0`——**兜底逐块重试全部救回**，SPL 和 U-Boot proper 都起来了，链路走到
`Found /extlinux/extlinux.conf` → `Retrieving file: /Image`。

但 300 秒没加载完 32 MB 内核（每块插桩打印 2 行 + 多块读间歇失败要重试），所以正式版
去掉插桩、全局 `CONFIG_SYS_MMC_MAX_BLK_COUNT=1`。

---

## 4. 三个独立根因（汇总）

| # | 故障 | 位置 | 修复 |
|---|---|---|---|
| 1 | SPL 不读设备树，走 legacy 硬编码 8-bit/52 MHz | `drivers/mmc/sunxi_mmc.c` 的 `sunxi_mmc_init()` | 对 A523 slot 2 清掉 `MMC_MODE_8BIT\|4BIT\|HS_52MHz`，`f_max` 降到 26 MHz。设备树那一份留给 U-Boot proper，**两边都要改** |
| 2 | SPL 的 1490 块 CMD18 卡死（`-EIO`） | 同上 + `drivers/mmc/mmc.c` 的 `mmc_bread()` | legacy 分支内 `cfg->b_max = 1`；`mmc_bread()` 多块读短读时逐块重试 |
| 3 | 启动目标里没有 eMMC | `include/configs/sunxi-common.h` | 保持 `CONFIG_MMC_SUNXI_SLOT_EXTRA=2`，让 `BOOT_TARGET_DEVICES_MMC` 展开成 `mmc_auto` |

关于第 2 条的两个精确判断：

- **只改 legacy 分支**，不动全局 `CONFIG_SYS_MMC_MAX_BLK_COUNT`——SPL 编译的是 legacy
  分支，U-Boot proper 编译的是 DM 分支。全局改会让每次失败都付约 3 秒超时（24 次 ≈
  70 秒），很可能被看门狗打断。
- **多块读是间歇性失败，不是硬不支持**：U-Boot CLI 读 1490 块成功，但 FAT 连续
  cluster 读 8 块时一个失败一个成功。而**单块读在 SPL 和 U-Boot proper 里从未失败过
  一次**——所以单块是唯一可证明可靠的路径。

---

## 5. 验证结果（真机，SD 卡已拔）

正式版 blob：773113 B，sha256 `17f0895b…`，`CONFIG_SYS_MMC_MAX_BLK_COUNT=1`，
断言全绿（`bus-width=1`、`max-frequency=26000000`、SPL magic `eGON.BT0` @ byte 4）。

串口全链路（留存于 `h728-emmc-boot-VERIFIED-20260913.txt`）：

```
U-Boot SPL 2025.01-h728-emmc-v3 (Sep 13 2026 - 07:09:12 +0000)
U-Boot 2025.01-h728-emmc-v3 ... H728 eMMC v3
Scanning mmc 1:1... → Found /extlinux/extlinux.conf
Retrieving file: /Image → /initrd.img-7.2.0-7-MANJARO-ARM → /dtb/.../sun55i-h728-x96qpro+.dtb
Starting kernel ...
EXT4-fs (mmcblk2p2): mounted filesystem dd11ca3d-...
dwmac-sun55i ... end0: Link is Up - 1Gbps/Full - flow control rx/tx
Welcome to Armbian-unofficial H728 v3 / Debian GNU/Linux 13 (trixie)!
x96q-pro-plus login:                    <- 约 32 秒
```

（日志里两处 `panic` 是内核 cmdline 的 `panic=10`，不是崩溃。）

串口登录 + SSH（`10.0.0.163`）双向确认：

| 项目 | 实测 |
|---|---|
| 根文件系统 | `/dev/mmcblk2p2` ext4（eMMC），`/boot` = `mmcblk2p1` vfat `H728_BOOT` |
| eMMC | 58.2 GiB（CJNB4R），`mmcblk2boot0/1` 各 4 MiB |
| `end0` | 1 Gbps / Full，carrier=1，DHCP 拿到地址 |
| 失败单元 | 仅 `exim4.service`（邮件服务，与本改动无关） |

**副作用**：这个 blob 编译进去的 `ethaddr` 与 SD 卡上那个 U-Boot 不同
（MAC `02:00:fb:5b:fb:44`，`addr_assign_type=0` 即来自固件），DHCP 分到的 IP 从 SD
启动时的 `10.0.0.164` 变成 `10.0.0.163`。要固定就在 U-Boot env 写死 `ethaddr`，或在
路由器做静态绑定。

---

## 6. 过程中踩到的坑（方法论）

1. **"U-Boot proper 能读"不等于"设备没问题"**：两者是不同的构建，走不同的代码分支。
2. **改之前先确认 SPL 有没有设备树**：`grep CONFIG_SPL_OF_CONTROL / CONFIG_SPL_DM .config`。
   没有的话，任何 DT 改动对 SPL 都是空操作。
3. **SPL 日志必须开 `CONFIG_SPL_LOG`**，只开 `CONFIG_LOG` 零输出——"调试版没输出"不是
   "代码路径没走到"的证据。
4. **不要手写 diff hunk**。手写版本通过 `git apply`，却被容器里的 GNU `patch(1)`
   拒绝（空上下文行被剥成空行）。用 `difflib.unified_diff` 从 pinned 上游源码生成，
   并在容器里用 GNU `patch` 验证。
5. **"错误一字未变"就是证伪信号**，不要在同一假设上改参数重试。
6. **一次挂起拿全数据**：脚本在同一个串口会话里做完只读诊断 → 刷入并读回校验 →
   打印下一步提示 → 继续挂着采冷启动。用户只需上电两次。
7. Windows 上 Python 传 `/tmp` 路径要先 `pwd -W` 转 Windows 路径；仓库
   `core.autocrlf=true` 会把脚本写成 CRLF，必须转 LF 才能进容器/盒子。

---

## 7. 遗留问题

- **eMMC 多块读的间歇性失败没有根治**，目前靠 `b_max = 1` 全程单块读规避，加载约
  53 MiB（内核 + initrd + DTB）明显偏慢。要提速需要真正的 A523 新时序校准，不是把
  `b_max` 调大——调大会重新引入失败。
- `ethaddr` 未固定，IP 会随 blob 变化（见第 5 节）。
- 多冷启动下的稳定性（尤其 Wi-Fi SDIO 初始化竞态）尚未系统复测。
- `.github/workflows/image-release.yml` 的路径过滤含 `revision-v3/**`，改该目录下
  任何文档都会触发一次约 90 分钟的 SD 镜像重建，建议收窄。
