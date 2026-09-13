"""Regenerate the H728 eMMC U-Boot patches from upstream sources.

Produces two files in revision-v3/:

  uboot-emmc.patch             - always applied; the real fix
  uboot-emmc-spl-debug.patch   - applied only when H728_UBOOT_DEBUG=1

Both are generated with difflib from the pinned upstream commit rather than
hand-written hunks: a hand-written hunk silently passed `git apply` while
GNU patch(1) inside the container rejected it (empty context lines had been
stripped to bare empty lines).

The device-tree hunk is preserved verbatim from the existing patch; only the
two driver hunks are regenerated.

    python revision-v3/gen-patches.py
"""

import difflib
import urllib.parse
import urllib.request
from pathlib import Path

UBOOT_COMMIT = "b99f4a9e0778f4f402619d70976537d4833d7eab"
BASE_URL = "https://raw.githubusercontent.com/apritzel/u-boot/" + UBOOT_COMMIT

REPO = Path(__file__).resolve().parent.parent
REV = REPO / "revision-v3"

SUNXI_MMC = "drivers/mmc/sunxi_mmc.c"
MMC = "drivers/mmc/mmc.c"


def fetch(path: str) -> str:
    url = BASE_URL + "/" + urllib.parse.quote(path)
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8").replace("\r\n", "\n")


def diff(from_src: str, to_src: str, path: str) -> str:
    d = difflib.unified_diff(
        from_src.splitlines(keepends=True),
        to_src.splitlines(keepends=True),
        fromfile="a/" + path,
        tofile="b/" + path,
        n=3,
    )
    return "".join(d)


def replace_once(src: str, old: str, new: str) -> str:
    assert src.count(old) == 1, "anchor not unique: %r" % old[:70]
    return src.replace(old, new)


# --------------------------------------------------------------------------
# fix 1: SPL takes the legacy branch of sunxi_mmc.c and never reads the DT
# --------------------------------------------------------------------------
def fix_sunxi_mmc(src: str) -> str:
    old = (
        "\tcfg->f_min = 400000;\n"
        "\tcfg->f_max = 52000000;\n"
        "\n"
        "\tif (mmc_resource_init(sdc_no) != 0)"
    )
    new = (
        "\tcfg->f_min = 400000;\n"
        "\tcfg->f_max = 52000000;\n"
        "\n"
        "\t/* H728 / A523: the SPL build has no device tree and no driver\n"
        "\t * model, so the hard-coded values above are all it will ever see.\n"
        "\t * The sunxi driver lacks A523 new-timing calibration, and 8-bit at\n"
        "\t * 52 MHz is the one eMMC mode that fails on this board: SPL dies\n"
        '\t * with "mmc block read error". Force what U-Boot proper only\n'
        "\t * reaches through its fallback ladder: 1-bit at 26 MHz.\n"
        "\t *\n"
        "\t * b_max is capped here too, and only here: this is the legacy\n"
        "\t * branch, which is what the SPL compiles without SPL_DM, while\n"
        "\t * U-Boot proper takes the DM branch below and keeps reading the\n"
        "\t * kernel in large transfers. Instrumented runs showed single-block\n"
        "\t * reads succeeding and a 1490-block CMD18 stalling until it timed\n"
        "\t * out, so the SPL reads one block per request and never enters the\n"
        "\t * failing path at all. Capping the global\n"
        "\t * CONFIG_SYS_MMC_MAX_BLK_COUNT instead would make each failed\n"
        "\t * chunk pay the ~3 s timeout, 24 times over.\n"
        "\t */\n"
        "\tif (IS_ENABLED(CONFIG_MACH_SUN55I_A523) && sdc_no == 2) {\n"
        "\t\tcfg->host_caps &= ~(MMC_MODE_8BIT | MMC_MODE_4BIT |\n"
        "\t\t\t\t    MMC_MODE_HS_52MHz);\n"
        "\t\tcfg->f_max = 26000000;\n"
        "\t\tcfg->b_max = 1;\n"
        "\t}\n"
        "\n"
        "\tif (mmc_resource_init(sdc_no) != 0)"
    )
    return replace_once(src, old, new)


