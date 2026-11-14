#!/bin/bash
# Install a dual boot image (build-image.sh with DUAL=1) on a phone that is
# already split by the release ZIP (35 esp, 36 linux), from TWRP over adb:
#   linux <- out/$EDITION[-public]-dual/arch-r9q.img   (ERASES the Arch install there)
#   esp   <- its arch/ files, loader/entries/arch.conf and EFI/BOOT/BOOTAA64.EFI
# Android, its boot, the "Android" entry and the ESP's r9q/ backups are not
# touched. Then clears Samsung's "boot recovery" flags and reboots.
#
# Usage: [PUBLIC=1] EDITION=kde|steam|mobile scripts/flash-dualboot-adb.sh --yes-erase-linux
set -euo pipefail
[ "${1:-}" = "--yes-erase-linux" ] || { echo "Refusing: pass --yes-erase-linux (erases the Arch install on 'linux')"; exit 1; }
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
SUF=; [ "${PUBLIC:-0}" = 1 ] && SUF=-public
OUT="$OUT_BASE/${EDITION:-steam}$SUF-dual"
S=${SERIAL:?set SERIAL to the adb serial of the phone (adb devices)}
A="adb -s $S"

[ -s "$OUT/arch-r9q.img" ] && [ -s "$OUT/SHA256SUMS" ] || { echo "missing $OUT/arch-r9q.img or SHA256SUMS"; exit 1; }
(cd "$OUT" && sha256sum -c --quiet SHA256SUMS) || { echo "image checksums do not match SHA256SUMS"; exit 1; }
$A wait-for-recovery
model=$($A shell getprop ro.boot.em.model | tr -d '\r')
[ "$model" = SM-G990B2 ] || { echo "not an SM-G990B2 ($model)"; exit 1; }
LX=$($A shell readlink -f /dev/block/by-name/linux | tr -d '\r')
ES=$($A shell readlink -f /dev/block/by-name/esp | tr -d '\r')
[ -n "$LX" ] && [ -n "$ES" ] || { echo "no linux/esp partitions: install the release ZIP first"; exit 1; }
size=$(stat -c %s "$OUT/arch-r9q.img")
part=$($A shell blockdev --getsize64 "$LX" | tr -d '\r')
[ "$size" -le "$part" ] || { echo "image ($size) larger than linux ($part)"; exit 1; }

echo "== linux ($LX): $((size >> 20)) MiB"
$A shell "umount $LX" 2>/dev/null || true
$A exec-in "dd of=$LX bs=4194304" < "$OUT/arch-r9q.img"
want=$(sha256sum < "$OUT/arch-r9q.img" | cut -d' ' -f1)
got=$($A shell "head -c $size $LX | sha256sum" | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "linux read back differs"; exit 1; }

echo "== esp ($ES)"
M=/tmp/r9q-esp
# (TWRP's mountpoint says yes for a plain directory: mount unconditionally)
$A shell "mkdir -p $M; umount $M 2>/dev/null; mount -t vfat $ES $M && mount | grep -q ' $M '" || { echo "cannot mount the ESP"; exit 1; }
(cd "$OUT/esp" && find arch loader/entries/arch.conf EFI/BOOT/BOOTAA64.EFI -type f) | while read -r f; do
	# adb reads stdin: keep it away from the file list
	$A push "$OUT/esp/$f" "$M/$f.new" >/dev/null < /dev/null
	$A shell "mv -f $M/$f.new $M/$f" < /dev/null
	[ "$($A shell sha256sum "$M/$f" < /dev/null | cut -d' ' -f1)" = "$(sha256sum < "$OUT/esp/$f" | cut -d' ' -f1)" ] ||
		{ echo "$f differs on the ESP"; exit 1; }
	echo "  $f"
done
$A shell "sync; umount $M"

# Samsung's ABL "boot recovery" flags, as flash-twrp-adb.sh
$A shell 'dd if=/dev/zero of=/dev/block/by-name/param bs=4 count=1 conv=notrunc 2>/dev/null; dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=8 2>/dev/null; sync'
[ "${NOREBOOT:-0}" = 1 ] || { echo "== reboot"; $A reboot; }
echo FLASH_DUAL_DONE
