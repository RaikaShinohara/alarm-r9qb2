#!/bin/bash
# Build the all-in-one dual boot release ZIP: Arch Linux ARM, KDE or Steam edition (public image,
# alarm/alarm, DUAL=1) + everything to make the installed Android dual boot,
# installed by configs/twrp/dualboot-update-binary (storage split chosen with the
# volume keys, Android's boot patched on the phone, fixed TWRP).
# Inside, next to the usual rootfs.img.gz / esp/ / manifest.txt:
#   dualboot/r9q-tool             keys + BLKPG helper (static AArch64, r9q-tool.c)
#   dualboot/shellcode-r9q.bin    the selector (make -C configs/dualboot)
#   dualboot/R9Q_UEFI.fd          Mu-Silicium v3.0.1 built in RELEASE (no on-screen log) with
#                                 the RAM and MMU fixes (fork RaikaShinohara/Mu-Silicium, r9q-dualboot)
#   dualboot/Reboot2Android.efi   the "Android" menu entry
#   dualboot/twrp-r9q.img         the fixed TWRP (make-twrp-fix.sh)
#   dualboot/SHA256SUMS
# Every piece is rebuilt here from its source and checked against the known
# result. Needs: the public dual image (PUBLIC=1 DUAL=1 EDITION=kde|steam|mobile
# build-image.sh), the RELEASE FD (dualboot/out/R9Q_UEFI-v3.0.1-release-r9qfix.fd,
# made by dualboot/build-uefi-release.sh; not rebuilt here, checked by its
# SHA-256), work/recovery.img (the original TWRP).
# Usage: [EDITION=kde|steam|mobile] bash scripts/make-dualboot-release.sh [destination=artifacts/release]
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$H/.." && pwd)"
A=$R/scripts/	# scripts/ in the repository
. "$A/paths.sh"
VERSION=$(tr -d ' \n' < "$VERSION_FILE")
EDITION=${EDITION:-kde}	# kde (Plasma), steam (Steam game mode, SteamOS style) or mobile (Plasma Mobile)
case "$EDITION" in kde | steam | mobile) ;; *) echo "EDITION must be kde, steam or mobile"; exit 1 ;; esac
NAME=archlinuxarm-$EDITION-dualboot-sm-g990b2-v$VERSION
DEST="${1:-$ARTIFACTS/release}"
IN=$OUT_BASE/$EDITION-public-dual
# the UEFI: built from the fork (see dualboot/build-uefi-release.sh), pinned here
FD_RELEASE=$R/dualboot/out/R9Q_UEFI-v3.0.1-release-r9qfix.fd
FD_SHA=f288bf8e09f0546394d2a01c4bde531bfe98d53551f263305246429b71effc8f	# v3.0.1 RELEASE + RAM + MMU fixes, tested on the phone
mkdir -p "$DEST"
W=$(mktemp -d "$DEST/.work-dual.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/add/dualboot
mkdir -p "$D" "$W/add/META-INF/com/google/android"

echo "== selector and Reboot2Android"
make -s -C "$R/dualboot/dbkp" >/dev/null
cp "$R/configs/dualboot/shellcode-r9q.bin" "$R/configs/dualboot/Reboot2Android.efi" "$D/"
grep -q R9QDUALB "$D/shellcode-r9q.bin"

echo "== r9q-tool"
clang --target=aarch64-linux-gnu -O2 -Wall -Wextra -Werror -ffreestanding -fno-stack-protector -fno-builtin \
	-nostdlib -static -fno-pic -fuse-ld=lld -Wl,--build-id=none -o "$D/r9q-tool" "$R/configs/dualboot/r9q-tool.c"
llvm-strip "$D/r9q-tool"
file "$D/r9q-tool" | grep -q 'ARM aarch64.*statically linked'

echo "== UEFI (v3.0.1 RELEASE + RAM + MMU fixes)"
cp "$FD_RELEASE" "$D/R9Q_UEFI.fd"
[ "$(sha256sum "$D/R9Q_UEFI.fd" | cut -d' ' -f1)" = "$FD_SHA" ] || { echo "the UEFI FD is not the tested one"; exit 1; }

echo "== fixed TWRP"
bash "$R/scripts/make-twrp-fix.sh" "$R/work/recovery.img" "$D/twrp-r9q.img" >/dev/null

(cd "$D" && sha256sum r9q-tool shellcode-r9q.bin R9Q_UEFI.fd Reboot2Android.efi twrp-r9q.img > SHA256SUMS)
install -m755 "$R/configs/twrp/dualboot-update-binary" "$W/add/META-INF/com/google/android/update-binary"
sh -n "$W/add/META-INF/com/google/android/update-binary"

echo "== Arch $EDITION (public, dual boot) zip"
[ -s "$IN/arch-r9q.img" ] || { echo "missing $IN: run PUBLIC=1 DUAL=1 EDITION=$EDITION bash scripts/build-image.sh"; exit 1; }
PUBLIC=1 DUAL=1 EDITION=$EDITION NAME=$NAME IN=$IN bash "$A/make-twrp-zip.sh" "$W/base" | tail -n2
mv "$W/base/$NAME.zip" "$W/$NAME.zip"
# our installer replaces the Arch-only one; the dual boot payload is added (stored)
(cd "$W/add" && zip -0 -X -q -r "$W/$NAME.zip" META-INF dualboot)
unzip -p "$W/$NAME.zip" META-INF/com/google/android/update-binary | cmp - "$R/configs/twrp/dualboot-update-binary"
for f in r9q-tool shellcode-r9q.bin R9Q_UEFI.fd Reboot2Android.efi twrp-r9q.img; do
	unzip -p "$W/$NAME.zip" "dualboot/$f" | cmp - "$D/$f"
done
mv -f "$W/$NAME.zip" "$DEST/$NAME.zip"
(cd "$DEST" && sha256sum "$NAME.zip" > "$NAME.zip.sha256")
echo "$DEST/$NAME.zip: $(($(stat -c %s "$DEST/$NAME.zip") >> 20)) MiB"
cat "$D/SHA256SUMS"
echo RELEASE_ZIP_DONE
