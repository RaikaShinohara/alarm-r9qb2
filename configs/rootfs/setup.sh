#!/bin/bash
# Runs as root inside the aarch64 ALARM container started by build-image.sh:
# turns the stock Arch Linux ARM rootfs into the Galaxy S21 FE system, on par
# with the postmarketOS install (Plasma, audio, sensors, Wi-Fi, BT, USB SSH).
# Inputs: /repo (our packages, work/repo) and /setup (settings, the
# user's password hash, authorized_keys).
set -euxo pipefail
. /setup/settings   # EDITION BOOT_MODE USER_NAME HOST_NAME LOCALE TIMEZONE KEYMAP
BOOT_MODE=${BOOT_MODE:-abl}
case "$BOOT_MODE" in abl | uefi) ;; *) echo "unknown BOOT_MODE '$BOOT_MODE'"; exit 1 ;; esac
# EDITION: kde = Plasma desktop with its login screen; steam = the same plus
# Steam's game mode (gamescope + arm64 client), booted into by default;
# mobile = the same Plasma plus Plasma Mobile, booted into by default, with a
# desktop panel on external screens (DeX style)
case "$EDITION" in kde | steam | mobile) ;; *) echo "unknown EDITION '$EDITION'"; exit 1 ;; esac

# --- pacman ------------------------------------------------------------------
# qemu-user container: no Landlock download sandbox, no mount-based space
# check (both restored at the end).
sed -i -e 's/^#\?DisableSandbox.*/DisableSandbox/' -e 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
# Never install linux-firmware's Bluetooth patches (with them BLE links drop,
# docs/porting-log.md row 28) nor the generic WCN6855 board-2.bin (ath11k would prefer
# it over our board.bin). Kept in the final pacman.conf.
sed -i '/^\[options\]/a NoExtract = usr/lib/firmware/qca/* usr/lib/firmware/ath11k/WCN6855/hw2.1/board-2.bin*' /etc/pacman.conf
cat >> /etc/pacman.conf <<'EOF'

[r9q]
SigLevel = Optional TrustAll
Server = file:///repo
EOF
pacman-key --init
pacman-key --populate archlinuxarm

# The ALARM generic kernel and firmware are replaced by ours
pacman -Rdd --noconfirm linux-aarch64 $(pacman -Qq | grep '^linux-firmware')

PKGS=(
	# device support (kernel, firmware, Qualcomm services, configs, boot images)
	device-samsung-r9q
	# Plasma, like postmarketos-ui-plasma-desktop (+ its login manager)
	plasma-desktop plasma-login-manager plasma-keyboard plasma-nm plasma-pa
	bluedevil kscreen powerdevil power-profiles-daemon upower
	breeze breeze-gtk kde-gtk-config xdg-desktop-portal-kde polkit-kde-agent
	kwallet-pam kinfocenter plasma-systemmonitor systemsettings kdeplasma-addons
	kio-extras xdg-user-dirs
	konsole dolphin kate spectacle ark gwenview firefox
	# audio: PipeWire (the UCM profile is the same one PulseAudio used)
	pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber alsa-utils
	# GPU: Adreno 660 (freedreno/turnip)
	mesa vulkan-freedreno vulkan-tools mesa-utils
	noto-fonts noto-fonts-emoji ttf-hack
	# same extras as the pmOS install, plus a few tools
	networkmanager wireless-regdb iw sudo nano less bash-completion htop
	usbutils pciutils i2c-tools dtc evtest
)
# game mode: Steam Big Picture in gamescope with the arm64 client (as ArmadaOS)
[ "$EDITION" = steam ] && PKGS+=(mangohud gamescope-session-plus gamescope-session-steam steam-session-r9q)
# Plasma Mobile (touch shell, terminal) with the desktop on external screens
[ "$EDITION" = mobile ] && PKGS+=(plasma-mobile qmlkonsole plasma-mobile-r9q)
pacman -Syu --noconfirm --needed "${PKGS[@]}"

# --- user --------------------------------------------------------------------
userdel -r alarm 2>/dev/null || true
useradd -m -G wheel,video,audio -s /bin/bash "$USER_NAME"
{ printf '%s:' "$USER_NAME"; cat /setup/hash; } | chpasswd -e
passwd -l root
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
install -d -m700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
install -m600 -o "$USER_NAME" -g "$USER_NAME" /setup/authorized_keys "/home/$USER_NAME/.ssh/authorized_keys"
if [ "$EDITION" = steam ] || [ "$EDITION" = mobile ]; then
	# game mode / Plasma Mobile log in automatically as this user (the
	# packages' install scripts ran while ALARM's alarm user still had uid
	# 1000: overwrite it)
	mkdir -p /etc/plasmalogin.conf.d
	printf '[Autologin]\nUser=%s\n' "$USER_NAME" > /etc/plasmalogin.conf.d/10-r9q-autologin.conf
fi
if [ "$EDITION" = steam ]; then
	# Steam ready at the first boot: seed Valve's arm64 client in the user's home
	# (Steam downloads the rest of its packages itself on its first start)
	runuser -u "$USER_NAME" -- env HOME="/home/$USER_NAME" /usr/lib/r9q/r9q-steam-bootstrap
