#!/bin/bash
# Package an image made by build-image.sh as a zip that TWRP installs by itself
# (Install -> USB-OTG, or adb sideload). Inside: rootfs.img.gz (the ext4 root,
# gzip: TWRP has unpigz but no zstd/xz), manifest.txt (sizes + SHA-256),
# META-INF/.../update-binary, and
#   - Linux alone (abl): boot.img, vendor_boot.img; installer twrp/update-binary
#   - dual boot (DUAL=1, image from DUAL=1 build-image.sh): esp/ (kernel Image,
#     initramfs, DTB, systemd-boot and its Arch entry) + esp.sha256; installer
#     twrp/update-binary-dual, which writes only the linux partition and the ESP
# Entries are stored, not deflated, and the zip must stay under 4 GiB (TWRP's
# USB-OTG storage is FAT32).
# Usage: [PUBLIC=1] [DUAL=1] [NAME=...] EDITION=kde|steam|mobile bash scripts/make-twrp-zip.sh [destination=artifacts/]
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
EDITION=${EDITION:-steam}
SUF=; [ "${PUBLIC:-0}" = 1 ] && SUF=-public
[ "${DUAL:-0}" = 1 ] && SUF=$SUF-dual
IN="${IN:-$OUT_BASE/$EDITION$SUF}"
DEST="${1:-$ARTIFACTS}"
BUILD=$(date +%Y%m%d)
# NAME: zip name without .zip (releases: archlinuxarm-$EDITION-sm-g990b2-vX.Y.Z)
NAME="${NAME:-r9q-arch-$EDITION$SUF-$BUILD}"
MODE=abl; [ -d "$IN/esp" ] && MODE=dual
ESPFILES="esp/arch/Image esp/arch/initramfs.img esp/arch/r9q.dtb esp/loader/entries/arch.conf esp/EFI/BOOT/BOOTAA64.EFI"

if [ "$MODE" = dual ]; then need="arch-r9q.img SHA256SUMS $ESPFILES"; else need="arch-r9q.img boot.img vendor_boot.img SHA256SUMS"; fi
for f in $need; do
	[ -s "$IN/$f" ] || { echo "missing $IN/$f: run EDITION=$EDITION build-image.sh"; exit 1; }
done
(cd "$IN" && sha256sum -c --quiet SHA256SUMS) || { echo "$IN does not match its SHA256SUMS"; exit 1; }
mkdir -p "$DEST"
# work next to the destination (big files; /tmp may be RAM)
W=$(mktemp -d "$DEST/.work-$EDITION.XXXXXX")
trap 'rm -rf "$W"' EXIT

sum() { grep " $1\$" "$IN/SHA256SUMS" | cut -d' ' -f1; }
img_size=$(stat -c %s "$IN/arch-r9q.img")
used=$(debugfs -R stats "$IN/arch-r9q.img" 2>/dev/null |
	awk -F: '/^Block count/ { t = $2 } /^Free blocks/ { f = $2 } /^Block size/ { b = $2 } END { printf "%.1f GB", (t - f) * b / 1e9 }')
krel=$(sed -n 's/^pkgrel=//p' "$PKGS_DIR/linux-samsung-r9q/PKGBUILD")

echo "compressing the root filesystem ($((img_size >> 20)) MiB)..."
gzip -6 -n -c "$IN/arch-r9q.img" > "$W/rootfs.img.gz"
{
	echo "MODE='$MODE'"
	echo "EDITION='$EDITION'"
	echo "BUILD='$BUILD'"
	echo "KERNEL='7.2.13-r$krel'"
	echo "SYSTEM_SIZE='$used de sistema'"
	echo "IMG_SIZE=$img_size"
	echo "IMG_SHA256=$(sum arch-r9q.img)"
	echo "GZ_SHA256=$(sha256sum "$W/rootfs.img.gz" | cut -d' ' -f1)"
} > "$W/manifest.txt"
if [ "$MODE" = dual ]; then
	for f in $ESPFILES; do install -Dm644 "$IN/$f" "$W/$f"; done
	(cd "$W" && sha256sum $ESPFILES > esp.sha256)
	install -Dm755 "${TWRP_BINARY%/*}/update-binary-dual" "$W/META-INF/com/google/android/update-binary"
	payload="esp esp.sha256"
else
	cp "$IN/boot.img" "$IN/vendor_boot.img" "$W/"
	echo "BOOT_SHA256=$(sum boot.img)" >> "$W/manifest.txt"
	echo "VBOOT_SHA256=$(sum vendor_boot.img)" >> "$W/manifest.txt"
	install -Dm755 "$TWRP_BINARY" "$W/META-INF/com/google/android/update-binary"
	payload="boot.img vendor_boot.img"
fi
echo '# dummy: the installer is update-binary (a shell script)' > "$W/META-INF/com/google/android/updater-script"

rm -f "$DEST/$NAME.zip"
(cd "$W" && zip -0 -X -q -r "$DEST/$NAME.zip" META-INF manifest.txt $payload rootfs.img.gz)
zsize=$(stat -c %s "$DEST/$NAME.zip")
(cd "$DEST" && sha256sum "$NAME.zip" > "$NAME.zip.sha256")
echo "$DEST/$NAME.zip: $((zsize >> 20)) MiB ($MODE)"
if [ "$zsize" -ge 4294967295 ]; then
	echo "WARNING: over 4 GiB, it does not fit on a FAT32 USB drive: install it with adb sideload"
fi
# the zip must give back exactly what the manifest says
got=$(unzip -p "$DEST/$NAME.zip" rootfs.img.gz | sha256sum | cut -d' ' -f1)
[ "$got" = "$(sed -n 's/^GZ_SHA256=//p' "$W/manifest.txt")" ] || { echo "zip self-check FAILED"; exit 1; }
unzip -p "$DEST/$NAME.zip" META-INF/com/google/android/update-binary | sh -n
echo "ZIP_DONE $NAME.zip"
