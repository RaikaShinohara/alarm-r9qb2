#!/bin/bash
# Check the Arch image in work/out before flashing it (no root, no
# mount: debugfs reads the ext4 image, python parses the boot images).
# Usage: bash scripts/check-image.sh
set -uo pipefail
# Usage: [PUBLIC=1] EDITION=kde|steam|mobile bash scripts/check-image.sh
#   (checks out/$EDITION, or out/$EDITION-public: user alarm, no ssh keys)
#   DUAL=1: the dual boot image (out/$EDITION[-public]-dual: root on "linux",
#   kernel/initramfs/DTB/systemd-boot entry in esp/ instead of boot images)
EDITION=${EDITION:-steam}
if [ "${PUBLIC:-0}" = 1 ]; then SUF=-public; U=alarm; else SUF=; U=${IMG_USER:-alarm}; fi
DUAL=${DUAL:-0}
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
[ "$DUAL" = 1 ] && OUT="$OUT_BASE/$EDITION$SUF-dual" || OUT="$OUT_BASE/$EDITION$SUF"
IMG=$OUT/arch-r9q.img
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
# `|| true`: `grep -q` stops reading at the first match and debugfs then dies
# of SIGPIPE, which pipefail would count as a failure (large files)
dfs() { debugfs -R "$1" "$IMG" 2>/dev/null || true; }
has() { dfs "stat $1" | grep -q '^Inode:'; }
need() { for p in "$@"; do has "$p" && ok "$p" || bad "missing $p"; done; }
lacks() { for p in "$@"; do has "$p" && bad "should not exist: $p" || ok "absent $p"; done; }
cat_has() { dfs "cat $1" | grep -qE "$2" && ok "$1: $2" || bad "$1 lacks /$2/"; }

if [ "$DUAL" = 1 ]; then
for f in "$IMG" "$OUT/esp/arch/Image" "$OUT/esp/arch/initramfs.img" "$OUT/esp/arch/r9q.dtb" \
	"$OUT/esp/loader/entries/arch.conf" "$OUT/esp/EFI/BOOT/BOOTAA64.EFI"; do
	[ -s "$f" ] || { echo "missing $f"; exit 1; }
done
echo "== ESP (dual boot: started by the UEFI, boot/vendor_boot are Android's)"
python3 -I - "$OUT/esp" <<'EOF' || fail=1
import struct, sys, os
e = sys.argv[1]
ok = True
def chk(c, m):
    global ok
    print(("  ok   " if c else "  FAIL ") + m); ok &= c
k = open(os.path.join(e, "arch/Image"), "rb").read(0x200)
chk(k[:2] == b"MZ" and k[0x38:0x3C] == b"ARM\x64", "arch/Image: uncompressed arm64 Image with EFI stub")
pe = struct.unpack_from("<I", k, 0x3C)[0]
chk(k[pe:pe + 4] == b"PE\0\0" and struct.unpack_from("<H", k, pe + 4)[0] == 0xAA64, "arch/Image: PE for AArch64")
d = open(os.path.join(e, "arch/r9q.dtb"), "rb").read()
chk(d[:4] == b"\xd0\x0d\xfe\xed" and b"samsung,r9q" in d, "arch/r9q.dtb: the r9q device tree")
r = os.path.getsize(os.path.join(e, "arch/initramfs.img"))
chk(0 < r < 64 << 20, f"arch/initramfs.img {r >> 20} MiB")
s = open(os.path.join(e, "EFI/BOOT/BOOTAA64.EFI"), "rb").read(0x400)
pe = struct.unpack_from("<I", s, 0x3C)[0]
chk(s[:2] == b"MZ" and struct.unpack_from("<H", s, pe + 4)[0] == 0xAA64, "EFI/BOOT/BOOTAA64.EFI: AArch64 EFI app (systemd-boot)")
c = open(os.path.join(e, "loader/entries/arch.conf")).read()
for w in ("linux      /arch/Image", "initrd     /arch/initramfs.img", "devicetree /arch/r9q.dtb",
          "root=PARTLABEL=linux", "acpi=off", "rootwait", "clk_ignore_unused", "panel_samsung_ea8082.refresh_rate=120"):
    chk(w in c, f"arch.conf has {w.split()[0] if w.startswith(('linux ', 'initrd', 'devicetree')) else w}")
chk("PARTLABEL=userdata" not in c, "arch.conf does not point at userdata (Android's)")
sys.exit(0 if ok else 1)
EOF
else
for f in "$IMG" "$OUT/boot.img" "$OUT/vendor_boot.img"; do [ -s "$f" ] || { echo "missing $f"; exit 1; }; done

