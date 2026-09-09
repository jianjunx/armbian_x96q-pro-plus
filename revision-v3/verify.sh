#!/bin/bash
# Literal variable expressions below are interpreted by dpkg, sh and Perl.
# shellcheck disable=SC2016
# shellcheck source=common.sh
source /armbian/cache/h728-v3-input/common.sh
test -f "$cache/finalized"
mount_image yes
test "$(stat -c%s "$image")" -eq 4294967296
sfdisk --json "$image" | jq -e '.partitiontable.partitions | .[0].start == 8192 and .[0].type == "c" and .[0].bootable and .[1].start == 1056768'
blob=/armbian/cache/blobs/u-boot-sunxi-with-spl-x96qproplus-b99f4a9.bin
cmp -n "$(stat -c%s "$blob")" -i 8192:0 "$image" "$blob"
cmp "$root/boot/Image" "$ref/boot/Image"
dtb=$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
expected=$root/tmp/expected.dtb
cp "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$expected"
bash "$src/patch-emmc-dtb.sh" "$expected"
cmp "$dtb" "$expected"
cmp "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb" "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb"
for node in /soc/ethernet@4510000 /soc/usb@4d00000 /soc/phy@4f00000 /soc/mmc@4020000 /soc/mmc@4021000 /soc/mmc@4022000; do
    test "$(fdtget "$dtb" "$node" status)" = okay
done
test "$(fdtget "$dtb" /soc/mmc@4022000 max-frequency)" -eq 52000000
test "$(fdtget "$dtb" /soc/mmc@4022000 bus-width)" -eq 8
test "$(fdtget -l "$dtb" /cpus | grep -c '^cpu@')" -eq 8
for cpu in 0 100 200 300 400 500 600 700; do
    test "$(fdtget "$dtb" /cpus/cpu@$cpu compatible)" = arm,cortex-a55
    fdtget "$dtb" /cpus/cpu@$cpu operating-points-v2 >/dev/null
done
for module in dwmac_sun55i realtek sun8i_thermal aic8800_bsp aic8800_fdrv; do
    chroot "$root" modprobe --set-version "$version" --show-depends "$module"
    test "$(chroot "$root" modinfo -k "$version" -F vermagic "$module" | cut -d' ' -f1)" = "$version"
done
initrd_listing=$(chroot "$root" lsinitramfs "/boot/initrd.img-$version")
for driver in dwmac-sun55i realtek sun8i_thermal; do
    grep -q "$driver.*\.ko" <<<"$initrd_listing"
done
test -s "$root/boot/uInitrd"
uuid=$(blkid -s UUID -o value "${loop}p2")
test "$uuid" != 0956215a-b771-4b93-8a68-d968be52fcfe
grep -q "root=UUID=$uuid" "$root/boot/extlinux/extlinux.conf"
grep -qx "rootdev=UUID=$uuid" "$root/boot/armbianEnv.txt"
grep -q "$uuid" "$root/etc/fstab"
grep -q '7283-0001' "$root/etc/fstab"
while read -r directive path _; do
    case "$directive" in LINUX|INITRD|FDT) test -s "$root/boot$path" ;; esac
done <"$root/boot/extlinux/extlinux.conf"
grep -qx VERSION_ID=\"13\" "$root/etc/os-release"
grep -qx VERSION_CODENAME=trixie "$root/etc/os-release"
chroot "$root" dpkg --audit
chroot "$root" apt-get check
chroot "$root" dpkg-query -W base-files libc6 systemd openssh-server linux-image-h728-manjaro
test "$(chroot "$root" dpkg-query -W -f='${Version}' linux-image-h728-manjaro)" = 7.2.0-7+h728.3
chroot "$root" apt-mark showhold | grep -qx linux-image-h728-manjaro
for tool in iw rfkill wpa_supplicant rsync partprobe mkfs.vfat mkfs.ext4; do
    chroot "$root" sh -c 'command -v "$1"' _ "$tool"
done
grep -qx GOVERNOR=schedutil "$root/etc/default/cpufrequtils"
grep -qx MIN_SPEED=408000 "$root/etc/default/cpufrequtils"
test -s "$root/usr/lib/firmware/aic8800_sdio/fw_patch_table_8800d80_u02.bin"
tar -xzf /armbian/output/repairs/h728-v2.1-repair.tar.gz -C "$root/tmp"
for firmware in "$root/tmp/h728-v2.1-repair/firmware/"*; do
    cmp "$firmware" "$root/usr/lib/firmware/aic8800_sdio/$(basename "$firmware")"
done
chroot "$root" sh -c 'cd /usr/lib/h728/uboot && sha256sum -c emmc-uboot.sha256'
grep -qx CONFIG_MMC_SUNXI_SLOT_EXTRA=2 "$root/usr/lib/h728/uboot/emmc-uboot.config"
test -x "$root/usr/local/sbin/h728-install-emmc"
test -L "$root/etc/systemd/system/basic.target.wants/armbian-hardware-optimize.service"
test -L "$root/etc/systemd/system/timers.target.wants/h728-diagnostics.timer"
test -L "$root/etc/systemd/system/multi-user.target.wants/ssh.service"
test -L "$root/etc/systemd/system/sysinit.target.wants/systemd-resolved.service" || chroot "$root" systemctl is-enabled systemd-resolved.service
test ! -s "$root/etc/machine-id"
test ! -e "$root/usr/sbin/policy-rc.d"
test ! -e "$root/etc/ssh/ssh_host_ed25519_key"
test -f "$root/root/.not_logged_in_yet"
# Verify the documented initial password without printing its hash.
chroot "$root" perl -e 'open(my $f,"<","/etc/shadow") or die; while(<$f>){my @p=split /:/; if($p[0] eq "root"){crypt("1234",$p[1]) eq $p[1] or die "Unexpected root password"; exit 0}} die "No root account"'
chroot "$root" mkdir -p /run/sshd
chroot "$root" ssh-keygen -q -t ed25519 -N '' -f /tmp/ssh-test-key
chroot "$root" sshd -t -h /tmp/ssh-test-key
ssh_settings=$(chroot "$root" sshd -T -h /tmp/ssh-test-key)
grep -qx 'permitrootlogin yes' <<<"$ssh_settings"
grep -qx 'passwordauthentication yes' <<<"$ssh_settings"
chroot "$root" systemd-analyze verify /etc/systemd/system/h728-ssh-hostkeys.service /etc/systemd/system/h728-diagnostics.service
if grep -E 'Suites:.*bookworm' "$root/etc/apt/sources.list.d/"*.sources; then exit 1; fi
echo 'PASS: 4 GiB image, filesystems, SD bootloader, matched 7.2 payload, eMMC DTB delta, eight CPUs, Wi-Fi firmware, Trixie packages, initramfs, SSH first login and eMMC installer payload.'
echo 'NOT hardware-tested: new-kernel SD boot, Wi-Fi association, USB transfer, DVFS stability, eMMC sustained I/O and standalone cold boot.'
