#!/bin/sh
# Runs on the phone in the background: logs every change of the USB-C /
# role / VBUS / charger / USB device state to ~/usblog/state.log, so a
# hot-plug test done with the PC cable unplugged can be read afterwards.
D=$HOME/usblog; mkdir -p "$D"; L=$D/state.log
snap() {
	p=/sys/class/typec/port0
	partner=no; [ -e /sys/class/typec/port0-partner ] && partner=yes
	echo "partner=$partner data=$(cat $p/data_role 2>/dev/null) power=$(cat $p/power_role 2>/dev/null) opmode=$(cat $p/power_operation_mode 2>/dev/null) orient=$(cat $p/orientation 2>/dev/null)"
	echo "role=$(cat /sys/class/usb_role/*/role 2>/dev/null) udc=$(cat /sys/class/udc/*/state 2>/dev/null)"
	for r in /sys/class/regulator/regulator.*; do
		[ "$(cat $r/name 2>/dev/null)" = usb_otg_vbus ] && echo "vbus=$(cat $r/state)"
	done
	c=/sys/class/power_supply/max77705-charger
	echo "chg_online=$(cat $c/online 2>/dev/null) chg_status=$(cat $c/status 2>/dev/null) ilim=$(cat $c/input_current_limit 2>/dev/null)"
	u=/sys/class/power_supply/max77705-usbc
	echo "usbc_online=$(cat $u/online 2>/dev/null) usbc_v=$(cat $u/voltage_now 2>/dev/null) usbc_type=$(cat $u/usb_type 2>/dev/null)"
	for d in /sys/bus/usb/devices/*; do
		[ -r "$d/idVendor" ] && echo "usb $(basename $d) $(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/speed 2>/dev/null) $(cat $d/product 2>/dev/null)"
	done
	for c in /sys/class/drm/card*-DP-*; do
		[ -e "$c/status" ] && echo "drm $(basename $c) $(cat $c/status) $(cat $c/enabled 2>/dev/null) modes=$(head -3 $c/modes 2>/dev/null | tr '\n' ' ')"
	done
}
prev=""
echo "=== logger start $(date) boot $(cat /proc/sys/kernel/random/boot_id)" >> "$L"
while :; do
	cur=$(snap)
	if [ "$cur" != "$prev" ]; then
		{ echo "--- $(date +%T) up=$(cut -d' ' -f1 /proc/uptime)"; echo "$cur"; } >> "$L"
		prev=$cur
	fi
	sleep 1
done