fi
# which edition this is (shown by check-image.sh and the installer)
echo "$EDITION" > /etc/r9q/edition

# --- locale, time, identity ----------------------------------------------------
for l in "$LOCALE" en_US.UTF-8; do
	sed -i "s/^#\($l UTF-8\)/\1/" /etc/locale.gen
done
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
	Identifier "system-keyboard"
	MatchIsKeyboard "on"
	Option "XkbLayout" "$KEYMAP"
EndSection
EOF
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
# like deviceinfo_chassis: Plasma and hostnamed treat it as a phone
echo 'CHASSIS=handset' > /etc/machine-info
# /etc/hostname and /etc/resolv.conf are podman's while this runs: build-image.sh
# writes them afterwards.

# root: the image is small, growfs fills the partition on first boot.
#   abl : Linux alone, root on userdata
#   uefi: dual boot with Android: root on the "linux" partition, the ESP
#         (kernel, initramfs, DTB, systemd-boot) on /efi
if [ "$BOOT_MODE" = uefi ]; then
	install -d -m 700 /efi
	printf '%s\n' 'PARTLABEL=linux  /  ext4  defaults,noatime,x-systemd.growfs  0 1' \
		'PARTLABEL=esp  /efi  vfat  umask=0077,noatime,nofail  0 2' >> /etc/fstab
	sed -i -e 's/^BOOT_MODE=.*/BOOT_MODE=uefi/' \
		-e 's/root=PARTLABEL=userdata rw rootwait /root=PARTLABEL=linux rw rootwait acpi=off /' \
		/etc/r9q/bootimg.conf
	grep -q '^BOOT_MODE=uefi' /etc/r9q/bootimg.conf
	grep -q 'root=PARTLABEL=linux rw rootwait acpi=off ' /etc/r9q/bootimg.conf
else
	printf '%s\n' 'PARTLABEL=userdata  /  ext4  defaults,noatime,x-systemd.growfs  0 1' >> /etc/fstab
fi

# --- services ------------------------------------------------------------------
# NetworkManager replaces ALARM's systemd-networkd; resolved stays (DNS)
systemctl disable systemd-networkd.service systemd-networkd.socket \
	systemd-networkd-wait-online.service systemd-network-generator.service \
	systemd-networkd-resolve-hook.socket systemd-networkd-varlink.socket \
	systemd-networkd-varlink-metrics.socket || true
systemctl enable NetworkManager.service bluetooth.service plasmalogin.service \
	sshd.service systemd-resolved.service systemd-timesyncd.service \
	power-profiles-daemon.service \
	rmtfs.service tqftpserv.service hexagonrpcd-sdsp.service \
	r9q-usb-gadget.service r9q-usb-dhcp.service

# SSH: password logins only over the USB cable (172.16.42.x, r9q-usb-gadget);
# from Wi-Fi only keys (the public image has a well-known alarm/alarm account)
install -d /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/10-r9q.conf
printf '\n# r9q: passwords only over the USB cable\nMatch Address 172.16.42.0/24\n\tPasswordAuthentication yes\n' >> /etc/ssh/sshd_config
grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' /etc/ssh/sshd_config
ssh-keygen -A >/dev/null
sshd -t
# (captured first: grep -q would close the pipe early and pipefail would fail)
usb=$(sshd -T -C addr=172.16.42.2,user="$USER_NAME",host=x,laddr=172.16.42.1,lport=22)
wifi=$(sshd -T -C addr=192.0.2.10,user="$USER_NAME",host=x,laddr=192.0.2.1,lport=22)
grep -qix 'passwordauthentication yes' <<< "$usb"
grep -qix 'passwordauthentication no' <<< "$wifi"

# The pacman keyring is created on the phone, not shipped from the build
# (unit from device-samsung-r9q)
systemctl enable r9q-pacman-init.service

# --- boot images -----------------------------------------------------------------
mkinitcpio -P
if [ "$BOOT_MODE" = uefi ]; then
	# the ESP's first contents, kept in the image: the TWRP zip copies them to
	# the phone's ESP (on the phone r9q-bootimg then writes /efi directly)
	R9Q_ESP=/boot/esp-initial /usr/lib/r9q/r9q-bootimg
	# the pacman hook ran in abl mode while the packages were installed
	# (before BOOT_MODE=uefi): those boot images belong to no partition here
	rm -f /boot/boot.img /boot/vendor_boot.img
	ls -laR /boot/esp-initial
else
	/usr/lib/r9q/r9q-bootimg
	ls -la /boot
fi

# --- cleanup -----------------------------------------------------------------------
# (pacman -Scc --noconfirm answers "no" to its own question: empty it by hand)
rm -rf /var/cache/pacman/pkg/*
rm -rf /etc/pacman.d/gnupg
# sshd generates its host keys on the phone (sshdgenkeys.service)
rm -f /etc/ssh/ssh_host_*
sed -i -e '/^DisableSandbox/d' -e 's/^#CheckSpace/CheckSpace/' -e '/^\[r9q\]/,$d' /etc/pacman.conf
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
echo SETUP_DONE
