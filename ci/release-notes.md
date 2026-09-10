## 实验性完整 SD 镜像 / Experimental standalone SD image

Debian 13 Trixie + reference Linux `7.2.0-7-MANJARO-ARM`，内核包修订 `+h728.4`。
本次由 GitHub Actions 从校验固定哈希的原始 v3 镜像重新组装并离线验证；
不是完整源码编译内核，也不是上传本机已有的 v3.1 成品。

- 修正 eMMC 供电 DTB，并同步到内核包；保留已验证的 SD U-Boot。
- 保留 AIC Wi-Fi 固件、schedutil，增加有界启动诊断，禁用无用 Exim。
- 全新 SD 根系统，eMMC 安装器禁用；不复制或覆盖盒子现有 eMMC。
- 独立 eMMC 启动、HDMI、深度空闲降温仍未解决；新镜像尚未真机验证。

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
