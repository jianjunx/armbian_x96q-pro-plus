#!/bin/bash
# SD-only diagnostic experiment. Never mounts or writes an eMMC device.
set -euo pipefail
mode=${1:-help}
[[ $mode == install || $mode == collect || $mode == arm || $mode == restore ]] || {
    echo 'Usage: sudo bash h728-boot-probe.sh {install|collect|arm|restore}'
    exit 1
}
[[ $EUID == 0 ]] || { echo 'Run as root.'; exit 1; }
[[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || exit 1
[[ $(uname -r) == 7.2.0-7-MANJARO-ARM ]] || exit 1
# Require BOTH root and the exact /boot mount to belong to the same SD.
rootpart=$(readlink -f "$(findmnt -nro SOURCE /)")
bootpart=$(readlink -f "$(findmnt -nr -M /boot -o SOURCE)")
disk=$(lsblk -ndo PKNAME "$rootpart")
[[ $disk =~ ^mmcblk[0-9]+$ ]] || exit 1
[[ $(cat "/sys/class/block/$disk/device/type") == SD ]] || exit 1
[[ $(lsblk -ndo PKNAME "$bootpart") == "$disk" ]] || exit 1
[[ $(findmnt -nr -M /boot -o FSTYPE) == vfat ]] || exit 1
base=/boot/h728-boot-probe-v1
backup=$base/recovery
envfile=/boot/armbianEnv.txt
extfile=/boot/extlinux/extlinux.conf
mkdir -p "$base"

case $mode in
install)
    for cmd in dtc fdtget timeout sha256sum systemctl flock; do command -v "$cmd" >/dev/null; done
    [[ $(tr -d '\0' </proc/device-tree/soc/mmc@4022000/status) == disabled ]] || {
        echo 'Install from the working stock-DTB boot.'; exit 1;
    }
    [[ ! -e /usr/local/sbin/h728-boot-probe-v1 && ! -e /etc/systemd/system/h728-boot-probe-v1.timer && ! -e /etc/systemd/system/h728-boot-probe-v1.service ]] || {
        echo 'Probe already installed; do not overwrite. Use collect, arm or restore.'; exit 1;
    }
    install -m0755 "$(readlink -f "$0")" /usr/local/sbin/h728-boot-probe-v1
    cat >/etc/systemd/system/h728-boot-probe-v1.service <<'EOF'
[Unit]
Description=H728 SD boot evidence snapshot
RequiresMountsFor=/boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/h728-boot-probe-v1 collect
TimeoutStartSec=120
EOF
    cat >/etc/systemd/system/h728-boot-probe-v1.timer <<'EOF'
[Unit]
Description=H728 network-independent diagnostic timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=1

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now h728-boot-probe-v1.timer
    /usr/local/sbin/h728-boot-probe-v1 collect
    echo 'Installed; stock boot unchanged. Inspect baseline before running arm.'
    ;;
collect)
    exec 9>/run/h728-boot-probe-v1.lock
    flock -n 9 || exit 0
    (( $(df -Pk /boot | awk 'END {print $4}') >= 16384 )) || {
        echo 'Less than 16 MiB free on boot; skipping capture.'; exit 1;
    }
    bootid=$(cat /proc/sys/kernel/random/boot_id)
    [[ $bootid =~ ^[0-9a-f-]{36}$ ]] || exit 1
    out=$base/$bootid
    mkdir -p "$out"
    # At most three snapshots per boot; no background sleep and no network wait.
    slot=
    for n in 1 2 3; do
        [[ -e $out/snapshot-$n.txt ]] || { slot=$n; break; }
    done
    [[ -n $slot ]] || exit 0
    capture() {
        printf '\n=== %s ===\n' "$*"
        timeout 10 "$@" || echo "Unavailable/failed: $*"
    }
    {
        capture date -Is
        capture cat /proc/uptime /proc/cmdline /proc/sys/kernel/random/boot_id
        capture uname -a
        capture cat /sys/kernel/debug/regulator/regulator_summary
        capture dmesg
        capture lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
        capture ip -br address
        capture cat /sys/class/net/end0/carrier /sys/class/net/end0/operstate
        capture systemctl --no-pager --failed
    } >"$out/snapshot-$slot.txt.part" 2>&1
    mv "$out/snapshot-$slot.txt.part" "$out/snapshot-$slot.txt"
    if [[ $slot == 1 ]]; then
        dtc -q -I fs -O dts /proc/device-tree >"$out/running.dts" 2>"$out/dtc-errors.txt" || true
        [[ ! -r /sys/firmware/fdt ]] || cp /sys/firmware/fdt "$out/running.dtb"
        cp "$envfile" "$out/armbianEnv.txt"
        cp "$extfile" "$out/extlinux.conf"
        sha256sum /boot/dtb/allwinner/sun55i-h728-x96qpro+*.dtb >"$out/dtb-sha256.txt"
    fi
    sync -f "$base"
    echo "Saved $out/snapshot-$slot.txt"
    ;;
arm)
    systemctl is-enabled --quiet h728-boot-probe-v1.timer
    [[ -s $base/$(cat /proc/sys/kernel/random/boot_id)/snapshot-1.txt ]] || {
        echo 'No baseline snapshot; run collect first.'; exit 1;
    }
    [[ ! -e $backup ]] || { echo 'Recovery already exists; refusing to replace it.'; exit 1; }
    grep -qx 'DEFAULT stock-dtb' "$extfile"
    grep -qx 'fdtfile=allwinner/sun55i-h728-x96qpro+-stock.dtb' "$envfile"
    # Pin the exact two files already inspected, not merely their filenames.
    printf '%s  %s\n' \
      be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567 '/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb' \
      debdd1a481cc322d9d88e236a74d3f28dac1b8fb89606722a33b2bf8c9f57081 '/boot/dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb' | sha256sum -c -
    grep -q '^LABEL armbian-h728$' "$extfile"
    grep -q 'loglevel=7' /proc/cmdline
    mkdir "$backup"
    cp "$envfile" "$backup/armbianEnv.txt"
    cp "$extfile" "$backup/extlinux.conf"
    sync -f "$backup"
    sed -i -E 's/^DEFAULT stock-dtb$/DEFAULT armbian-h728/; s/loglevel=[0-9]+/loglevel=7/g' "$extfile"
    sed -i 's|^fdtfile=.*|fdtfile=allwinner/sun55i-h728-x96qpro+.dtb|' "$envfile"
    # Covers boot.scr fallback, while preserving serial/earlycon arguments.
    sed -i -E 's/(^extraargs=.*) loglevel=[0-9]+/\1/; s/^(extraargs=.*)$/\1 loglevel=7/' "$envfile"
    sync -f /boot
    echo 'Armed. No reboot performed. Recovery: copy both recovery files back to their original locations.'
    ;;
restore)
    [[ -s $backup/armbianEnv.txt && -s $backup/extlinux.conf ]] || exit 1
    cp "$backup/armbianEnv.txt" "$envfile"
    cp "$backup/extlinux.conf" "$extfile"
    sync -f /boot
    echo 'Stock settings restored for NEXT boot. No reboot performed; evidence retained.'
    ;;
esac
