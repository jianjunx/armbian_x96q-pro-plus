"""One-pass H728 eMMC diagnosis + flash + cold-boot capture.

Everything that can be learned from a single serial session is collected here,
so the box only has to be power-cycled twice:

  pass 1 (SD card inserted)
    - U-Boot version / environment
    - eMMC identity, partition table
    - whether a U-Boot proper image really sits at the SPL's load sector
    - a multi-block read capability sweep (1 .. 1490 blocks)
    - write the new blob to the eMMC SPL slot and verify it

  pass 2 (SD card removed)
    - capture the cold boot from eMMC

    python h728_emmc_one_pass.py COM3 [filename.bin]

Everything is appended to h728-onepass.txt.
"""

import math
import os
import re
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM3"
FNAME = sys.argv[2] if len(sys.argv) > 2 else "u-boot-sunxi-with-spl-emmc.bin"
DURATION = int(sys.argv[3]) if len(sys.argv) > 3 else 300
# H728_QUICK=1 skips the read-only diagnosis when it has already been
# captured and only the flash + cold boot matter.
QUICK = os.environ.get("H728_QUICK") == "1"
OUT = r"C:\Users\jjxie\WorkBuddy\2026-09-09-20-53-08\h728-onepass.txt"

LOAD_ADDR = 0x42000000
MIRROR_ADDR = 0x50000000
START_BLK = 0x10          # sector 16 == byte 8192, the eMMC SPL slot
UBOOT_SECTOR = 0x50       # where the SPL expects U-Boot proper (0x40 + 0x10)
MAX_BYTES = 2 * 1024 * 1024

# Block counts for the multi-block read sweep. 1490 is the transfer the SPL
# actually issues when it loads U-Boot proper.
SWEEP = [1, 2, 8, 16, 64, 128, 512, 1490]

ANSI = re.compile(
    rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]|[\x00-\x08\x0b-\x1f\x7f]"
)


def clean(data: bytes) -> str:
    data = ANSI.sub(b"", data).replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data.decode("utf-8", "replace")


