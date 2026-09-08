# X96Q Pro+ H728 v2: explicit paths for the separate FAT boot partition.
# Settings are read from armbianEnv.txt. Extlinux is also supplied.
setenv verbosity 7
setenv rootfstype ext4
setenv bootpart ${devnum}:1
setenv env_addr 0x45000000
if load mmc ${bootpart} ${env_addr} armbianEnv.txt; then
    env import -t ${env_addr} ${filesize}
fi
setenv bootargs "root=${rootdev} rootwait rw rootfstype=${rootfstype} console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=${verbosity} panic=10 ${extraargs}"
if load mmc ${bootpart} ${kernel_addr_r} Image; then
    if load mmc ${bootpart} ${fdt_addr_r} dtb/allwinner/sun55i-h728-x96qpro+.dtb; then
        if load mmc ${bootpart} ${ramdisk_addr_r} uInitrd; then
            booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
        fi
    fi
fi
echo "H728 v2: boot file load failed; inspect FAT partition and UART log."
