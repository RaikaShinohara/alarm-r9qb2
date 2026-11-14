#!/bin/bash
# Wait for the phone to reboot (boot_id change), then run a checks script.
# Usage: boot-watch.sh <old-boot-id> <checks.sh> <output-file>
R=.
S=(-o UserKnownHostsFile=$R/work/known_hosts -o HostKeyAlias=172.16.42.1 -o ConnectTimeout=5 -o BatchMode=yes)
OLD=$1; CHECKS=$2; OUT=$3
for i in $(seq 1 240); do
	B=$(ssh "${S[@]}" alarm@172.16.42.1 cat /proc/sys/kernel/random/boot_id 2>/dev/null)
	if [ -n "$B" ] && [ "$B" != "$OLD" ]; then
		echo "new boot $B at $(date +%T)"; sleep 30
		ssh "${S[@]}" alarm@172.16.42.1 sh -s < "$CHECKS" > "$OUT" 2>&1
		echo "checks written to $OUT"; exit 0
	fi
	sleep 5
done
echo "timeout waiting for reboot"; exit 1
