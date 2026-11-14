#!/bin/bash
# Install a finished ZIP with the real update-binary on the PC (test mode:
# partitions are files, 8 GiB userdata) and compare boot/vendor_boot with the
# images it was made from. update-binary itself checks userdata's SHA-256.
# Usage: bash scripts/test-twrp-zip.sh ZIP IMAGE_DIR   (IMAGE_DIR = out/$EDITION)
set -euo pipefail
ZIP=$1
IN=$2
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
T=$(mktemp -d "$(dirname "$ZIP")/.ziptest.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/blk" "$T/bin"
printf '#!/bin/sh\necho SM-G990B2\n' > "$T/bin/getprop"
printf '#!/bin/sh\n[ "$1" = --getsize64 ] && exec stat -c %%s "$2"\n' > "$T/bin/blockdev"
printf '#!/bin/sh\nexec gzip -dc\n' > "$T/bin/unpigz"
chmod +x "$T/bin"/*
truncate -s 8G "$T/blk/userdata"
for p in boot:96 vendor_boot:96 dtbo:24 param:8 misc:1; do
	truncate -s "${p#*:}M" "$T/blk/${p%%:*}"
done
R9Q_TEST_BLK="$T/blk" PATH="$T/bin:$PATH" bash "$TWRP_BINARY" 3 1 "$ZIP" |
	sed 's/^ui_print */   /' | grep -v '^ *$'
cmp -n "$(stat -c %s "$IN/boot.img")" "$IN/boot.img" "$T/blk/boot"
cmp -n "$(stat -c %s "$IN/vendor_boot.img")" "$IN/vendor_boot.img" "$T/blk/vendor_boot"
echo "   boot and vendor_boot match"
echo ZIP_INSTALL_OK
