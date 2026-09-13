# GitHub Actions build pipelines

Two independent workflows exist:

- `image-release.yml` assembles and publishes the full SD image (described below).
- `uboot-emmc.yml` builds only the eMMC bootloader blob (see the last section).

Neither builds Linux from source.

## SD image assembly

The workflow builds v3.1 from six pinned, pristine offline inputs, NOT from a
physical SD/eMMC backup. No private diagnostics or keys belong in the bundle.
The native `ubuntu-24.04-arm` runner executes loop/mount/chroot in a privileged
Ubuntu container. No physical device is attached. It does not build Linux
from source or update Trixie packages. CI host packages may update; image
packages remain pinned to the original v3 base and the local +h728.5 DTB repair.
Current output is v3.1.1 with Wi-Fi 24 MHz ceiling and a 20 MHz fallback DTB.

## One-time bootstrap

The repository bootstrap was completed on 2026-09-10: `build-inputs-v3` is a
public prerelease, and Actions run 34463277020 downloaded it successfully. The
steps below document how to recreate the bootstrap after an intentional input
change or in another repository; do not repeat them for normal builds.

1. Review third-party binary redistribution conditions (especially the AIC
   firmware's unknown license) before making the input/image assets public.
2. Run `pack-inputs.sh /path/to/inputs.sha256` inside `h728-image-build`.
   It checks every input and creates `/armbian/output/ci-inputs/h728-v3-inputs.tar.xz`.
3. Copy the generated `.sha256` into tracked `ci/bundle.sha256`; review/commit.
4. Upload the bundle to a separate `build-inputs-v3` Release in this repository.
   This is an archival build input, not a recommended flashable release.
   Never replace it with a device backup or a different image under the same name.
5. Push build-related code to main: the workflow builds and publishes under a
   unique `v3.1.1-ci.<run>.<attempt>` tag. Alternatively push a new v3.1 tag, or manually
   run workflow_dispatch on main or a v3.1 release tag. Documentation-only pushes
   outside the build directories do not trigger another image build.

The build fails closed if the input release is missing or a checksum changes.
Publishing requires only the workflow's GITHUB_TOKEN; do not commit a PAT.
Local SSH Git authentication alone cannot upload the initial Release asset;
use a GitHub-authenticated browser or `gh auth login` on the maintainer machine.

## Outputs and failure handling

The Release is marked prerelease, with `.img.xz`, SHA256SUMS, verification/build
logs, package list, instructions and commit/run provenance. A draft is created
only after build/verification/compression succeeds and published only after all
uploads complete. Existing releases/assets are never overwritten. If upload
fails, inspect the remaining draft before retrying; use a new tag or manually
finish that draft instead of silently replacing a published image.

The workflow needs >10 GiB initially free and avoids a third raw image copy.
Each compressed asset is checked to be <2 GiB. SHA256SUMS lists both compressed
and decompressed files; download/decompress both before `sha256sum -c SHA256SUMS`.
Random filesystem UUIDs and build timestamps mean outputs are not bit-reproducible.
The local v3.1 image hash in revision-v3.1/README.md is not a CI output hash.

Changing image behavior requires a new version and output filename in the
revision scripts, not merely rerunning a tag. Preserve v2 and previous outputs.

## eMMC U-Boot blob

`uboot-emmc.yml` cross-compiles `u-boot-sunxi-with-spl-emmc.bin` from the pinned
upstream commits in `uboot-x96qproplus/PKGBUILD` (U-Boot `b99f4a9e...`, TF-A
`b5de74a...`), applies `revision-v3/uboot-emmc.patch`, and uploads the blob, its
SHA-256, the resulting `.config` and the source archive hashes as a workflow
artifact. It needs no input bundle, no privileged container and no 4 GiB image,
so it finishes in minutes instead of the SD job's ~90 minutes.

It is the CI twin of `revision-v3/build-emmc-uboot.sh`, which does the same work
inside the local `h728-image-build` container. Changing one without the other
makes the two outputs diverge; keep the pinned commits, the patch and the
`scripts/config` edits identical.

Upstream sources are downloaded by commit SHA but are not hash-pinned unless
`ci/uboot-emmc.sha256` exists. GitHub regenerates archive tarballs, so their
hashes can change for reasons unrelated to the source. Copy `source.sha256` from
a run's artifact into `ci/uboot-emmc.sha256` to pin them; the workflow then
verifies before building and warns while the file is absent.

The blob is verified, not merely produced: the compiled board DTB must carry
`bus-width = <1>` and `max-frequency = <26000000>` on `/soc/mmc@4022000`, and
the blob must contain `eGON.BT0` at **byte offset 4** of the file (byte 0 is the
branch instruction). 8192 is where it lands *on the device*, because the blob is
written with `dd seek=8`; it is not an offset inside the file.

Installing a blob is a separate manual step: copy it to the SD card's FAT
partition, boot from SD, interrupt autoboot, and write it to the eMMC user area
at sector 16. The eMMC partition table starts at 1 MiB, so this replaces only
the bootloader area. The SD card keeps its own bootloader and stays bootable
regardless of the outcome.

## Building the blob locally with Podman

CI is authoritative, but waiting on it for every patch tweak is slow. On a
Windows host with Podman Desktop (WSL backend) this builds the same blob in
minutes:

```bash
bash ci/podman-build-uboot-emmc.sh
```

The launcher starts the Podman machine if it is stopped, mounts the repo at
`/work`, and runs `ci/build-uboot-emmc-container.sh` inside `ubuntu:24.04`.
Output lands in `<repo>/out/` (gitignored): the blob, `emmc-uboot.config`,
`emmc-uboot.sha256` and `source.sha256`. All the CI assertions run, and the
script deletes the blob and exits non-zero if any of them fail, so a bad blob
can never be mistaken for a good one.

Two environment notes:

- The script strips CR from the patch before `patch -p1`; a CRLF checkout
  makes `patch` fail with hunks that "look" correct.
- `wsl.exe` must not be on the host command blacklist, otherwise Podman cannot
  reach its WSL machine and every container command fails with
  `PROGRAM BLOCKED BY SECURITY POLICY`.
