#!/bin/bash
# Test the TWRP installer on the PC, without a phone: "partitions" are files
# (update-binary's R9Q_TEST_BLK mode), getprop/blockdev/unpigz are stubs, and
# a small ext4 image is packaged by the real make-twrp-zip.sh.
# Cases: normal install, wrong model, damaged zip (the last two must not write).
# Usage: bash scripts/test-twrp-installer.sh
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/in" "$T/blk" "$T/bin" "$T/dest"
fail() { echo "FAIL: $*"; exit 1; }

# a small image set, as build-image.sh leaves it
truncate -s 32M "$T/in/arch-r9q.img"
mkfs.ext4 -q -F "$T/in/arch-r9q.img"
head -c 3M /dev/urandom > "$T/in/boot.img"
head -c 2M /dev/urandom > "$T/in/vendor_boot.img"
(cd "$T/in" && sha256sum arch-r9q.img boot.img vendor_boot.img > SHA256SUMS)

# stubs for TWRP's tools
printf '#!/bin/sh\necho "${MODEL:-SM-G990B2}"\n' > "$T/bin/getprop"
printf '#!/bin/sh\n[ "$1" = --getsize64 ] && exec stat -c %%s "$2"\n' > "$T/bin/blockdev"
printf '#!/bin/sh\nexec gzip -dc\n' > "$T/bin/unpigz"
chmod +x "$T/bin"/*

partitions() {
	rm -f "$T/blk"/*
	for p in userdata:64 boot:8 vendor_boot:8 dtbo:1 param:1 misc:1; do
		dd if=/dev/urandom of="$T/blk/${p%%:*}" bs=1M count="${p#*:}" status=none
	done
	printf '\002\0\0\0' | dd of="$T/blk/param" conv=notrunc status=none
	sha256sum "$T/blk/userdata" | cut -d' ' -f1
}
run() { R9Q_TEST_BLK="$T/blk" PATH="$T/bin:$PATH" bash "$TWRP_BINARY" 3 1 "$1"; }

EDITION=kde IN="$T/in" bash "$A/make-twrp-zip.sh" "$T/dest" | tail -2
ZIP=$(ls "$T/dest"/*.zip)

echo "== 1. normal install"
partitions > /dev/null
run "$ZIP" | sed 's/^ui_print */   /' | grep -v '^ *$'
size=$(stat -c %s "$T/in/arch-r9q.img")
cmp -n "$size" "$T/in/arch-r9q.img" "$T/blk/userdata" || fail "userdata differs from the image"
cmp -n "$(stat -c %s "$T/in/boot.img")" "$T/in/boot.img" "$T/blk/boot" || fail "boot differs"
cmp -n "$(stat -c %s "$T/in/vendor_boot.img")" "$T/in/vendor_boot.img" "$T/blk/vendor_boot" || fail "vendor_boot differs"
[ "$(head -c 4096 "$T/blk/dtbo" | tr -d '\0' | wc -c)" = 0 ] || fail "dtbo header not blanked"
[ "$(head -c 4 "$T/blk/param" | tr -d '\0' | wc -c)" = 0 ] || fail "param flag not cleared"
echo "   OK: userdata, boot, vendor_boot written; dtbo and param cleared"

echo "== 2. wrong model: must not write"
before=$(partitions)
MODEL=SM-G991B run "$ZIP" > "$T/out2" && fail "installer accepted a wrong model"
grep -q 'SM-G990B2' "$T/out2" || fail "no model message"
[ "$(sha256sum "$T/blk/userdata" | cut -d' ' -f1)" = "$before" ] || fail "userdata was touched"
echo "   OK: refused, nothing written"

echo "== 3. damaged zip: must not write"
before=$(partitions)
cp "$ZIP" "$T/bad.zip"
off=$(($(stat -c %s "$T/bad.zip") - 200000))
printf 'XXXXXXXX' | dd of="$T/bad.zip" bs=1 seek="$off" conv=notrunc status=none
run "$T/bad.zip" > "$T/out3" && fail "installer accepted a damaged zip"
[ "$(sha256sum "$T/blk/userdata" | cut -d' ' -f1)" = "$before" ] || fail "userdata was touched"
grep -E 'ERROR' "$T/out3" | sed 's/^ui_print */   /'
echo "   OK: refused, nothing written"
echo "INSTALLER_TESTS_OK"
