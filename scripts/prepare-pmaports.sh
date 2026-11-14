#!/bin/bash
# Put this port's postmarketOS packages into a pmaports checkout, so that
# pmbootstrap can build the kernel and firmware the Arch packages repack:
#   packaging/postmarketos/*           -> $PMAPORTS/device/testing/
#   kernel/patches, config, dts        -> $PMAPORTS/device/testing/linux-samsung-r9q/
# The firmware package also needs the blobs listed in its APKBUILD, taken from
# your own phone's vendor partition (see docs/boot-strategy.md); they are not
# in this repository.
# Usage: bash scripts/prepare-pmaports.sh [PMAPORTS=$(pmbootstrap config aports)]
#        pmbootstrap build linux-samsung-r9q device-samsung-r9q firmware-samsung-r9q
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
PMAPORTS=${1:-$(pmbootstrap config aports)}
[ -d "$PMAPORTS/device/testing" ] || { echo "not a pmaports checkout: $PMAPORTS"; exit 1; }
D=$PMAPORTS/device/testing
for p in "$R"/packaging/postmarketos/*/; do
	n=$(basename "$p")
	mkdir -p "$D/$n"
	cp -a "$p". "$D/$n/"
done
K=$D/linux-samsung-r9q
cp "$R"/kernel/patches/*.patch "$K/"
cp "$R/kernel/config/config-samsung-r9q.aarch64" "$K/"
cp "$R/kernel/dts/sm8350-samsung-r9q.dts" "$K/"
echo "pmaports ready in $D: pmbootstrap checksum linux-samsung-r9q && pmbootstrap build linux-samsung-r9q"
