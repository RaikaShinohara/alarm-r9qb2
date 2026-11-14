#!/bin/sh
# USB-C / OTG / charging checks, run on the phone over ssh (no root needed
# for most of it; dmesg goes through sudo -n if allowed, else is skipped).
echo "== kernel"; uname -r; cat /proc/cmdline | cut -c1-200
echo "== typec"
for p in /sys/class/typec/*; do
	[ -e "$p" ] || { echo "no typec ports"; break; }
	echo "-- $p"
	for a in data_role power_role power_operation_mode orientation \
		port_type preferred_role usb_power_delivery_revision vconn_source; do
		[ -r "$p/$a" ] && echo "$a: $(cat "$p/$a" 2>/dev/null)"
	done
done
echo "== usb_role"
for r in /sys/class/usb_role/*; do
	[ -e "$r" ] && echo "$r: $(cat "$r/role" 2>/dev/null)"
done
echo "== regulators (vbus/otg)"
for r in /sys/class/regulator/regulator.*; do
	n=$(cat "$r/name" 2>/dev/null)
	case "$n" in *otg*|*vbus*|*VBUS*) echo "$n: state=$(cat "$r/state" 2>/dev/null) users=$(cat "$r/num_users" 2>/dev/null)";; esac
done
echo "== power_supply"
for s in /sys/class/power_supply/*; do
	[ -e "$s" ] || continue
	echo "-- $(basename "$s")"
	grep -E 'ONLINE|STATUS|PRESENT|CAPACITY=|VOLTAGE_NOW|CURRENT_NOW|INPUT_CURRENT_LIMIT|CONSTANT_CHARGE|USB_TYPE|CHARGE_TYPE|HEALTH' "$s/uevent" 2>/dev/null
done
echo "== usb devices"
for d in /sys/bus/usb/devices/*; do
	[ -r "$d/idVendor" ] && echo "$(basename "$d") $(cat "$d/idVendor"):$(cat "$d/idProduct") speed=$(cat "$d/speed" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
done
echo "== udc"
ls /sys/class/udc 2>/dev/null; for u in /sys/class/udc/*; do [ -e "$u" ] && echo "$(basename "$u"): state=$(cat "$u/state" 2>/dev/null)"; done
echo "== dmesg"
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | grep -iE 'max77705|typec|dwc3|usb_role|role.switch|xhci|otg|vbus|power_supply|charger' | tail -80 || echo "(dmesg not readable)"
