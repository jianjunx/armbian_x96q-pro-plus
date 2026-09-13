"""Capture the H728 serial console to a log file.

Opens COM3 @ 115200 8N1 and appends everything received to the log until the
time budget runs out. Raw bytes are kept verbatim; a decoded, ANSI-stripped
view is written alongside for readability.

Run in the background, then cold-power the box. The BROM SPL banner is the
first thing you want to see; silence means a wiring problem, not a brick.
"""

import re
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM3"
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 180
RAW_LOG = r"C:\Users\jjxie\WorkBuddy\2026-09-09-20-53-08\h728-serial-raw.bin"
TXT_LOG = r"C:\Users\jjxie\WorkBuddy\2026-09-09-20-53-08\h728-serial.txt"

ANSI = re.compile(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]|[\x00-\x08\x0b-\x1f\x7f]")


def main():
    ser = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1, timeout=1)
    t0 = time.time()
    total = 0
    with open(RAW_LOG, "ab") as raw, open(TXT_LOG, "a", encoding="utf-8") as txt:
        raw.write(b"\n===== capture start %s =====\n" % time.strftime("%H:%M:%S").encode())
        txt.write(f"\n===== capture start {time.strftime('%H:%M:%S')} =====\n")
        while time.time() - t0 < SECONDS:
            chunk = ser.read(4096)
            if not chunk:
                continue
            total += len(chunk)
            raw.write(chunk)
            raw.flush()
            clean = ANSI.sub(b"", chunk).replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            try:
                txt.write(clean.decode("utf-8", "replace"))
            except Exception:
                pass
            txt.flush()
    print(f"done: {total} bytes in {SECONDS:.0f}s -> {RAW_LOG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
