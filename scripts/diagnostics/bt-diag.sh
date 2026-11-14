#!/bin/sh
# Bluetooth controller state as root: is hci0 configured, what address it
# has, and whether powering it on brings it back. Output: ~/bt-diag.txt
OUT=/home/alarm/bt-diag.txt
{
	echo "== mgmt"; btmgmt info; btmgmt config 2>&1 | head -3
	echo "== debugfs"; mount -t debugfs none /sys/kernel/debug 2>/dev/null
	for f in identity manufacturer hci_version hci_revision quirk_strict_duplicate_filter; do
		printf '%s: ' $f; cat /sys/kernel/debug/bluetooth/hci0/$f 2>&1
	done
	echo "== flags"; cat /sys/class/bluetooth/hci0/power/runtime_status 2>&1
	echo "== power on"; btmgmt -i hci0 power on 2>&1; sleep 3
	btmgmt info 2>&1 | head -8
	echo "== kernel"; dmesg | grep -iE "hci0|bluetooth: |qca" | tail -15
	echo "== bluez"; bluetoothctl list 2>&1
} > "$OUT" 2>&1
chown alarm:alarm "$OUT"
