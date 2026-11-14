#!/bin/sh
# DisplayPort alternate mode checks, run on the phone over ssh.
echo "== kernel"; uname -v; cat /proc/sys/kernel/random/boot_id
echo "== typec port"
p=/sys/class/typec/port0
for a in data_role power_role orientation; do echo "$a: $(cat $p/$a 2>/dev/null)"; done
echo "== typec switches/muxes"
ls /sys/class/typec_mux 2>/dev/null
echo "== drm connectors"
for c in /sys/class/drm/card*-*; do
	[ -e "$c/status" ] && echo "$(basename $c): $(cat $c/status) enabled=$(cat $c/enabled 2>/dev/null)"
done
echo "== drivers bound"
for d in usb-sbu-mux 88e8000.phy ae90000.displayport-controller; do
	l=$(readlink /sys/bus/platform/devices/$d/driver 2>/dev/null)
	echo "$d -> ${l##*/}"
done
echo "== kernel log"
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | grep -iE 'max77705|typec|sbu|qmp|88e8000|displayport|msm_dp|\[drm\]|dp_|hpd|panel|dsi|deferred|probe of' | grep -v Handover | tail -60
