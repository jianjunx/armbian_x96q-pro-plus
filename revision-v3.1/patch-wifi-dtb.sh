#!/bin/bash
# Board-tested SDIO clock ceiling; preserve all other DTB bytes.
set -euo pipefail
dtb=$1
node=/soc/mmc@4021000
expected=be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567
test "$(sha256sum "$dtb" | awk '{print $1}')" = "$expected"
fdtput -t i "$dtb" "$node" max-frequency 24000000
test "$(sha256sum "$dtb" | awk '{print $1}')" = 5e4c838516b43e7667a583859b671cf5eb00316674eb950d0eb5bb67b2502bc7