def main() -> int:
    ser = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1, timeout=1)
    log = open(OUT, "a", encoding="utf-8")

    def emit(text: str) -> None:
        print(text, end="")
        log.write(text)
        log.flush()

    def pump(patterns, timeout) -> bytearray:
        buf = bytearray()
        start = time.time()
        while time.time() - start < timeout:
            chunk = ser.read(4096)
            if chunk:
                buf += chunk
                for p in patterns:
                    if p in buf:
                        return buf
        return buf

    def run(cmd, timeout=30) -> str:
        ser.write(cmd.encode() + b"\n")
        out = bytes(pump([b"=>"], timeout))
        if b"=>" not in out:
            emit(f"\n### {cmd}\n[no prompt within {timeout}s]\n")
            ser.write(b"\x03")
            out += bytes(pump([b"=>"], 5))
        body = clean(out)
        emit(f"\n### {cmd}\n{body.rstrip()}\n")
        return body

    def section(title: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        emit(f"\n\n===== {title} ({stamp}) =====\n")

    section("pass 1: diagnosis from the SD card boot")

    print("waiting for the U-Boot prompt; cold-power the box now ...")
    for escape in (b"\x1b", b"\x03"):
        ser.write(escape)
        if b"=>" in pump([b"=>"], 3):
            break
    else:
        deadline = time.time() + 420
        buf = bytearray()
        while time.time() < deadline and b"=>" not in buf:
            ser.write(b" ")
            buf += pump([b"=>"], 0.15)
        if b"=>" not in buf:
            emit("\nABORTED: never reached the U-Boot prompt\n")
            return 1
    emit("=== at U-Boot prompt ===\n")

    if not QUICK:
        run("version", 15)

    # ---- eMMC identity ---------------------------------------------------
    emmc = run("mmc dev 1", 20)
    if "is current device" not in emmc and "mmc1" not in emmc:
        emit("\nABORTED: eMMC (mmc dev 1) did not come up\n")
        return 1
    info = run("mmc info", 20)
    if "Capacity" not in info:
        emit("\nABORTED: eMMC reported no capacity\n")
        return 1

    if not QUICK:
        run("mmc part", 30)

    # ---- is there really a payload where the SPL will look? --------------
    # The SPL loads raw from sector 0x50. If that area is empty, fixing the
    # SPL read would still not produce a boot, so check it before writing.
    if not QUICK:
        run(f"mmc read 0x{LOAD_ADDR:x} 0x{UBOOT_SECTOR:x} 0x8", 60)
        run(f"md.b 0x{LOAD_ADDR:x} 0x40", 20)

    # ---- multi-block read capability sweep --------------------------------
    # U-Boot proper takes the DM path, so this does not reproduce the SPL's
    # legacy path exactly, but it shows whether the device itself stalls on
    # large transfers and where the cliff is.
    emit("\n----- multi-block read sweep on eMMC (sector 0x10) -----\n")
    for n in ([] if QUICK else SWEEP):
        out = run(f"mmc read 0x{LOAD_ADDR:x} 0x{START_BLK:x} 0x{n:x}", 60)
        m = re.search(r"(\d+)\s+blocks? read", out)
        emit(f"  sweep {n:5d}: {'ok' if m and int(m.group(1)) == n else 'FAILED'}\n")

    # ---- environment -----------------------------------------------------
    if not QUICK:
        run("printenv bootcmd bootargs boot_targets boot_prefixes", 30)

    # ---- load from SD and write to eMMC ----------------------------------
    section("pass 1: flashing the new blob")

    sd = run("mmc dev 0", 20)
    if "is current device" not in sd and "mmc0" not in sd:
        emit("\nABORTED: SD card (mmc dev 0) did not come up\n")
        return 1

    listing = run("fatls mmc 0:1 /", 30)
    if FNAME not in listing:
        emit(f"\nABORTED: {FNAME} not found on the SD card FAT partition\n")
        return 1

    loaded = run(f"fatload mmc 0:1 0x{LOAD_ADDR:x} /{FNAME}", 120)
    m = re.search(r"(\d+)\s+bytes read", loaded)
    if not m:
        emit("\nABORTED: fatload reported no byte count\n")
        return 1
    size = int(m.group(1))
    if not (0 < size <= MAX_BYTES):
        emit(f"\nABORTED: implausible blob size {size}\n")
        return 1
    sectors = math.ceil(size / 512)
    emit(f"\n[ok] loaded {size} bytes -> {sectors} sectors\n")

    run("mmc dev 1", 20)
    wrote = run(f"mmc write 0x{LOAD_ADDR:x} 0x{START_BLK:x} 0x{sectors:x}", 240)
    m = re.search(r"(\d+)\s+blocks? written", wrote)
    if not m or int(m.group(1)) != sectors:
        emit("\nABORTED: mmc write did not report the expected block count\n")
        return 1

    run(f"mmc read 0x{MIRROR_ADDR:x} 0x{START_BLK:x} 0x{sectors:x}", 240)
    cmp_out = run(f"cmp.b 0x{LOAD_ADDR:x} 0x{MIRROR_ADDR:x} 0x{size:x}", 60)
    ok = "were the same" in cmp_out
    emit(f"\n[{'ok' if ok else 'FAILED'}] read-back comparison\n")

    # ---- pass 2 ----------------------------------------------------------
    section("pass 2: cold boot from eMMC")
    emit(f">>> power off, REMOVE the SD card, power on. Capturing for {DURATION} s.\n")
    print(">>> power off, remove the SD card, power on ...")

    # Give the user a moment, then drop anything buffered from pass 1.
    time.sleep(3)
    ser.reset_input_buffer()

    capture = bytearray()
    deadline = time.time() + DURATION
    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            capture += chunk
    text = clean(bytes(capture))
    emit(text)

    emit("\n\n----- pass 2 summary -----\n")
    for marker, label in (
        ("U-Boot SPL", "SPL banner"),
        ("H728DBG bread fail", "multi-block read failed"),
        ("H728DBG bread recovered", "single-block fallback recovered"),
        ("H728DBG single fail", "single-block read failed"),
        ("mmc block read error", "SPL block read error"),
        ("U-Boot 2025", "U-Boot proper reached"),
        ("Starting kernel", "kernel started"),
    ):
        n = text.count(marker)
        emit(f"  {label:32s}: {n}\n")

    log.close()
    print(f"\ntranscript -> {OUT}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
