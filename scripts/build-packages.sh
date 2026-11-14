#!/bin/bash
# Build the r9q Arch Linux ARM packages in an aarch64 container (rootless
# podman + qemu-user binfmt, no sudo) into a local pacman repo ($LOCAL_REPO)
# Usage: bash scripts/build-packages.sh [package ...]   (default: all)
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
P=$PMB_WORK/packages/edge/aarch64
C=$PMB_WORK/cache_apk_aarch64
DEV=$PMOS_DEVICE
TAR="$DL_DIR/ArchLinuxARM-aarch64-latest.tar.gz"
ORDER=(qrtr rmtfs tqftpserv hexagonrpcd linux-samsung-r9q firmware-samsung-r9q device-samsung-r9q
	mangohud ffmpeg8-compat gamescope-session-plus gamescope-session-steam steam-session-r9q
	plasma-mobile-r9q)
[ $# -gt 0 ] && ORDER=("$@")

# 1. base image from the verified ALARM tarball, then a builder image
if ! podman image exists localhost/alarm-r9q:base; then
	podman import --arch arm64 --change 'CMD ["/bin/bash"]' "$TAR" localhost/alarm-r9q:base
fi
if ! podman image exists localhost/alarm-r9q:builder; then
	podman rm -f r9q-builder-prep >/dev/null 2>&1 || true
	podman run --name r9q-builder-prep --arch arm64 localhost/alarm-r9q:base /bin/bash -euxc '
		# container + qemu: no Landlock download sandbox, no mount-based space check
		sed -i -e "s/^#\?DisableSandbox.*/DisableSandbox/" -e "s/^CheckSpace/#CheckSpace/" /etc/pacman.conf
		grep -q "^DisableSandbox" /etc/pacman.conf || sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
		pacman-key --init
		pacman-key --populate archlinuxarm
		pacman -Syu --noconfirm --needed base-devel meson git sudo
		useradd -m builder
		echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
		pacman -Scc --noconfirm'
	podman commit r9q-builder-prep localhost/alarm-r9q:builder
	podman rm r9q-builder-prep
fi

# 2. stage the PKGBUILD dirs plus the inputs they repack/share
W="$WORK_DIR/pkgs"
rm -rf "$W"; mkdir -p "$W" "$LOCAL_REPO"
for p in "${ORDER[@]}"; do cp -a "$PKGS_DIR/$p" "$W"/; done
building() { [[ " ${ORDER[*]} " == *" $1 "* ]]; }
if building linux-samsung-r9q; then
	krel=$(sed -n 's/^pkgrel=//p' "$PKGS_DIR/linux-samsung-r9q/PKGBUILD")
	cp "$P/linux-samsung-r9q-7.2.13-r$krel.apk" "$W/linux-samsung-r9q/"
fi
if building firmware-samsung-r9q; then
	cp "$P"/firmware-samsung-r9q-{adreno,adsp,audio,cdsp,hexagonfs,modem,slpi,wifi}-1-r5.apk "$W/firmware-samsung-r9q/"
	cp "$(ls "$C"/firmware-qcom-adreno-a660-*.apk | tail -n1)" "$W/firmware-samsung-r9q/firmware-qcom-adreno-a660.apk"
	cp "$VENDOR_FW"/{hpbtfw21.tlv,hpnv21g.baa} "$W/firmware-samsung-r9q/"
fi
if building device-samsung-r9q; then
	for f in ucm-HiFi.conf ucm-Samsung-Galaxy-S21-FE.conf 81-libssc-samsung-r9q.rules \
		modprobe-samsung-r9q.conf iio-sensor-proxy-samsung-r9q.conf kwinrc; do
		cp "$DEV/$f" "$W/device-samsung-r9q/"
	done
fi

# 3. build in order; local packages are installed so later ones can depend on them
podman run --rm --arch arm64 -v "$W":/stage:ro -v "$LOCAL_REPO":/repo localhost/alarm-r9q:builder /bin/bash -euc '
	cp -a /stage /build && chown -R builder: /build
	cat >> /etc/pacman.conf <<EOF
[r9q]
SigLevel = Optional TrustAll
Server = file:///repo
EOF
	[ -f /repo/r9q.db.tar.gz ] || repo-add -q /repo/r9q.db.tar.gz
	pacman -Sy --noconfirm >/dev/null
	for p in '"${ORDER[*]}"'; do
		echo "=== $p"
		cd /build/$p
		# Under qemu-user the setuid bit is ignored, so makepkg -s (sudo from
		# the builder user) cannot install anything: root installs the
		# makedepends, and runtime depends are not needed to build (-d).
		mk=$(sudo -u builder makepkg --printsrcinfo | sed -n "s/^\tmakedepends = //p")
		[ -z "$mk" ] || pacman -S --noconfirm --needed --asdeps $mk
		sudo -u builder makepkg -d --noconfirm --cleanbuild -f
		for f in *.pkg.tar.*; do
			cp "$f" /repo/
			repo-add -q -R /repo/r9q.db.tar.gz /repo/"$f"
		done
		pacman -Sy --noconfirm >/dev/null
		# runtime deps of the next packages (qrtr for rmtfs/tqftpserv)
		[ "$p" = qrtr ] && pacman -S --noconfirm --needed qrtr
	done
	echo PKGS_DONE'
ls -la "$LOCAL_REPO"