# --------------------------------------------------------------------------
# fix 2: a multi-block transfer can stall; retry block by block
# --------------------------------------------------------------------------
def fix_mmc_bread(src: str) -> str:
    old = (
        "\t\tif (mmc_read_blocks(mmc, dst, start, cur) != cur) {\n"
        '\t\t\tpr_debug("%s: Failed to read blocks\\n", __func__);\n'
        "\t\t\treturn 0;\n"
        "\t\t}\n"
    )
    new = (
        "\t\tif (mmc_read_blocks(mmc, dst, start, cur) != cur) {\n"
        "\t\t\tlbaint_t i;\n"
        "\n"
        '\t\t\tpr_debug("%s: Failed to read blocks\\n", __func__);\n'
        "\t\t\t/*\n"
        "\t\t\t * H728 / A523: the sunxi host has no new-timing calibration,\n"
        "\t\t\t * so a multi-block transfer to the eMMC can stall without ever\n"
        "\t\t\t * raising command-done. That is how the SPL died with \"mmc\n"
        "\t\t\t * block read error\" before reaching U-Boot proper. Single-block\n"
        "\t\t\t * reads on the same device were proven to succeed, so retry\n"
        "\t\t\t * block by block instead of failing the whole load.\n"
        "\t\t\t */\n"
        "\t\t\tfor (i = 0; i < cur; i++) {\n"
        "\t\t\t\tif (mmc_read_blocks(mmc, (char *)dst +\n"
        "\t\t\t\t\t\t    i * mmc->read_bl_len,\n"
        "\t\t\t\t\t\t    start + i, 1) != 1)\n"
        "\t\t\t\t\treturn 0;\n"
        "\t\t\t}\n"
        "\t\t}\n"
    )
    return replace_once(src, old, new)


# --------------------------------------------------------------------------
# debug instrumentation (never part of an installable blob)
# --------------------------------------------------------------------------
def add_debug(src: str) -> str:
    subs = [
        (
            '\tdebug("set ios: bus_width: %x, clock: %d\\n",\n'
            "\t      mmc->bus_width, mmc->clock);\n",
            '\tdebug("set ios: bus_width: %x, clock: %d\\n",\n'
            "\t      mmc->bus_width, mmc->clock);\n"
            '\tprintf("H728DBG ios bw=%d clk=%d\\n", mmc->bus_width, mmc->clock);\n',
            True,
        ),
        (
            "\t\twritel(data->blocksize, &priv->reg->blksz);\n"
            "\t\twritel(data->blocks * data->blocksize, &priv->reg->bytecnt);\n"
            "\t}\n",
            "\t\twritel(data->blocksize, &priv->reg->blksz);\n"
            "\t\twritel(data->blocks * data->blocksize, &priv->reg->bytecnt);\n"
            "\t}\n"
            '\tprintf("H728DBG cmd=%d blks=%d bs=%d bc=%u\\n", cmd->cmdidx,\n'
            "\t       data ? data->blocks : 0, data ? data->blocksize : 0,\n"
            "\t       data ? (unsigned)(data->blocks * data->blocksize) : 0);\n",
            True,
        ),
        (
            "\tif (timeout_msecs < 2000)\n\t\ttimeout_msecs = 2000;\n",
            "\tif (timeout_msecs < 2000)\n\t\ttimeout_msecs = 2000;\n"
            '\tprintf("H728DBG pio words=%u tmo=%u\\n", word_cnt, timeout_msecs);\n',
            False,
        ),
        (
            "\t\twhile ((status = readl(&priv->reg->status)) & status_bit) {\n"
            "\t\t\tif (get_timer(start) > timeout_msecs)\n"
            "\t\t\t\treturn -1;\n"
            "\t\t}\n",
            "\t\twhile ((status = readl(&priv->reg->status)) & status_bit) {\n"
            "\t\t\tif (get_timer(start) > timeout_msecs) {\n"
            '\t\t\t\tprintf("H728DBG pio TMO word %u/%u st=%x\\n", i, word_cnt,\n'
            "\t\t\t\t       status);\n"
            "\t\t\t\treturn -1;\n"
            "\t\t\t}\n"
            "\t\t}\n",
            False,
        ),
        (
            "\t\tret = mmc_trans_data_by_cpu(priv, mmc, data);\n\t\tif (ret) {\n",
            "\t\tret = mmc_trans_data_by_cpu(priv, mmc, data);\n\t\tif (ret) {\n"
            '\t\t\tprintf("H728DBG pio fail ret=%d rint=%x\\n", ret,\n'
            "\t\t\t       readl(&priv->reg->rint));\n",
            False,
        ),
        (
            '\t\t\t\t      "data");\n\t\tif (error)\n\t\t\tgoto out;\n',
            '\t\t\t\t      "data");\n\t\tif (error) {\n'
            '\t\t\tprintf("H728DBG datawait err=%d rint=%x\\n", error,\n'
            "\t\t\t       readl(&priv->reg->rint));\n"
            "\t\t\tgoto out;\n\t\t}\n",
            False,
        ),
    ]
    for old, new, once in subs:
        n = src.count(old)
        assert n >= 1, "debug anchor not found: %r" % old[:60]
        src = src.replace(old, new, 1) if once else src.replace(old, new)
    return src


