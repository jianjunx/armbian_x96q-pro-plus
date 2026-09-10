#!/bin/bash
# Diagnostic files only. No partitioning, raw writes, bootloader or DTB changes.
set -euo pipefail
root_uuid=dd11ca3d-7015-4466-8fba-cb95a97b73ff
boot_uuid=A7DC-CB4B
sd_uuid=5e0d59f0-a18f-4d13-8d91-ea283a16f754
name=h728-emmc-probe-v1
mode=${1:-help}
fail() { echo "STOP: $*" >&2; exit 1; }
[[ $# == 1 && $mode =~ ^(install|collect|export)$ ]] || fail 'Usage: bash h728-emmc-probe.sh install|collect|export'
[[ $EUID == 0 ]] || fail 'Run as root.'
[[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || fail 'Wrong board.'
[[ $(uname -r) == 7.2.0-7-MANJARO-ARM ]] || fail 'Wrong kernel.'
current_root=$(readlink -f "$(findmnt -nro SOURCE /)")
current_disk=$(lsblk -ndo PKNAME "$current_root")
[[ $current_disk =~ ^mmcblk[0-9]+$ ]] || fail 'Root is not on a physical MMC/SD partition.'

if [[ $mode == collect ]]; then
    [[ $(blkid -s UUID -o value "$current_root") == "$root_uuid" ]] || fail 'Not the installed eMMC root.'
    [[ $(cat "/sys/class/block/$current_disk/device/type") == MMC ]] || fail 'Root is not eMMC.'
    exec 9>"/run/$name.lock"
    flock -n 9 || exit 0
    base=/var/lib/$name
    (( $(df -Pk / | awk 'END {print $4}') >= 32768 )) || fail 'Root free space below 32 MiB.'
    id=$(cat /proc/sys/kernel/random/boot_id)
    [[ $id =~ ^[0-9a-f-]{36}$ ]] || exit 1
    out=$base/$id
    mkdir -p "$out"
    slot=
    for n in 1 2 3 4; do
        [[ -e $out/snapshot-$n.txt ]] || { slot=$n; break; }
    done
    [[ -n $slot ]] || exit 0
    # Persist a minimal marker BEFORE slower diagnostic commands.
    printf 'eMMC userspace reached\nboot_id=%s\n' "$id" >"$out/started.txt"
    cat /proc/uptime /proc/cmdline >>"$out/started.txt"
    sync -f "$out"
    capture() {
        printf '\n=== %s ===\n' "$*"
        timeout 5 "$@" || echo "Unavailable/failed: $*"
    }
    {
        capture date -Is
        capture cat /proc/uptime /proc/cmdline
        capture findmnt -rn -o SOURCE,TARGET,FSTYPE
        capture cat /sys/kernel/debug/regulator/regulator_summary
        capture dmesg
        capture lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
        capture ip -br address
        capture cat /sys/class/net/end0/carrier /sys/class/net/end0/operstate
        capture systemctl --no-pager --failed
    } >"$out/snapshot-$slot.txt.part" 2>&1
    mv "$out/snapshot-$slot.txt.part" "$out/snapshot-$slot.txt"
    if [[ $slot == 1 ]]; then
        timeout 5 dtc -q -I fs -O dts /proc/device-tree >"$out/running.dts" 2>"$out/dtc-errors.txt" || true
        [[ ! -r /sys/firmware/fdt ]] || cp /sys/firmware/fdt "$out/running.dtb"
    fi
    sync -f "$out"
    # Root copy remains useful even if /boot could not mount.
    if bootpart=$(findmnt -nr -M /boot -o SOURCE); then
        bootpart=$(readlink -f "$bootpart")
        if [[ $(blkid -s UUID -o value "$bootpart") == "$boot_uuid" && $(lsblk -ndo PKNAME "$bootpart") == "$current_disk" ]]; then
            if (( $(df -Pk /boot | awk 'END {print $4}') >= 16384 )); then
                mkdir -p "/boot/$name/$id"
                cp "$out"/* "/boot/$name/$id/"
                sync -f "/boot/$name"
            fi
        fi
    fi
    exit 0
fi

[[ $(cat "/sys/class/block/$current_disk/device/type") == SD ]] || fail 'Install/export must run from SD.'
[[ $(blkid -s UUID -o value "$current_root") == "$sd_uuid" ]] || fail 'Unexpected SD root UUID.'
targets=()
for path in /sys/block/mmcblk[0-9]*; do
    [[ ${path##*/} =~ ^mmcblk[0-9]+$ && -f $path/device/type ]] || continue
    [[ $(cat "$path/device/type") != MMC ]] || targets+=("/dev/${path##*/}")
done
[[ ${#targets[@]} == 1 ]] || fail 'Expected exactly one eMMC.'
target=${targets[0]}
rootpart=${target}p2
bootpart=${target}p1
assert_target() {
    [[ $(blkid -s UUID -o value "$rootpart") == "$root_uuid" && $(blkid -s TYPE -o value "$rootpart") == ext4 ]] || fail 'eMMC root mismatch.'
    [[ $(blkid -s UUID -o value "$bootpart") == "$boot_uuid" && $(blkid -s TYPE -o value "$bootpart") == vfat ]] || fail 'eMMC boot mismatch.'
    [[ $(blockdev --getro "$target") == 0 ]] || fail 'Device is read-only.'
    if lsblk -nrpo MOUNTPOINTS "$target" | grep -q '[^[:space:]]'; then fail 'eMMC is mounted or used as swap.'; fi
    for entry in /sys/class/block/"${target##*/}" /sys/class/block/"${target##*/}"p*; do
        [[ ! -d $entry/holders ]] || ! compgen -G "$entry/holders/*" >/dev/null || fail 'Active device holder.'
    done
}
assert_target
cid=$(cat "/sys/class/block/${target##*/}/device/cid")
echo "eMMC target: $target; CID: $cid; root UUID: $root_uuid"
if [[ $mode == install ]]; then
    echo 'Only new diagnostic files will be installed. Boot settings remain unchanged.'
    token="PROBE $target ${cid: -8}"
    echo "Type exactly: $token"
    read -r answer </dev/tty
    [[ $answer == "$token" ]] || fail 'Cancelled.'
fi
assert_target
[[ $(cat "/sys/class/block/${target##*/}/device/cid") == "$cid" ]] || fail 'CID changed.'
work=$(mktemp -d /tmp/h728-emmc-probe.XXXXXX)
cleanup() { if mountpoint -q "$work"; then umount "$work"; fi; }
trap cleanup EXIT
mount -t ext4 -o ro,noload,nodev,nosuid,noexec "$rootpart" "$work"
if [[ $mode == export ]]; then
    [[ -d $work/var/lib/$name ]] || fail 'No probe directory found.'
    export_dir=$(mktemp -d /root/h728-emmc-evidence.XXXXXX)
    tar -czf "$export_dir/results.tar.gz" -C "$work/var/lib" "$name"
    echo "Saved to SD: $export_dir/results.tar.gz"
    exit 0
fi
for path in usr/local/sbin etc/systemd/system var/lib; do
    [[ -d $work/$path && $(realpath "$work/$path") == "$work/$path" ]] || fail "Unexpected directory/symlink: $path";
done
for path in "usr/local/sbin/$name" "etc/systemd/system/$name.service" "etc/systemd/system/$name.timer" "var/lib/$name" "etc/systemd/system/sysinit.target.wants/$name.service" "etc/systemd/system/timers.target.wants/$name.timer"; do
    [[ ! -e $work/$path && ! -L $work/$path ]] || fail "Already exists: $path";
done
for path in etc/systemd/system/sysinit.target.wants etc/systemd/system/timers.target.wants; do
    [[ $(realpath -m "$work/$path") == "$work/$path" ]] || fail "Unexpected symlink: $path";
done
for tool in usr/bin/timeout usr/bin/flock usr/bin/dtc; do
    # test -x checks mount permissions too: it always fails on this noexec
    # audit mount, even for a valid mode-0755 binary. Inspect the file instead.
    [[ -f $work/$tool && -r $work/$tool && -s $work/$tool ]] || fail "Missing/unreadable dependency: $tool"
    permissions=$(stat -Lc '%a' "$work/$tool")
    (( (8#$permissions & 0111) != 0 )) || fail "Dependency has no executable mode bits: $tool"
done
umount "$work"
# Separate RW mount permits normal journal recovery. No offline chroot execution.
mount -t ext4 -o rw,nodev,nosuid,noexec "$rootpart" "$work"
install -m0755 "$(readlink -f "$0")" "$work/usr/local/sbin/$name"
mkdir -p "$work/var/lib/$name" "$work/etc/systemd/system/"{sysinit.target.wants,timers.target.wants}
cat >"$work/etc/systemd/system/$name.service" <<'EOF'
[Unit]
Description=H728 eMMC boot evidence (root copy, optional boot copy)
DefaultDependencies=no
After=systemd-remount-fs.service
Before=sysinit.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/h728-emmc-probe-v1 collect
TimeoutStartSec=90
EOF
cat >"$work/etc/systemd/system/$name.timer" <<'EOF'
[Unit]
Description=H728 eMMC follow-up evidence

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=1

[Install]
WantedBy=timers.target
EOF
ln -s "../$name.service" "$work/etc/systemd/system/sysinit.target.wants/$name.service"
ln -s "../$name.timer" "$work/etc/systemd/system/timers.target.wants/$name.timer"
printf 'Probe installed from SD; this file is NOT proof of eMMC boot.\n' >"$work/var/lib/$name/INSTALLATION.txt"
cmp "$(readlink -f "$0")" "$work/usr/local/sbin/$name"
sync -f "$work"
cleanup
trap - EXIT
echo 'EMMC_PROBE_INSTALLED. Boot configuration unchanged. No reboot performed.'
