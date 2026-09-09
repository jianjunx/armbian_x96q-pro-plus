#!/bin/bash
# Run in h728-image-build after copying this directory into /armbian/cache.
set -euo pipefail
src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
package=/tmp/h728-wifi.pkg.tar.zst
expected=1b921a23d1f9f952a2b2d53f99a431f5d6450a2aa4b815d24b3c7b9606782ab6
[[ $(sha256sum "$package" | cut -d' ' -f1) == "$expected" ]]
work=$(mktemp -d /tmp/h728-repair-build.XXXXXX)
bundle=$work/h728-v2.1-repair
mkdir -p "$bundle/firmware" "$work/extracted" /armbian/output/repairs
tar -xf "$package" -C "$work/extracted" usr/lib/firmware/aic8800_sdio
cp "$work/extracted/usr/lib/firmware/aic8800_sdio/"* "$bundle/firmware/"
install -m0755 "$src/install.sh" "$bundle/install.sh"
install -m0755 /armbian/cache/h728-v2-input/h728-diagnostics "$bundle/h728-diagnostics"
install -m0644 "$src/README.md" "$bundle/README.md"
tar -xOf "$package" .PKGINFO >"$bundle/firmware-source.PKGINFO"
cd "$bundle"
sha256sum firmware/* h728-diagnostics >SHA256SUMS
sha256sum -c SHA256SUMS
tar -czf /armbian/output/repairs/h728-v2.1-repair.tar.gz -C "$work" h728-v2.1-repair
cd /armbian/output/repairs
sha256sum h728-v2.1-repair.tar.gz >h728-v2.1-repair.tar.gz.sha256
echo "Unpacked bundle: $bundle"
