#!/bin/sh
# Switch the QCA6490 Bluetooth between its ROM firmware (the default: no files
# in qca/) and Samsung's patch + NVM (hpbtfw21.tlv + hpnv21g.baa as
# hpnv21g.bin), put in /usr/lib/firmware/updates/qca (searched first by the
# kernel, owned by no package), then rebind the driver: no reboot needed.
# Usage (as root on the phone): sh bt-fw-switch.sh patch|rom
#   patch expects the two files in /home/alarm/bt-fw/
set -eu
U=/usr/lib/firmware/updates/qca
case "${1:-}" in
patch)
	install -Dm644 /home/alarm/bt-fw/hpbtfw21.tlv "$U/hpbtfw21.tlv"
	install -Dm644 /home/alarm/bt-fw/hpnv21g.bin "$U/hpnv21g.bin"
	;;
rom)
	rm -rf "$U"
	;;
*)
	echo "usage: $0 patch|rom" >&2
	exit 2
	;;
esac
start=$(date '+%F %T')
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind
sleep 2
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind
sleep 6
journalctl -k --since "$start" -o cat | grep -E "hci0" | grep -vE "Direct firmware load|Failed to request" | tail -12
# a patched controller may come up without a usable address ("unconfigured"):
# give it a stable, locally administered one derived from the machine-id
if ! bluetoothctl list | grep -q Controller; then
	addr=$(sha256sum /etc/machine-id | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*/02:\1:\2:\3:\4:\5/')
	echo "controller unconfigured: setting public address $addr"
	btmgmt -i hci0 public-addr "$addr" || true
	sleep 2
fi
rfkill unblock bluetooth
yes | btmgmt -i hci0 power on >/dev/null 2>&1 || true
sleep 1
bluetoothctl show | grep -E "Controller|Powered"
echo "BT_FW_$1"
