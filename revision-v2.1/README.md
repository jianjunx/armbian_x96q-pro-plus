# H728 v2.1 Wi-Fi 与调频补丁

此包用于已启动的 Armbian v2（`6.17.0-rc1-2-MANJARO-ARM+`），补齐 AIC8800D80 SDIO 固件，并将 CPU 策略改为 `schedutil`，允许空闲降频。此包不升级内核或 Debian 发行版。

2026-09-08 的真机日志确认：8 个 CPU 在线、有线链路为 1000 Mbps 全双工；Wi-Fi 的 SDIO ID 为 `c8a1:0082` / `c8a1:0182`，驱动因找不到 `/usr/lib/firmware/aic8800_sdio/fw_patch_table_8800d80_u02.bin` 退出。两组 CPU 使用 performance，当前频率为 1.416/1.8 GHz；CPU 温度 45.8/47.4°C。日志没有同时记录负载，不能据此断言持续空载过热。

## 在盒子上安装

将 `h728-v2.1-repair.tar.gz` 传到盒子，执行：

```sh
tar -xzf h728-v2.1-repair.tar.gz
cd h728-v2.1-repair
sudo bash install.sh
sudo reboot
```

root 登录时可省略 sudo。安装会备份原有固件目录和 cpufrequtils 配置到 `/var/backups/h728-v2.1.*`，保留原有最高频率限制。只修复固件加载，不包含 SSID/密码；成功生成无线接口后仍需配置网络。

重启后检查：

```sh
ip -br link
dmesg | grep -Ei 'aic|firmware|rwnx'
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq
sudo /usr/local/sbin/h728-diagnostics
```

预期不再出现缺少上述固件的报错，并出现无线接口。是否能扫描、关联和稳定传输仍需真机测试。记录同样环境下静置 10 分钟后的温度与频率；温度变化不能预先保证。按需调频会触发电压/频率切换，如果出现重启或卡死，恢复备份的 `/etc/default/cpufrequtils` 后重启，或将其中 GOVERNOR 改回 performance；这能区分 DVFS 稳定性问题。

## 固件来源

使用论坛作者给本盒子发布的完整固件包，保持其目录与文件名：

- [原始支持帖](https://forum.manjaro.org/t/allwinner-h728-a523-a527-t527-initial-support-thread/173654)
- [aic8800d80-firmware-2025.03-1-any.pkg.tar.zst](https://drive.google.com/file/d/1jj2vpSFcgSFfor-mv-MiFAefhHxXAAaX/view)
- 原包 SHA-256：`1b921a23d1f9f952a2b2d53f99a431f5d6450a2aa4b815d24b3c7b9606782ab6`

包内保留上游 PKGINFO；其许可证字段为 unknown。本地兼容测试使用，重新公开分发前需确认固件授权。

## 构建

在项目根目录执行（现有构建容器需运行）：

```sh
docker cp reference-packages/aic8800d80-firmware-2025.03-1-any.pkg.tar.zst h728-image-build:/tmp/h728-wifi.pkg.tar.zst
docker cp revision-v2/h728-diagnostics h728-image-build:/armbian/cache/h728-v2-input/h728-diagnostics
docker cp revision-v2.1 h728-image-build:/armbian/cache/h728-v2.1-input
docker exec h728-image-build bash /armbian/cache/h728-v2.1-input/build-bundle.sh
```

产物位于 `armbian-build/output/repairs`。安装器也支持 `--root /mounted-v2-rootfs`，用于离线镜像集成及验证，不访问构建主机的 CPU sysfs。
