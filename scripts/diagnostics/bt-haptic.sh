#!/bin/sh
# Bluetooth and haptic checks, run on the phone over ssh.
echo "== kernel"; uname -v; cat /proc/sys/kernel/random/boot_id
echo "== bluetooth"
ls /sys/class/bluetooth 2>&1
for h in /sys/class/bluetooth/hci*; do
	[ -e "$h" ] && echo "$(basename $h): address=$(cat $h/address 2>/dev/null)"
done
bluetoothctl show 2>&1 | head -12
echo "== haptic"
for p in /sys/class/input/event*/device/name; do echo "$p: $(cat $p)"; done
for d in /sys/class/pwm/pwmchip*; do [ -e "$d" ] && echo "$(basename $d) npwm=$(cat $d/npwm) $(readlink -f $d/device)"; done
echo "== kernel log"
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | grep -iE 'bluetooth|hci_uart|qca|btqca|serdev|890000|haptic|pwm|max77693' | grep -v Handover | tail -40
echo "== bluetoothd"
journalctl -b --no-pager -o short-monotonic -u bluetooth 2>/dev/null | grep -v "Endpoint registered" | tail -30
