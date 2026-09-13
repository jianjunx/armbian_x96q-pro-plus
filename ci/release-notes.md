## 实验性完整 SD 镜像 / Experimental standalone SD image

v3.1.3 安装候选版：Debian 13 Trixie + reference Linux `7.2.0-7-MANJARO-ARM`，内核包修订 `+h728.7`。
本次由 GitHub Actions 从校验固定哈希的原始 v3 镜像重新组装并离线验证；
不是完整源码编译内核，也不是上传本机已有的 v3.1 成品。

- 修正 eMMC 供电 DTB，并同步到内核包；保留已验证的 SD U-Boot。
- Wi-Fi SDIO 上限改为 24 MHz；真机实际时钟约 22.22 MHz。现有系统已通过
  三次断电冷启动、5 GHz 连接，以及双向各 5 分钟 TCP 测试：下载 64.3、
  上传 66.0 Mbit/s，上传零重传。新组装镜像仍需复测。
- 附带 `sun55i-h728-x96qpro+-wifi20.dtb` 回退到 20 MHz；具体步骤见 H728-README.txt。
- 无线采用 Netplan/systemd-networkd；不内置用户 Wi-Fi 密码或统一固定 MAC。
- 保留 AIC Wi-Fi 固件、schedutil，增加有界启动诊断，禁用无用 Exim。
- 全新 SD 根系统，不自动写入 eMMC。实验安装器默认 `--check`，显式
  `--install --no-backup` 会在设备/CID 确认后清空 eMMC；也支持 USB 完整备份。
  该安装流程尚待真机端到端验证，详见启动分区 EMMC-INSTALL.md。
- 集成从固定源码编译的 eMMC 引导器文件、配置、DTB 及校验记录；1-bit/26 MHz、
  单块读取。仅存放在 `/usr/lib/h728/uboot`，不自动刷入，不替换 SD 启动器。
- 用户已验证修补后的盒子独立 eMMC 启动；该次日志仍有 Wi-Fi 错误，
  不代表完整新镜像已验证。HDMI、深度空闲降温仍未解决。

下载 `.img.xz`，使用 `SHA256SUMS` 校验压缩包，解压后再次校验 `.img`。
镜像解压后 4 GiB，使用至少 8 GB SD 卡；烧录前备份现有可用 SD。
连接网线，首次 SSH 登录 `root` / `1234`，随后完成首次登录改密流程。
禁止将默认密码设备直接暴露到公网。

离线 PASS 不证明硬件外设正常；请复测冷启动、SSH、Wi-Fi、USB 与温度。
每次组装生成新的文件系统 UUID，因此不同运行的镜像 SHA-256 不相同。

### Provenance / licensing limitations

See MATERIALS.md and the attached build-inputs.sha256. The complete matching
kernel source history is not available in this repository. The upstream AIC
firmware package declares its license as `unknown`; this project makes no
claim to grant redistribution rights for third-party binary components.
