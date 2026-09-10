#!/bin/bash
# Run inside the existing ARM64 build container; outputs never belong in Git.
set -euo pipefail
manifest=${1:?Usage: pack-inputs.sh /path/to/inputs.sha256}
manifest=$(realpath "$manifest")
cd /armbian
sha256sum -c "$manifest"
out=/armbian/output/ci-inputs/h728-v3-inputs.tar.xz
test ! -e "$out" || { echo 'Refusing to overwrite existing input bundle'; exit 1; }
mkdir -p "${out%/*}"
mapfile -t files < <(awk '{print $2}' "$manifest")
# Explicit allowlist: no device backups, private logs, caches or credentials.
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -cf - -- "${files[@]}" | xz -T2 -3 >"$out"
xz -t "$out"
test "$(stat -c%s "$out")" -lt 2147483648
cd "${out%/*}"
sha256sum "${out##*/}" >"$out.sha256"
echo "Input bundle prepared: $out"
