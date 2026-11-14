#!/bin/bash
# Update an installed Arch phone in place (no TWRP, userdata kept): copy the
# newest packages from work/repo over SSH and install them with pacman.
# Its hooks rebuild the initramfs and, through device-samsung-r9q's
# r9q-bootimg hook, build and flash boot.img / vendor_boot.img. Then reboot.
# Asks for the phone's sudo password once.
# Usage: bash scripts/update-phone.sh [--sync] [package ...]   (default: all of ours)
#   --sync: first a full `pacman -Syu` (needs Wi-Fi on the phone), so new
#           dependencies from the Arch Linux ARM repos (e.g. gamescope) can be installed
set -eu
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
S=(-o UserKnownHostsFile=$KNOWN_HOSTS -o HostKeyAlias=172.16.42.1 -o ConnectTimeout=5)
H=${PHONE_USER:-alarm}@${PHONE_IP:-172.16.42.1}
SYNC=0
[ "${1:-}" = --sync ] && { SYNC=1; shift; }
PKGS=(qrtr rmtfs tqftpserv hexagonrpcd linux-samsung-r9q firmware-samsung-r9q device-samsung-r9q
	mangohud gamescope-session-plus gamescope-session-steam steam-session-r9q)
[ $# -gt 0 ] && PKGS=("$@")

FILES=()
for p in "${PKGS[@]}"; do
	# newest build of each package (the repo keeps older files too)
	f=$(ls -t "$LOCAL_REPO/$p"-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -n1)
	[ -s "$f" ] || { echo "missing $p in $LOCAL_REPO (run scripts/build-packages.sh)"; exit 1; }
	FILES+=("$f")
done
echo "installing: $(printf '%s ' "${FILES[@]##*/}")"

ssh "${S[@]}" -o BatchMode=yes $H "rm -rf ~/pkgs && mkdir ~/pkgs"
for f in "${FILES[@]}"; do ssh "${S[@]}" -o BatchMode=yes $H "cat > ~/pkgs/${f##*/}" < "$f"; done

# The PMIC RTC starts in 1970 (docs/porting-log.md): if the phone is more than a day
# behind, give it the PC's time (timesyncd saves it at shutdown).
now=$(date -u +%s)
ssh -t "${S[@]}" $H 'set -e
if [ "$(date -u +%s)" -lt $(('"$now"' - 86400)) ]; then sudo date -u -s @'"$now"'; fi
if [ '"$SYNC"' = 1 ]; then sudo pacman -Syu --noconfirm; fi
# the Bluetooth firmware test (scripts/diagnostics/bt-fw-switch.sh) left unowned copies
# of the files firmware-samsung-r9q now ships: let pacman take them over
sudo pacman -U --needed --noconfirm --overwrite "/usr/lib/firmware/updates/qca/*" ~/pkgs/*.pkg.tar.*
# the clock is right now: keep its offset to the RTC for the next boots
if [ -x /usr/lib/r9q/r9q-clock ]; then sudo /usr/lib/r9q/r9q-clock save; fi
ls -la /boot/boot.img /boot/vendor_boot.img
echo "UPDATE_OK, rebooting"
sudo reboot'