def add_debug_mmc(src: str) -> str:
    src = replace_once(
        src,
        "\t\tif (mmc_read_blocks(mmc, dst, start, cur) != cur) {\n\t\t\tlbaint_t i;\n",
        "\t\tif (mmc_read_blocks(mmc, dst, start, cur) != cur) {\n"
        "\t\t\tlbaint_t i;\n"
        "\n"
        '\t\t\tprintf("H728DBG bread fail start=%lu cur=%lu\\n",\n'
        "\t\t\t       (unsigned long)start, (unsigned long)cur);\n",
    )
    return replace_once(
        src,
        "\t\t\tfor (i = 0; i < cur; i++) {\n"
        "\t\t\t\tif (mmc_read_blocks(mmc, (char *)dst +\n"
        "\t\t\t\t\t\t    i * mmc->read_bl_len,\n"
        "\t\t\t\t\t\t    start + i, 1) != 1)\n"
        "\t\t\t\t\treturn 0;\n"
        "\t\t\t}\n",
        "\t\t\tfor (i = 0; i < cur; i++) {\n"
        "\t\t\t\tif (mmc_read_blocks(mmc, (char *)dst +\n"
        "\t\t\t\t\t\t    i * mmc->read_bl_len,\n"
        "\t\t\t\t\t\t    start + i, 1) != 1) {\n"
        '\t\t\t\t\tprintf("H728DBG single fail at %lu\\n",\n'
        "\t\t\t\t\t       (unsigned long)(start + i));\n"
        "\t\t\t\t\treturn 0;\n"
        "\t\t\t\t}\n"
        "\t\t\t}\n"
        '\t\t\tprintf("H728DBG bread recovered\\n");\n',
    )


def main() -> None:
    print("fetching pristine sources ...")
    sunxi_src = fetch(SUNXI_MMC)
    mmc_src = fetch(MMC)

    existing = (
        (REV / "uboot-emmc.patch").read_bytes().decode("utf-8").replace("\r\n", "\n")
    )
    dts_hunk = existing.split("--- a/drivers")[0].rstrip("\n")
    assert dts_hunk.startswith("--- a/arch"), "device-tree hunk not found"

    fixed_sunxi = fix_sunxi_mmc(sunxi_src)
    fixed_mmc = fix_mmc_bread(mmc_src)

    parts = [
        dts_hunk,
        diff(sunxi_src, fixed_sunxi, SUNXI_MMC).rstrip("\n"),
        diff(mmc_src, fixed_mmc, MMC).rstrip("\n"),
    ]
    (REV / "uboot-emmc.patch").write_bytes(("\n".join(parts) + "\n").encode("utf-8"))
    print("wrote revision-v3/uboot-emmc.patch")

    dbg_sunxi = add_debug(fixed_sunxi)
    dbg_mmc = add_debug_mmc(fixed_mmc)
    dbg_parts = [
        diff(fixed_sunxi, dbg_sunxi, SUNXI_MMC).rstrip("\n"),
        diff(fixed_mmc, dbg_mmc, MMC).rstrip("\n"),
    ]
    (REV / "uboot-emmc-spl-debug.patch").write_bytes(
        ("\n".join(dbg_parts) + "\n").encode("utf-8")
    )
    print("wrote revision-v3/uboot-emmc-spl-debug.patch")


if __name__ == "__main__":
    main()
