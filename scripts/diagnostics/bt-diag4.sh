#!/bin/sh
# Does a real rfkill block -> unblock transition clear the stale HCI_RFKILLED
# flag? Output: ~/bt-diag4.txt
OUT=/home/alarm/bt-diag4.txt
{
	H=$(ls /sys/class/bluetooth/ | grep -m1 '^hci[0-9]*$')
	echo "== before"; rfkill list bluetooth; hciconfig "$H" up; echo "up rc=$?"
	echo "== block / unblock"
	rfkill block bluetooth; sleep 1; rfkill list bluetooth | grep Soft
	rfkill unblock bluetooth; sleep 1; rfkill list bluetooth | grep Soft
	hciconfig "$H" up; echo "up rc=$?"; sleep 2
	hciconfig "$H" | sed -n '2,3p'
	btmgmt info 2>&1 | head -5
	bluetoothctl show 2>&1 | grep -E "Controller|Powered" | head -3
} > "$OUT" 2>&1
chown alarm:alarm "$OUT"
