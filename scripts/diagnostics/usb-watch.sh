#!/bin/bash
# Wait for the phone to reboot (boot_id change), then run usb.sh on it.
# Usage: usb-watch.sh <old-boot-id> <output-file>
R=.
S=(-o UserKnownHostsFile=$R/work/known_hosts -o ConnectTimeout=5 -o BatchMode=yes)
OLD=$1; OUT=$2
for i in $(seq 1 180); do
	B=$(ssh "${S[@]}" alarm@172.16.42.1 cat /proc/sys/kernel/random/boot_id 2>/dev/null)
	if [ -n "$B" ] && [ "$B" != "$OLD" ]; then
		echo "new boot $B after ~$((i*10))s"; sleep 20
		ssh "${S[@]}" alarm@172.16.42.1 sh -s < $R/scripts/diagnostics/usb.sh > "$OUT" 2>&1
		echo "checks written to $OUT"; exit 0
	fi
	sleep 10
done
echo "timeout waiting for reboot"; exit 1
