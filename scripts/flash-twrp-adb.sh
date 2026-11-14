#!/bin/bash
# Install the Arch Linux ARM image built by scripts/build-image.sh, from TWRP
# over adb (without adb: the TWRP zip from make-twrp-zip.sh does the same).
#   boot        <- out/$EDITION/boot.img          (kernel, header v3)
#   vendor_boot <- out/$EDITION/vendor_boot.img   (DTB + initramfs + cmdline)
#   dtbo        <- 4 KiB of zeros                 (ABL skips Samsung's DT overlays)
#   userdata    <- out/$EDITION/arch-r9q.img      (ext4 root; ERASES postmarketOS/Android)
# Then clears Samsung's "boot recovery" flags (param word 0, misc BCB) and
# reboots.
#
# Usage: EDITION=kde|steam scripts/flash-twrp-adb.sh --yes-erase-userdata
set -euo pipefail
[ "${1:-}" = "--yes-erase-userdata" ] || { echo "Refusing: pass --yes-erase-userdata (erases pmOS/Android on userdata)"; exit 1; }
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
OUT="$OUT_BASE/${EDITION:-steam}"
S=${SERIAL:?set SERIAL to the adb serial of the phone (adb devices)}
A="adb -s $S"

for f in boot.img vendor_boot.img arch-r9q.img SHA256SUMS; do
	[ -s "$OUT/$f" ] || { echo "missing $OUT/$f"; exit 1; }
done
(cd "$OUT" && sha256sum -c --quiet SHA256SUMS) || { echo "image checksums do not match SHA256SUMS"; exit 1; }
$A wait-for-recovery
model=$($A shell getprop ro.boot.em.model | tr -d '\r')
[ "$model" = "SM-G990B2" ] || { echo "unexpected device model '$model'"; exit 1; }

psize() { $A shell "blockdev --getsize64 /dev/block/by-name/$1" | tr -d '\r'; }
for p in boot:boot.img vendor_boot:vendor_boot.img userdata:arch-r9q.img; do
	part=${p%%:*}; f=$OUT/${p#*:}
	fs=$(stat -L -c %s "$f"); ps=$(psize "$part")
	echo "$part: image $fs bytes, partition $ps bytes"
	[ "$fs" -le "$ps" ] || { echo "$f larger than $part"; exit 1; }
done

# TWRP mounts /data (and its views) from userdata: release it first
$A shell 'umount /data/media 2>/dev/null; umount /sdcard 2>/dev/null; umount /data 2>/dev/null; umount -l /data 2>/dev/null; mount | grep -E " /data | /sdcard " || echo "data unmounted"'

img="$OUT/arch-r9q.img"
img_size=$(stat -L -c %s "$img")
echo "writing rootfs to userdata..."
# Push 1 GiB chunks to TWRP's tmpfs and dd them locally (adb exec-in through
# a pipe crawled at <1 MB/s; the tmpfs has ~2.3 GB free).
chunk_blocks=256
nchunks=$(( (img_size + chunk_blocks * 4194304 - 1) / (chunk_blocks * 4194304) ))
tmpd=$(mktemp -d)
trap 'rm -rf "$tmpd"' EXIT
for i in $(seq 0 $((nchunks - 1))); do
	skip=$((i * chunk_blocks))
	dd if="$img" of="$tmpd/chunk" bs=4194304 skip=$skip count=$chunk_blocks status=none
	echo "  chunk $((i + 1))/$nchunks ($(stat -c %s "$tmpd/chunk") bytes)"
	$A push "$tmpd/chunk" /tmp/rootfs.chunk >/dev/null
	$A shell "dd if=/tmp/rootfs.chunk of=/dev/block/by-name/userdata bs=4194304 seek=$skip conv=notrunc 2>/dev/null && rm -f /tmp/rootfs.chunk && sync" || { echo "chunk $i FAILED"; exit 1; }
done
want=$(sha256sum < "$img" | cut -d' ' -f1)
got=$($A shell "head -c $img_size /dev/block/by-name/userdata | sha256sum" | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "rootfs verification FAILED ($want != $got)"; exit 1; }
echo "rootfs verified ($want)"

$A push "$OUT/boot.img" "$OUT/vendor_boot.img" /tmp/
$A shell '
set -e
dd if=/tmp/boot.img of=/dev/block/by-name/boot bs=1M
dd if=/tmp/vendor_boot.img of=/dev/block/by-name/vendor_boot bs=1M
dd if=/dev/zero of=/dev/block/by-name/dtbo bs=4096 count=1
dd if=/dev/zero of=/dev/block/by-name/param bs=4 count=1 conv=notrunc
dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=8
sync
echo FLASH_OK'
echo "First boot: do not touch the buttons until the login screen (new SSH host key: use work/known_hosts)."
[ "${NOREBOOT:-0}" = 1 ] || $A reboot
