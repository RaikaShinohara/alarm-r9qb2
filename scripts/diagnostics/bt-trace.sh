#!/bin/sh
# Run as root on the phone: install btmon (Alpine bluez-btmon, signature
# checked by apk), trace HCI while pairing a device, save the trace for the
# user. Usage: sudo sh bt-trace.sh <MAC>
M=$1
H=/home/alarm
apk info -e bluez-btmon >/dev/null || apk add "$H/bluez-btmon-5.87-r0.apk" || exit 1
btmon > "$H/bt-trace.txt" 2>&1 &
P=$!
sleep 2
echo "== pair $M"
bluetoothctl --timeout 20 pair "$M"
sleep 1
echo "== connect $M"
bluetoothctl --timeout 15 connect "$M"
sleep 2
kill $P
chown alarm "$H/bt-trace.txt"
echo "trace: $(wc -l < "$H/bt-trace.txt") lines in $H/bt-trace.txt"
