#!/bin/bash
# Install the firmware/governor fix on v2, or into an offline mounted v2 rootfs.
set -euo pipefail
src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=
offline=no
if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && $1 == --root && -d $2 && $2 != / ]] || {
        echo 'Usage: sudo bash install.sh [--root /mounted-v2-rootfs]' >&2; exit 1;
    }
    root=$(realpath "$2")
    [[ $root != / ]] || exit 1
    offline=yes
fi
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
version=6.17.0-rc1-2-MANJARO-ARM+
[[ -d $root/lib/modules/$version && -f $root/etc/armbian-release ]] || {
    echo 'This repair requires the H728 Armbian v2 root filesystem.' >&2; exit 1;
}
if [[ $offline == no ]]; then
    [[ $(uname -r) == "$version" ]] || { echo 'Unexpected running kernel.' >&2; exit 1; }
    [[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || exit 1
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        grep -qw schedutil "$policy/scaling_available_governors" || exit 1
    done
fi
(cd "$src" && sha256sum -c SHA256SUMS)
install -d "$root/var/backups"
backup=$(mktemp -d "$root/var/backups/h728-v2.1.XXXXXX")
for path in etc/default/cpufrequtils usr/lib/firmware/aic8800_sdio usr/local/sbin/h728-diagnostics; do
    if [[ -e $root/$path ]]; then
        mkdir -p "$backup/$(dirname "$path")"
        cp -a "$root/$path" "$backup/$path"
    fi
done
install -d "$root/usr/lib/firmware/aic8800_sdio" "$root/etc/default"
install -m0644 "$src"/firmware/* "$root/usr/lib/firmware/aic8800_sdio/"
install -D -m0755 "$src/h728-diagnostics" "$root/usr/local/sbin/h728-diagnostics"
config=$root/etc/default/cpufrequtils
temporary=$(mktemp "$root/etc/default/.h728-cpufreq.XXXXXX")
if [[ -f $config ]]; then
    awk '!/^[[:space:]]*(export[[:space:]]+)?(GOVERNOR|MIN_SPEED)=/' "$config" >"$temporary"
fi
printf '\n# H728 v2.1: scheduler-driven DVFS; retain the existing maximum frequency.\nGOVERNOR=schedutil\nMIN_SPEED=408000\n' >>"$temporary"
chmod 0644 "$temporary"
mv "$temporary" "$config"
if [[ $offline == no ]]; then
    systemctl enable armbian-hardware-optimize.service
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        printf '408000\n' >"$policy/scaling_min_freq"
        printf 'schedutil\n' >"$policy/scaling_governor"
    done
else
    systemctl --root="$root" enable armbian-hardware-optimize.service
fi
echo "Installed firmware and schedutil configuration. Backup: $backup"
echo 'Reboot when ready so the previously failed Wi-Fi driver can initialize again.'