echo "== boot images"
python3 -I - "$OUT/boot.img" "$OUT/vendor_boot.img" <<'EOF' || fail=1
import struct, sys
b = open(sys.argv[1], "rb").read()
v = open(sys.argv[2], "rb").read()
ok = True
def chk(c, m):
    global ok
    print(("  ok   " if c else "  FAIL ") + m); ok &= c
chk(b[:8] == b"ANDROID!", "boot.img magic")
ksize, rsize, osv, hsize = struct.unpack_from("<4I", b, 8)
hver = struct.unpack_from("<I", b, 40)[0]
chk(hver == 3, f"boot.img header v{hver}")
chk(b[4096:4098] == b"\x1f\x8b", f"boot.img kernel is gzip ({ksize} bytes)")
chk(rsize == 0, "boot.img has no ramdisk (it is in vendor_boot)")
chk(v[:8] == b"VNDRBOOT", "vendor_boot.img magic")
vh, page, kaddr, raddr, vrsize = struct.unpack_from("<5I", v, 8)
cmd = v[28:28 + 2048].split(b"\0")[0].decode()
tags = struct.unpack_from("<I", v, 28 + 2048)[0]
name = v[28 + 2048 + 4:28 + 2048 + 20].split(b"\0")[0].decode()
hsz, dtbsz = struct.unpack_from("<2I", v, 28 + 2048 + 20)
chk(vh == 3 and page == 4096, f"vendor_boot v{vh} page {page}")
chk(name == "SRPVC21A007", f"board {name}")
chk(kaddr == 0x8000 and raddr == 0x2000000 and tags == 0x1e00000, "load addresses")
chk(dtbsz > 0, f"DTB {dtbsz} bytes")
chk(0 < vrsize < 64 << 20, f"initramfs {vrsize >> 20} MiB")
for w in ("root=PARTLABEL=userdata", "rootwait", "clk_ignore_unused", "panel_samsung_ea8082.refresh_rate=120"):
    chk(w in cmd, f"cmdline has {w}")
print("  cmdline:", cmd)
sys.exit(0 if ok else 1)
EOF
fi

echo "== filesystem"
dumpe2fs -h "$IMG" 2>/dev/null | grep -E '^(Filesystem volume name|Block size|Filesystem features)'
dumpe2fs -h "$IMG" 2>/dev/null | grep -q '^Block size: *4096' && ok "4 KiB blocks" || bad "block size"
dumpe2fs -h "$IMG" 2>/dev/null | grep '^Filesystem features' | grep -q orphan_file && bad "orphan_file set (TWRP cannot mount)" || ok "no orphan_file"

echo "== kernel, firmware, boot"
kver=7.2.13
need /usr/lib/modules/$kver/vmlinuz /usr/lib/modules/$kver/modules.dep \
	/usr/lib/modules/$kver/dtbs/qcom/sm8350-samsung-r9q.dtb \
	/boot/vmlinuz-linux-samsung-r9q /boot/initramfs-linux-samsung-r9q.img \
	/usr/lib/firmware/qcom/a660_sqe.fw /usr/lib/firmware/ath11k/WCN6855/hw2.1/board.bin
lacks /usr/lib/firmware/qca /usr/lib/firmware/ath11k/WCN6855/hw2.1/board-2.bin /etc/mkinitcpio.d/linux-aarch64.preset
dfs "ls /usr/lib/modules/$kver/kernel/drivers/usb/typec" | grep -q max77705_typec && ok "max77705_typec module" || bad "max77705_typec module"

echo "== device configuration"
need /etc/xdg/kwinrc /usr/share/alsa/ucm2/Samsung/r9q/HiFi.conf \
	/usr/share/alsa/ucm2/conf.d/sm8350/Samsung-Galaxy-S21-FE.conf \
	/usr/lib/udev/rules.d/81-libssc-samsung-r9q.rules /usr/lib/udev/rules.d/82-r9q-bluetooth.rules \
	/usr/lib/systemd/system/iio-sensor-proxy.service.d/10-samsung-r9q.conf \
	/usr/lib/systemd/system/rmtfs.service.d/10-samsung-r9q.conf \
	/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf /usr/lib/modprobe.d/samsung-r9q.conf \
	/usr/share/applications/org.kde.plasma.keyboard.desktop \
	/usr/lib/udev/rules.d/90-iio-sensor-proxy-ssc.rules /usr/lib/clock-epoch \
	/usr/lib/systemd/system/r9q-pacman-init.service \
	/usr/lib/r9q/r9q-clock /usr/lib/udev/rules.d/83-r9q-clock.rules \
	/usr/lib/r9q/r9q-macs /usr/lib/systemd/system/multi-user.target.wants/r9q-macs.service \
	/usr/lib/firmware/updates/qca/hpbtfw21.tlv /usr/lib/firmware/updates/qca/hpnv21g.bin \
	/usr/lib/systemd/system/multi-user.target.wants/r9q-clock-sync.path
