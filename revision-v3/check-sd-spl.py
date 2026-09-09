"""Check whether an SD card is still *bootable*, not just readable.

Windows can read the FAT partition fine while the Allwinner SPL that lives
OUTSIDE any partition (offset 8 KiB on the raw card) is damaged -- that yields
exactly the symptom "all files present, box completely dead".

Read-only. Requires an elevated (administrator) shell for raw disk access.
"""

import ctypes
import struct
import sys

GENERIC_READ = 0x80000000
FILE_SHARE_READ = 1
FILE_SHARE_WRITE = 2
OPEN_EXISTING = 3
IOCTL_DISK_GET_LENGTH_INFO = 0x7405C

SIZE_HINT_GB = (100, 140)  # the v3 SD card is 116.5 GB


def open_drive(n):
    path = rf"\\.\PhysicalDrive{n}"
    h = ctypes.windll.kernel32.CreateFileW(
        path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        None, OPEN_EXISTING, 0, None)
    if h == ctypes.c_ulonglong(-1).value or h == -1:
        return None
    return h


def drive_size(h):
    class LARGE(ctypes.Structure):
        _fields_ = [("Length", ctypes.c_longlong)]

    buf = LARGE()
    returned = ctypes.c_ulong(0)
    ok = ctypes.windll.kernel32.DeviceIoControl(
        h, IOCTL_DISK_GET_LENGTH_INFO, None, 0,
        ctypes.byref(buf), ctypes.sizeof(buf),
        ctypes.byref(returned), None)
    return buf.Length if ok else 0


def pread(h, offset, length):
    ctypes.windll.kernel32.SetFilePointerEx(
        h, ctypes.c_longlong(offset), None, 0)
    buf = ctypes.create_string_buffer(length)
    read = ctypes.c_ulong(0)
    ok = ctypes.windll.kernel32.ReadFile(
        h, buf, length, ctypes.byref(read), None)
    return buf.raw[: read.value] if ok else b""


def hexdump(data, base=0, width=16):
    out = []
    for i in range(0, len(data), width):
        chunk = data[i:i + width]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append(f"  {base + i:08x}  {hexs:<{width * 3}}  {asc}")
    return "\n".join(out)


def main():
    drives = []
    for n in range(0, 12):
        h = open_drive(n)
        if h is None:
            continue
        size = drive_size(h)
        mbr = pread(h, 0, 512)
        spl = pread(h, 8192, 512)
        ctypes.windll.kernel32.CloseHandle(h)
        drives.append((n, size, mbr, spl))

    if not drives:
        print("No physical drives could be opened.")
        print("Run this from an elevated (administrator) PowerShell.")
        return 1

    print("=" * 72)
    print(" Physical drives (read-only raw inspection)")
    print("=" * 72)
    for n, size, mbr, spl in drives:
        gb = size / (1024 ** 3)
        tag = ""
        if SIZE_HINT_GB[0] <= gb <= SIZE_HINT_GB[1]:
            tag = "   <== candidate: looks like the 116.5 GB SD card"
        print(f"\nPhysicalDrive{n}  {gb:7.1f} GB{tag}")
        mbr_sig = mbr[510:512]
        sig_ok = mbr_sig == b"\x55\xaa"
        print(f"  MBR signature : {mbr_sig.hex()}"
              f"  ({'valid 0x55AA' if sig_ok else 'MISSING'})")
        if mbr[0x1c2:0x1c6] == b"\xee\xee\xee" or (
                mbr[450:458] == b"EFI PART"):
            print("  partition table: GPT")
        else:
            for i in range(4):
                off = 0x1BE + i * 16
                entry = mbr[off:off + 16]
                if entry == b"\x00" * 16:
                    continue
                status, ptype = entry[0], entry[4]
                lba, sect = struct.unpack("<II", entry[8:16])
                print(f"  partition {i + 1}: status=0x{status:02x} "
                      f"type=0x{ptype:02x} start_sector={lba} "
                      f"sectors={sect} ({sect * 512 / 1024 ** 3:.1f} GB)")

        magic = b"eGON.BT0" in spl or b"eGON" in spl
        uboot = b"U-Boot" in spl or b"SPL" in spl
        print(f"  SPL @ 8 KiB  : eGON magic={'YES' if magic else 'NO '} "
              f"| U-Boot/SPL string={'YES' if uboot else 'NO '}"
              f"   {'==> BOOTABLE' if (magic or uboot) else '==> NOT BOOTABLE'}")
        print("  first 64 bytes at 8 KiB:")
        print(hexdump(spl[:64], base=8192))

    print("\n" + "=" * 72)
    print(" Look for the 116.5 GB drive. If it reports 'NOT BOOTABLE'")
    print(" at 8 KiB, the FAT files being fine does not matter: the SoC")
    print(" never finds SPL and the box stays completely dark.")
    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
