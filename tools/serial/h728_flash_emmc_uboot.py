"""Write a new eMMC U-Boot blob to the eMMC user area over the serial console.

Run this from the SD card boot (which always works), interrupt autoboot, then
load the blob from the SD card's FAT partition and write it to the eMMC user
area at byte offset 8192 (sector 16). No Linux root and no network needed.

    python h728_flash_emmc_uboot.py COM3 [filename.bin]

Beforehand: copy u-boot-sunxi-with-spl-emmc.bin onto the SD card's FAT
partition (the Windows-visible drive, e.g. F:\\).

The eMMC partition table starts at 1 MiB, so overwriting the first ~800 KiB
touches only the bootloader area. The SD card is never written.
"""

import math
import re
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM3"
FNAME = sys.argv[2] if len(sys.argv) > 2 else "u-boot-sunxi-with-spl-emmc.bin"
LOG = r"C:\Users\jjxie\WorkBuddy\2026-09-09-20-53-08\h728-emmc-flash.txt"

LOAD_ADDR = 0x42000000   # where fatload puts the blob
MIRROR_ADDR = 0x50000000  # where the read-back for cmp.b goes
START_BLK = 0x10          # sector 16 == byte offset 8192, the eMMC SPL slot
MAX_BYTES = 2 * 1024 * 1024

ANSI = re.compile(
    rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]|[\x00-\x08\x0b-\x1f\x7f]"
)


def clean(data: bytes) -> str:
    data = ANSI.sub(b"", data).replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data.decode("utf-8", "replace")


def main() -> int:
    ser = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1, timeout=1)
    transcript = bytearray()

    def pump_until(patterns, timeout) -> bytes:
        nonlocal transcript
        buf = bytearray()
        start = time.time()
        while time.time() - start < timeout:
            chunk = ser.read(4096)
            if chunk:
                buf += chunk
                transcript += chunk
                for p in patterns:
                    if p in buf:
                        return bytes(buf)
        return bytes(buf)

    def run(cmd, timeout=30) -> str:
        ser.write(cmd.encode() + b"\n")
        out = pump_until([b"=>"], timeout)
        body = clean(bytes(out))
        print(f"\n### {cmd}\n{body.rstrip()}")
        return body

    def abort(msg) -> int:
        print(f"\nABORTED: {msg}")
        print("Nothing was written to the eMMC.")
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("\n===== flash attempt %s =====\n" % time.strftime("%H:%M:%S"))
            f.write(clean(bytes(transcript)))
        return 1

    print("trying to reach U-Boot prompt...")
    for escape in (b"\x1b", b"\x03"):
        ser.write(escape)
        out = pump_until([b"=>"], 3)
        if b"=>" in out:
            break
    else:
        print("spamming keys; cold-power the box now (SD card inserted)...")
        deadline = time.time() + 420
        got = False
        buf = bytearray()
        while time.time() < deadline and not got:
            ser.write(b" ")
            chunk = pump_until([b"=>"], 0.15)
            buf += chunk
            if b"=>" in buf:
                got = True
        out = bytes(buf)
    if b"=>" not in out:
        return abort("could not reach the U-Boot prompt")
    print("=== at U-Boot prompt ===")

    # --- Identify both devices before touching anything -------------------
    emmc = run("mmc dev 1", 20)
    if "is current device" not in emmc and "mmc1" not in emmc:
        return abort("eMMC (mmc dev 1) did not come up")
    emmc_info = run("mmc info", 20)
    if "Capacity" not in emmc_info:
        return abort("eMMC reported no capacity; refusing to write")

    sd = run("mmc dev 0", 20)
    if "is current device" not in sd and "mmc0" not in sd:
        return abort("SD card (mmc dev 0) did not come up")

    # --- Load the blob from the SD card -----------------------------------
    listing = run(f"fatls mmc 0:1 /", 30)
    if FNAME not in listing:
        return abort(f"{FNAME} not found on the SD card FAT partition")

    loaded = run(f"fatload mmc 0:1 0x{LOAD_ADDR:x} /{FNAME}", 120)
    m = re.search(r"(\d+)\s+bytes read", loaded)
    if not m:
        return abort("fatload did not report a byte count")
    size = int(m.group(1))
    if not (0 < size <= MAX_BYTES):
        return abort(f"implausible blob size {size}")
    sectors = math.ceil(size / 512)
    print(f"\n[ok] loaded {size} bytes -> {sectors} sectors")

    # --- Write to the eMMC SPL slot and verify ----------------------------
    run("mmc dev 1", 20)
    wrote = run(f"mmc write 0x{LOAD_ADDR:x} 0x{START_BLK:x} 0x{sectors:x}", 180)
    m = re.search(r"(\d+)\s+blocks? written", wrote)
    if not m:
        return abort("mmc write did not report blocks written")
    if int(m.group(1)) != sectors:
        return abort(f"wrote {m.group(1)} blocks, expected {sectors}")

    run(f"mmc read 0x{MIRROR_ADDR:x} 0x{START_BLK:x} 0x{sectors:x}", 180)
    cmp_out = run(f"cmp.b 0x{LOAD_ADDR:x} 0x{MIRROR_ADDR:x} 0x{size:x}", 60)
    if "were the same" not in cmp_out:
        return abort("read-back comparison did not confirm the write")

    print(f"\n=== SUCCESS ===")
    print(f"Wrote {FNAME} ({size} bytes, {sectors} sectors) to eMMC sector 16.")
    print("Read-back comparison passed.")
    print("\nNext: power off, remove the SD card, power on, and watch the")
    print("serial console. Expected: 'U-Boot SPL ... H728 eMMC v3' followed by")
    print("U-Boot proper instead of 'mmc block read error'.")

    with open(LOG, "a", encoding="utf-8") as f:
        f.write("\n===== flash %s =====\n" % time.strftime("%H:%M:%S"))
        f.write(clean(bytes(transcript)))
    print(f"\ntranscript -> {LOG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