lacks /etc/systemd/system/r9q-pacman-init.service
cat_has /usr/lib/udev/rules.d/90-iio-sensor-proxy-ssc.rules 'fastrpc-sdsp.*ssc-accel ssc-proximity'
cat_has /usr/lib/modprobe.d/samsung-r9q.conf '^blacklist qcrypto'
cat_has /usr/share/alsa/ucm2/Samsung/r9q/HiFi.conf 'DSP RX2 Source.*ASPRX1'
cat_has /usr/lib/systemd/system/rmtfs.service.d/10-samsung-r9q.conf '^ExecStart=/usr/bin/rmtfs -r -P$'
dfs "cat /usr/lib/systemd/system/rmtfs.service.d/10-samsung-r9q.conf" | grep -q -- ' -s' && bad "rmtfs would boot the modem (-s)" || ok "rmtfs without -s"
cat_has /etc/mkinitcpio.conf.d/10-r9q.conf '^HOOKS=\(base systemd modconf fsck\)'

echo "== services"
W=/etc/systemd/system
need $W/multi-user.target.wants/NetworkManager.service $W/display-manager.service \
	$W/multi-user.target.wants/sshd.service $W/multi-user.target.wants/rmtfs.service \
	$W/multi-user.target.wants/tqftpserv.service $W/multi-user.target.wants/hexagonrpcd-sdsp.service \
	$W/multi-user.target.wants/r9q-usb-gadget.service $W/multi-user.target.wants/r9q-usb-dhcp.service \
	$W/bluetooth.target.wants/bluetooth.service $W/multi-user.target.wants/r9q-pacman-init.service
lacks $W/multi-user.target.wants/systemd-networkd.service
dfs "stat $W/display-manager.service" | grep -q plasmalogin && ok "display manager = plasmalogin" || bad "display manager"
dfs "stat $W/systemd-firstboot.service" | grep -q '/dev/null' && ok "systemd-firstboot masked" || bad "systemd-firstboot not masked"

echo "== system identity and users"
if [ "$DUAL" = 1 ]; then
	need /boot/esp-initial/arch/Image /efi
	lacks /boot/boot.img /boot/vendor_boot.img
	cat_has /etc/fstab '^PARTLABEL=linux +/ +ext4 .*x-systemd.growfs'
	cat_has /etc/fstab '^PARTLABEL=esp +/efi +vfat '
	dfs "cat /etc/fstab" | grep -q '^PARTLABEL=userdata' && bad "fstab mounts userdata (Android's)" || ok "fstab leaves userdata alone"
	cat_has /etc/r9q/bootimg.conf '^BOOT_MODE=uefi$'
	cat_has /etc/r9q/bootimg.conf 'root=PARTLABEL=linux rw rootwait acpi=off '
else
	need /boot/boot.img /boot/vendor_boot.img
	cat_has /etc/fstab '^PARTLABEL=userdata +/ +ext4 .*x-systemd.growfs'
	cat_has /etc/r9q/bootimg.conf '^BOOT_MODE=abl$'
fi
cat_has /etc/hostname '^r9q-arch$'
if [ -n "$SUF" ]; then cat_has /etc/locale.conf "^LANG=${LOCALE:-en_US.UTF-8}"; else cat_has /etc/locale.conf '^LANG=es_ES.UTF-8'; fi
cat_has /etc/machine-info '^CHASSIS=handset'
dfs "stat /etc/resolv.conf" | grep -q 'stub-resolv.conf' && ok "resolv.conf -> systemd-resolved stub" || bad "resolv.conf"
[ "$(dfs 'stat /etc/machine-id' | sed -n 's/.*Size: \([0-9]*\).*/\1/p' | head -1)" = 0 ] && ok "machine-id empty" || bad "machine-id not empty"
cat_has /etc/passwd "^$U:x:1000:"
if [ "$U" != alarm ]; then dfs "cat /etc/passwd" | grep -q '^alarm:' && bad "alarm user still there" || ok "no alarm user"; fi
dfs "cat /etc/shadow" | grep -qE '^root:!' && ok "root locked" || bad "root not locked"
dfs "cat /etc/shadow" | grep -qE "^$U:\\\$6\\\$" && ok "$U has a password" || bad "$U password"
cat_has /etc/group "^wheel:x:[0-9]+:.*$U"
cat_has /etc/sudoers.d/10-wheel '^%wheel ALL=\(ALL:ALL\) ALL'

echo "== edition: $EDITION"
cat_has /etc/r9q/edition "^$EDITION\$"
if [ "$EDITION" = steam ]; then
need /usr/bin/steam /usr/bin/gamescope /usr/bin/mangoapp /usr/share/wayland-sessions/gamescope-session-steam.desktop \
	/usr/lib/os-session-select /usr/lib/plasmalogin/plasmalogin.conf.d/50-r9q-gaming.conf \
	/home/$U/.local/share/Steam/steamrtarm64/steam \
	/home/$U/.local/share/Steam/steam-runtime-steamrt-arm64
