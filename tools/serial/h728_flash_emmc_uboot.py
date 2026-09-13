"""Retired unsafe UART writer. Intentionally never opens a serial port."""

import sys


def main():
    print(
        "STOP: legacy UART flashing is disabled. It did not verify CID, "
        "hardware partition, partition boundaries, backup or final device selection. "
        "No serial port was opened and nothing was written. "
        "Keep the working eMMC and recovery SD unchanged. "
        "See tools/serial/README.md.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
