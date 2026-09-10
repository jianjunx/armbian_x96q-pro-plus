#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/h728-sd-emmc-root-test.sh"
test_dir=$(mktemp -d /tmp/h728-render-fixture.XXXXXX)
cat >"$test_dir/env" <<EOF
verbosity=6
rootdev=UUID=$sd_uuid
fdtfile=allwinner/sun55i-h728-x96qpro+.dtb
extraargs=earlycon=uart8250,mmio32,0x02500000 panic=10 loglevel=7
rootfstype=ext4
EOF
cat >"$test_dir/ext" <<EOF
DEFAULT armbian-h728
TIMEOUT 30
LABEL armbian-h728
    APPEND root=UUID=$sd_uuid rootwait loglevel=7
LABEL stock-dtb
    FDT /dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb
    APPEND root=UUID=$sd_uuid rootwait loglevel=7
EOF
render_extlinux "$test_dir/ext" >"$test_dir/ext.new"
render_env "$test_dir/env" >"$test_dir/env.new"
grep -qx "DEFAULT $label" "$test_dir/ext.new"
[[ $(grep -c "root=UUID=$sd_uuid" "$test_dir/ext.new") == 2 ]]
[[ $(grep -c "root=UUID=$emmc_uuid" "$test_dir/ext.new") == 1 ]]
grep -qx "rootdev=UUID=$emmc_uuid" "$test_dir/env.new"
grep -qx 'extraargs=earlycon=uart8250,mmio32,0x02500000 panic=10 loglevel=7' "$test_dir/env.new"
grep -qx 'verbosity=7' "$test_dir/env.new"
# Original menu entries are preserved byte-for-byte; only default is replaced.
awk '/^LABEL h728-sd-emmc-root-test$/ {exit} {print}' "$test_dir/ext.new" | sed '$d; 1d' >"$test_dir/preserved"
tail -n +2 "$test_dir/ext" | cmp - "$test_dir/preserved"
echo 'RENDER_TEST_PASS (no devices accessed)'
