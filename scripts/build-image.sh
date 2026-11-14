#!/bin/bash
# Build the Arch Linux ARM image for the Galaxy S21 FE (r9q), without sudo:
#  1. rootless podman + qemu-user (aarch64): a container from the verified
#     ALARM tarball runs image/setup.sh (our repo, Plasma, user, services)
#  2. `podman unshare` + `podman mount`: its filesystem becomes an ext4 image
#     for userdata (4 KiB blocks, like the UFS); boot.img and vendor_boot.img
#     come from its /boot (built there by r9q-bootimg)
# Three editions: EDITION=kde (Plasma with its login screen), EDITION=steam
# (the same plus Steam's game mode, booted into by default) or EDITION=mobile
# (the same plus Plasma Mobile, booted into by default; DeX style desktop on
# external screens).
# Output: work/out/$EDITION/{arch-r9q.img,boot.img,vendor_boot.img,SHA256SUMS}
# The container (r9q-arch-$EDITION) is kept for inspection; KEEP=0 removes it.
# PUBLIC=1: image for publishing (user alarm, password alarm, no ssh keys,
# en_US/UTC unless LOCALE/TIMEZONE/KEYMAP are given), output in out/$EDITION-public.
# DUAL=1: for the dual boot with Android (BOOT_MODE=uefi): root on the "linux"
# partition and, instead of boot.img/vendor_boot.img, the ESP contents in
# out/$EDITION-dual/esp/ (kernel Image, initramfs, DTB, systemd-boot entry).
# Usage: [PUBLIC=1] [DUAL=1] EDITION=kde|steam|mobile bash scripts/build-image.sh
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
EDITION=${EDITION:-steam}
case "$EDITION" in kde | steam | mobile) ;; *) echo "EDITION must be kde, steam or mobile"; exit 1 ;; esac
BOOT_MODE=abl; [ "${DUAL:-0}" = 1 ] && BOOT_MODE=uefi
SUF=; [ "${PUBLIC:-0}" = 1 ] && SUF=-public
[ "$BOOT_MODE" = uefi ] && SUF=$SUF-dual
OUT="$OUT_BASE/$EDITION$SUF"
CTR=r9q-arch-$EDITION$SUF
CFG=$PMB_CFG
HOST_NAME=r9q-arch
cfg() { sed -n "s/^$1 *= *//p" "$CFG" | head -n1; }

podman image exists localhost/alarm-r9q:base || { echo "missing base image: run build-packages.sh first"; exit 1; }
for p in qrtr rmtfs tqftpserv hexagonrpcd linux-samsung-r9q firmware-samsung-r9q device-samsung-r9q; do
	compgen -G "$LOCAL_REPO/$p-[0-9]*.pkg.tar.*" >/dev/null || { echo "missing $p in $LOCAL_REPO: run build-packages.sh"; exit 1; }
done

# settings, password hash and ssh keys for setup.sh (same as the pmOS install:
# user/locale/timezone from pmbootstrap-r9q.cfg, ssh_keys = ~/.ssh/id_*.pub)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
if [ "${PUBLIC:-0}" = 1 ]; then
	# image to publish: the documented alarm/alarm account (as stock Arch Linux
	# ARM), no ssh keys, nothing from this PC
	user=alarm; pw=alarm
	locale=${LOCALE:-en_US.UTF-8}; timezone=${TIMEZONE:-UTC}; keymap=${KEYMAP:-us}
	: > "$T/authorized_keys"
else
	user=$(cfg user)
	[ -n "$user" ] || user=$(sed -n 's/^User=//p' "$CRED")
	locale=$(cfg locale); timezone=$(cfg timezone); keymap=${KEYMAP:-es}
	pw=$(sed -n 's/^password=//p' "$CRED")
	cat "$HOME"/.ssh/id_*.pub > "$T/authorized_keys"
fi
[ -n "$user" ] && [ -n "$pw" ] && [ -n "$locale" ] && [ -n "$timezone" ] || { echo "incomplete settings"; exit 1; }
printf '%s\n' "$pw" | openssl passwd -6 -stdin > "$T/hash"
unset pw
cat > "$T/settings" <<EOF
EDITION=$EDITION
BOOT_MODE=$BOOT_MODE
USER_NAME=$user
HOST_NAME=$HOST_NAME
LOCALE=$locale
TIMEZONE=$timezone
KEYMAP=$keymap
EOF
cp "$SETUP_SH" "$T/setup.sh"

# 1. install and configure the system in the container
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman run --name "$CTR" --arch arm64 --hostname "$HOST_NAME" \
	-v "$LOCAL_REPO:/repo:ro" -v "$T:/setup:ro" \
	localhost/alarm-r9q:base /bin/bash /setup/setup.sh

# 2. ext4 image + boot images from the container's filesystem
mkdir -p "$OUT"
rm -rf "$OUT/arch-r9q.img" "$OUT/boot.img" "$OUT/vendor_boot.img" "$OUT/esp" "$OUT/SHA256SUMS"
export OUT CTR HOST_NAME BOOT_MODE
podman unshare bash -euo pipefail -c '
	m=$(podman mount "$CTR")
	trap "podman umount \"\$CTR\" >/dev/null" EXIT
	# files podman manages while a container runs: set them for the phone
	echo "$HOST_NAME" > "$m/etc/hostname"
	ln -sfn ../run/systemd/resolve/stub-resolv.conf "$m/etc/resolv.conf"
	used=$(du -sxB1 "$m" | cut -f1)
	# +25% +1 GiB of room, 4 MiB aligned; growfs fills userdata on first boot
	size=$(( (used + used / 4 + (1 << 30)) / (4 << 20) * (4 << 20) ))
	echo "rootfs: $((used >> 20)) MiB used, image $((size >> 20)) MiB"
	truncate -s "$size" "$OUT/arch-r9q.img"
	# no orphan_file: keeps the filesystem mountable by TWRP (kernel 5.4)
	mkfs.ext4 -q -F -b 4096 -L arch_root -O ^orphan_file -E root_owner=0:0 \
		-d "$m" "$OUT/arch-r9q.img"
	if [ "$BOOT_MODE" = uefi ]; then
		cp -r "$m/boot/esp-initial" "$OUT/esp"
	else
		cp "$m/boot/boot.img" "$m/boot/vendor_boot.img" "$OUT/"
	fi
'
e2fsck -fn "$OUT/arch-r9q.img"
if [ "$BOOT_MODE" = uefi ]; then
	(cd "$OUT" && { sha256sum arch-r9q.img; find esp -type f | sort | xargs sha256sum; } > SHA256SUMS)
else
	(cd "$OUT" && sha256sum arch-r9q.img boot.img vendor_boot.img > SHA256SUMS)
fi
[ "${KEEP:-1}" = 1 ] || podman rm "$CTR" >/dev/null
ls -la "$OUT"
echo IMAGE_DONE
