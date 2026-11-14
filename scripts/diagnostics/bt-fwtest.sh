#!/bin/sh
# Run as root on the phone. For each firmware set in ~alarm/btsets/<set>/
# (an empty set = the chip's ROM firmware): install it in /usr/lib/firmware/qca,
# re-run the Bluetooth setup by rebinding hci_uart_qca, then try to connect
# and pair <MAC> under btmon. Results in ~alarm/bt-fwtest/.
# Usage: sudo sh bt-fwtest.sh <MAC> <set>...
M=$1; shift
H=/home/alarm
O=$H/bt-fwtest; mkdir -p "$O"
Q=/usr/lib/firmware/qca
D=/sys/bus/serial/drivers/hci_uart_qca
for set in "$@"; do
	echo "===== set $set"
	rm -f $Q/hpbtfw21.tlv $Q/hpnv21.bin $Q/hpnv21g.bin $Q/wcnhpbtfw21.tlv $Q/wcnhpnv21*.bin
	[ -d "$H/btsets/$set" ] && cp "$H/btsets/$set"/* $Q/ 2>/dev/null
	ls $Q
	T0=$(cut -d' ' -f1 /proc/uptime)
	echo serial0-0 > $D/unbind; sleep 1; echo serial0-0 > $D/bind
	sleep 8
	dmesg | awk -v t="$T0" -F'[][]' '$2+0 > t' | grep -iE "qca|bluetooth" > "$O/$set-kernel.txt"
	grep -E "Downloading|FW build|setup|Failed" "$O/$set-kernel.txt" | sed 's/^/  /'
	bluetoothctl remove "$M" >/dev/null 2>&1
	btmon > "$O/$set-btmon.txt" 2>&1 &
	P=$!
	sleep 1
	bluetoothctl --timeout 8 scan on > /dev/null 2>&1
	bluetoothctl --timeout 15 pair "$M" > "$O/$set-pair.txt" 2>&1
	sleep 3
	bluetoothctl info "$M" > "$O/$set-info.txt" 2>&1
	kill $P
	F=$(grep -c "Connection Failed to be Established" "$O/$set-btmon.txt")
	S=$(grep -c "LE Enhanced Connection Complete" "$O/$set-btmon.txt")
	echo "  connections $S, failed-to-establish $F"
	grep -E "Paired|Connected" "$O/$set-info.txt" | sed 's/^/  /'
	grep -E "succe|Failed" "$O/$set-pair.txt" | sed 's/\x1b\[[0-9;]*m//g; s/^/  /' | head -3
done
chown -R alarm "$O"
echo "done: results in $O"
