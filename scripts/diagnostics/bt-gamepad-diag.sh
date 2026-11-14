#!/bin/sh
# Run as root on the phone: record the Bluetooth HCI traffic (btmon) while a
# game controller connects, stop as soon as the QCA chip crashes ("hardware
# error"), then keep its firmware dump (devcoredump) and the logs.
# Usage (on the PC): copy it to the phone, then
#   ssh -t ... alarm@172.16.42.1 'sudo sh ~/bt-gamepad-diag.sh'
O=/tmp/bt-diag
rm -rf "$O"
mkdir -p "$O"
for d in /sys/class/devcoredump/devcd*; do
	[ -e "$d/data" ] && cp "$d/data" "$O/old-${d##*/}.bin"
done
start=$(date '+%F %T')
btmon -w "$O/hci.btsnoop" >/dev/null 2>&1 &
B=$!
echo ">>> Turn the controller on now (PS button) and use it normally; waiting up to 90 s..."
end=$(($(date +%s) + 90))
while [ "$(date +%s)" -lt "$end" ]; do
	if journalctl -k --since "$start" -o cat | grep -q "hardware error"; then
		echo ">>> chip crash captured"
		sleep 4
		break
	fi
	sleep 1
done
kill "$B" 2>/dev/null
sleep 1
for d in /sys/class/devcoredump/devcd*; do
	[ -e "$d/data" ] && cp "$d/data" "$O/new-${d##*/}.bin"
done
journalctl -b -k -o short-monotonic | grep -iE "hci0|bluetooth|playstation|hid|uhid" > "$O/kernel.txt"
journalctl -b -u bluetooth -o short-monotonic > "$O/bluetoothd.txt"
for a in $(bluetoothctl devices | cut -d" " -f2); do bluetoothctl info "$a"; done > "$O/device.txt" 2>&1
chown -R alarm: "$O"
ls -la "$O"
echo "DIAG_DONE"