cat_has /etc/plasmalogin.conf.d/10-r9q-autologin.conf "^User=$U\$"
cat_has /etc/gamescope-session-plus/sessions.d/steam '^ORIENTATION=right$'
cat_has /usr/lib/udev/rules.d/60-steam-input.rules 'KERNEL=="uinput".*uaccess'
# the FFmpeg libraries the client's libvideo.so links (it is loaded by
# steamui.so: one missing and game mode stays black) must be in /usr/lib
t=$(mktemp -d)
dfs "dump /home/$U/.local/share/Steam/steamrtarm64/libvideo.so $t/libvideo.so" >/dev/null
for l in $(readelf -d "$t/libvideo.so" 2>/dev/null | sed -n 's/.*\[\(lib\(av\|sw\)[a-z]*\.so\.[0-9]*\)\].*/\1/p'); do
	need "/usr/lib/$l"
done
[ -s "$t/libvideo.so" ] && ok "libvideo.so read" || bad "cannot read the client's libvideo.so"
rm -rf "$t"
elif [ "$EDITION" = mobile ]; then
need /usr/bin/startplasmamobile /usr/share/wayland-sessions/plasma-mobile.desktop \
	/usr/share/plasma/shells/org.kde.plasma.mobileshell/metadata.json \
	/usr/lib/plasmalogin/plasmalogin.conf.d/50-r9q-mobile.conf \
	/usr/lib/r9q/r9q-dock /usr/share/r9q/r9q-dock.js /etc/xdg/autostart/r9q-dock.desktop /usr/bin/startplasma-wayland
cat_has /etc/plasmalogin.conf.d/10-r9q-autologin.conf "^User=$U\$"
cat_has /usr/lib/plasmalogin/plasmalogin.conf.d/50-r9q-mobile.conf '^Session=plasma-mobile.desktop$'
lacks /usr/bin/gamescope /usr/lib/os-session-select /home/$U/.local/share/Steam
else
lacks /usr/bin/gamescope /usr/lib/os-session-select /etc/plasmalogin.conf.d/10-r9q-autologin.conf \
	/home/$U/.local/share/Steam
fi
cat_has /usr/lib/systemd/zram-generator.conf '^zram-size = ram \* 1.5'
cat_has /usr/lib/sysctl.d/90-r9q-zram.conf '^vm.swappiness = 180'
if [ -n "$SUF" ]; then
	[ -z "$(dfs "cat /home/$U/.ssh/authorized_keys")" ] && ok "no ssh keys authorized" || bad "public image authorizes ssh keys"
	# the password must be the documented one (alarm), nothing else
	h=$(dfs "cat /etc/shadow" | sed -n "s/^$U:\([^:]*\):.*/\1/p")
	salt=$(echo "$h" | cut -d'$' -f3)
	[ -n "$salt" ] && [ "$(openssl passwd -6 -salt "$salt" alarm)" = "$h" ] && ok "$U password is 'alarm'" || bad "$U password is not 'alarm'"
	for k in "$HOME"/.ssh/*.pub; do
		[ -f "$k" ] || continue
		dfs "cat /home/$U/.ssh/authorized_keys" | grep -qF "$(cut -d' ' -f2 "$k")" && bad "PC key $(basename "$k") in image"
	done
else
	dfs "cat /home/$U/.ssh/authorized_keys" | grep -q "$(cut -d' ' -f2 "$HOME/.ssh/id_ed25519.pub")" && ok "PC ssh key authorized" || bad "PC ssh key"
fi
cat_has /etc/ssh/sshd_config.d/10-r9q.conf '^PasswordAuthentication no'
cat_has /etc/ssh/sshd_config '^Match Address 172.16.42.0/24'
dfs "ls /etc/ssh" | grep -q ssh_host_ && bad "ssh host keys shipped" || ok "no ssh host keys"
has /etc/pacman.d/gnupg && bad "pacman keyring shipped" || ok "no pacman keyring (made on first boot)"
cat_has /etc/pacman.conf '^NoExtract = usr/lib/firmware/qca/\*'
dfs "cat /etc/pacman.conf" | grep -qE '^\[r9q\]|^DisableSandbox' && bad "build-only pacman.conf settings left" || ok "pacman.conf clean"
[ "$(dfs 'ls /var/cache/pacman/pkg' | grep -c 'pkg.tar')" = 0 ] && ok "package cache empty" || bad "package cache not empty"

echo
[ $fail = 0 ] && echo CHECK_OK || { echo CHECK_FAILED; exit 1; }
