#!/bin/sh
# Run as root on the phone: start a persistent logger (survives a hang: every
# line is synced to the rootfs), then boot the modem from /tmp/fw.
# Read the logs afterwards from TWRP: /home/alarm/modemtest/ on pmOS root.
D=/home/alarm/modemtest
mkdir -p $D
rm -f $D/*.txt
echo 8 > /proc/sys/kernel/printk

# kernel log, synced every second
( cat /dev/kmsg > $D/kmsg.txt ) &
( while true; do sync $D/kmsg.txt 2>/dev/null || sync; sleep 1; done ) &

# link / remoteproc status every second
(
while true; do
	echo "$(cut -d' ' -f1 /proc/uptime) usb0=$(cat /sys/class/net/usb0/operstate 2>/dev/null)/$(cat /sys/class/net/usb0/carrier 2>/dev/null) udc=$(cat /sys/class/udc/*/state 2>/dev/null) load=$(cut -d' ' -f1-3 /proc/loadavg) rproc=$(for r in /sys/class/remoteproc/remoteproc*; do printf '%s:%s ' $(cat $r/name) $(cat $r/state); done)"
	sync
	sleep 1
done > $D/status.txt
) &

sleep 3
echo "starting modem $(cut -d' ' -f1 /proc/uptime)" > $D/start.txt
echo /tmp/fw > /sys/module/firmware_class/parameters/path
for r in /sys/class/remoteproc/remoteproc*; do
	[ "$(cat $r/name)" = modem ] && echo start > $r/state && echo "start written to $r" >> $D/start.txt
done
sync
echo "logger running, modem started; logs in $D"
