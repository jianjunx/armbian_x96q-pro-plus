"""Log in to the H728 over the serial console and run diagnostics.

The box has a getty on ttyS0 (serial-getty@ttyS0.service). We drive it like
expect(1): wake the prompt, log in, then run each command with a sentinel so
we know where its output ends.
"""

import getpass
import re
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM3"

CMDS = [
    "uname -a",
    "cat /etc/armbian-release 2>/dev/null | head -5",
    "ip -o -4 addr",
    "ip -o link show end0",
    "ethtool end0 2>/dev/null | grep -iE 'link detected|speed|duplex'",
    "cat /sys/class/net/end0/carrier 2>/dev/null",
    "lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS | grep -E 'mmcblk|NAME'",
    "cat /proc/device-tree/soc/mmc@4022000/status; echo",
    "systemctl --failed --no-legend --no-pager",
    "dmesg | grep -iE 'link is up|link is down' | tail -3",
    "dmesg | grep -i 'MDIO device at address' | tail -3; echo mdio-check-done",
    "uptime",
]

ANSI = re.compile(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]")


def clean(data):
    data = ANSI.sub(b"", data)
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data.decode("utf-8", "replace")


def expect(ser, pattern, timeout=40):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        chunk = ser.read(4096)
        if chunk:
            buf += chunk
            if pattern in buf:
                return buf
    return buf


def main():
    ser = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1, timeout=1)

    # Wake the console; we may get either a login prompt or a live shell.
    ser.write(b"\n")
    out = expect(ser, b"login:", 8)
    if b"login:" in out:
        ser.write(b"root\n")
        out = expect(ser, b"assword:", 20)
        if b"assword:" in out:
            password = getpass.getpass("Device root password (not saved): ")
            ser.write(password.encode("utf-8") + b"\n")
            del password
        expect(ser, b"#", 25)
    else:
        # probably already logged in; verify with a probe
        ser.write(b"echo __PROBE__\n")
        out = expect(ser, b"__PROBE__", 10)
        if b"__PROBE__" not in out:
            print("could not reach a shell; last bytes:", clean(out)[-400:])
            return
    time.sleep(0.5)
    ser.read(8192)  # drain banner/motd

    print("=== logged in ===")
    for cmd in CMDS:
        tag = b"__EOF__"
        ser.read(8192)  # drain
        ser.write(cmd.encode() + b"; echo " + tag + b"$?\n")
        out = expect(ser, tag, 60)
        text = clean(out)
        # echo of the command line comes back first; drop up to first newline
        print(f"\n### {cmd}")
        body = text.split("\n", 1)[1] if "\n" in text else text
        body = re.sub(re.escape(tag.decode()) + r"\d*", "", body)
        print(body.strip())


if __name__ == "__main__":
    main()
