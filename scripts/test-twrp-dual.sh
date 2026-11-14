#!/bin/bash
# Test the dual boot TWRP installer (twrp/update-binary-dual) on the PC:
# "partitions" are files, the ESP a directory that already holds Android's
# menu entry, getprop/blockdev/unpigz are stubs, and a small DUAL image is
# packaged by the real make-twrp-zip.sh.
# Cases: normal install (only linux and the Arch files on the ESP change;
# userdata, boot and Android's entry stay byte for byte), boot without the
# dual boot kernel, phone not split, damaged zip (none of these may write).
# Usage: bash scripts/test-twrp-dual.sh
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/in/esp/arch" "$T/in/esp/loader/entries" "$T/in/esp/EFI/BOOT" "$T/blk" "$T/bin" "$T/dest"
fail() { echo "FAIL: $*"; exit 1; }

# a small DUAL image set, as build-image.sh DUAL=1 leaves it
truncate -s 32M "$T/in/arch-r9q.img"
mkfs.ext4 -q -F "$T/in/arch-r9q.img"
{ printf 'MZ'; head -c 54 /dev/zero; printf 'ARM\x64'; head -c 3M /dev/urandom; } > "$T/in/esp/arch/Image"
head -c 2M /dev/urandom > "$T/in/esp/arch/initramfs.img"
{ printf '\xd0\x0d\xfe\xed'; head -c 1000 /dev/urandom; } > "$T/in/esp/arch/r9q.dtb"
printf 'title Arch Linux ARM\noptions root=PARTLABEL=linux\n' > "$T/in/esp/loader/entries/arch.conf"
head -c 170K /dev/urandom > "$T/in/esp/EFI/BOOT/BOOTAA64.EFI"
(cd "$T/in" && { sha256sum arch-r9q.img; find esp -type f | sort | xargs sha256sum; } > SHA256SUMS)

printf '#!/bin/sh\necho "${MODEL:-SM-G990B2}"\n' > "$T/bin/getprop"
printf '#!/bin/sh\n[ "$1" = --getsize64 ] && exec stat -c %%s "$2"\n' > "$T/bin/blockdev"
printf '#!/bin/sh\nexec gzip -dc\n' > "$T/bin/unpigz"
chmod +x "$T/bin"/*

phone() { # phone [nosel] [nolinux]: fake partitions + an ESP with Android's entry
	rm -rf "$T/blk" "$T/esp"; mkdir -p "$T/blk" "$T/esp/loader/entries" "$T/esp/EFI/android" "$T/esp/EFI/BOOT"
	for p in userdata:16 boot:8 esp:1 param:1 misc:1 linux:64; do
		dd if=/dev/urandom of="$T/blk/${p%%:*}" bs=1M count="${p#*:}" status=none
	done
	case " $* " in *" nolinux "*) rm -f "$T/blk/linux" ;; esac
	# boot.img of Android with the selector: kernel at 4096, marker after 0x40
	case " $* " in *" nosel "*) ;; *) printf 'R9QDUALB' | dd of="$T/blk/boot" bs=1 seek=$((4096 + 0xAC)) conv=notrunc status=none ;; esac
	printf 'title Android\nefi /EFI/android/Reboot2Android.efi\n' > "$T/esp/loader/entries/android.conf"
	head -c 3K /dev/urandom > "$T/esp/EFI/android/Reboot2Android.efi"
	head -c 100K /dev/urandom > "$T/esp/EFI/BOOT/BOOTAA64.EFI"
	printf 'timeout 10\ndefault android.conf\n' > "$T/esp/loader/loader.conf"
	printf '\002\0\0\0' | dd of="$T/blk/param" conv=notrunc status=none
}
state() { (cd "$T/blk" && sha256sum *; cd "$T/esp" && find . -type f | sort | xargs sha256sum) | sha256sum | cut -d' ' -f1; }
run() { R9Q_TEST_BLK="$T/blk" R9Q_TEST_ESP="$T/esp" PATH="$T/bin:$PATH" bash "${TWRP_BINARY%/*}/update-binary-dual" 3 1 "$1"; }

DUAL=1 EDITION=kde IN="$T/in" bash "$A/make-twrp-zip.sh" "$T/dest" | tail -2
ZIP=$(ls "$T"/dest/*.zip)
unzip -l "$ZIP" | grep -q 'esp/arch/Image' || fail "no esp/ in the zip"

echo "== 1. normal install"
phone
keep_ud=$(sha256sum < "$T/blk/userdata"); keep_boot=$(sha256sum < "$T/blk/boot")
keep_and=$(cd "$T/esp" && sha256sum loader/entries/android.conf EFI/android/Reboot2Android.efi)
run "$ZIP" | sed 's/^ui_print */   /' | grep -v '^ *$'
cmp -n "$(stat -c %s "$T/in/arch-r9q.img")" "$T/in/arch-r9q.img" "$T/blk/linux" || fail "linux differs from the image"
for f in arch/Image arch/initramfs.img arch/r9q.dtb loader/entries/arch.conf EFI/BOOT/BOOTAA64.EFI; do
	cmp "$T/in/esp/$f" "$T/esp/$f" || fail "ESP $f differs"
done
grep -qx 'default arch.conf' "$T/esp/loader/loader.conf" || fail "loader.conf default"
[ "$(sha256sum < "$T/blk/userdata")" = "$keep_ud" ] || fail "userdata was touched"
[ "$(sha256sum < "$T/blk/boot")" = "$keep_boot" ] || fail "boot was touched"
[ "$(cd "$T/esp" && sha256sum loader/entries/android.conf EFI/android/Reboot2Android.efi)" = "$keep_and" ] || fail "Android's menu entry was touched"
[ "$(head -c 4 "$T/blk/param" | tr -d '\0' | wc -c)" = 0 ] || fail "param flag not cleared"
echo "   OK: linux and the Arch ESP files written; userdata, boot and Android's entry untouched"

for c in "nosel:boot without the dual boot kernel" "nolinux:phone not split"; do
	echo "== ${c#*:}: must not write"
	phone "${c%%:*}"; before=$(state)
	run "$ZIP" > "$T/out" && fail "installer accepted: ${c#*:}"
	[ "$(state)" = "$before" ] || fail "something was written"
	grep -o 'ERROR: .*' "$T/out" | head -1 | sed 's/^/   /'
	echo "   OK: refused, nothing written"
done

echo "== damaged zip: must not write"
phone; before=$(state)
cp "$ZIP" "$T/bad.zip"
off=$(($(stat -c %s "$T/bad.zip") - 200000))
printf 'XXXXXXXX' | dd of="$T/bad.zip" bs=1 seek="$off" conv=notrunc status=none
run "$T/bad.zip" > "$T/out" && fail "installer accepted a damaged zip"
[ "$(state)" = "$before" ] || fail "something was written"
grep -o 'ERROR: .*' "$T/out" | head -1 | sed 's/^/   /'
echo "   OK: refused, nothing written"
echo DUAL_INSTALLER_TESTS_OK
