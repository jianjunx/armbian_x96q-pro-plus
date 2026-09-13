"""Retired diagnosis/automatic-write combination; fail before serial access."""

from h728_flash_emmc_uboot import main


if __name__ == "__main__":
    raise SystemExit(main())
