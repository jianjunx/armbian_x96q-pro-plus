# GitHub Actions SD image assembly

The workflow builds v3.1 from six pinned, pristine offline inputs, NOT from a
physical SD/eMMC backup. No private diagnostics or keys belong in the bundle.
The native `ubuntu-24.04-arm` runner executes loop/mount/chroot in a privileged
Ubuntu container. No physical device is attached. It does not build Linux
from source or update Trixie packages. CI host packages may update; image
packages remain pinned to the original v3 base and the local +h728.4 repair.

## One-time bootstrap

1. Review third-party binary redistribution conditions (especially the AIC
   firmware's unknown license) before making the input/image assets public.
2. Run `pack-inputs.sh /path/to/inputs.sha256` inside `h728-image-build`.
   It checks every input and creates `/armbian/output/ci-inputs/h728-v3-inputs.tar.xz`.
3. Copy the generated `.sha256` into tracked `ci/bundle.sha256`; review/commit.
4. Upload the bundle to a separate `build-inputs-v3` Release in this repository.
   This is an archival build input, not a recommended flashable release.
   Never replace it with a device backup or a different image under the same name.
5. Push build-related code to main: the workflow builds and publishes under a
   unique `v3.1.0-ci.<run>.<attempt>` tag. Alternatively push `v3.1.0`, or manually
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
