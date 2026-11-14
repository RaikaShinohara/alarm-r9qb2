#!/bin/bash
# Wait until SSH to the phone works, then copy the test images to /tmp and
# the given extra files to the home directory, and print the hashes.
# Usage: copy-when-up.sh <imgdir> [file:remote-dir]...
R=.
S=(-o UserKnownHostsFile=$R/work/known_hosts -o ConnectTimeout=5 -o BatchMode=yes)
P=alarm@172.16.42.1
D=$1; shift
for i in $(seq 1 240); do
	ssh "${S[@]}" $P true 2>/dev/null && break
	sleep 5
done
ssh "${S[@]}" $P true 2>/dev/null || { echo "phone not reachable after 20 min"; exit 1; }
echo "phone up at $(date +%T), copying"
scp -q "${S[@]}" "$D/boot.img" "$D/vendor_boot.img" $P:/tmp/ || { echo "image copy failed"; exit 1; }
for a in "$@"; do
	scp -q "${S[@]}" "${a%%:*}" "$P:${a#*:}" || echo "copy failed: $a"
done
echo "local:"; sha256sum "$D/boot.img" "$D/vendor_boot.img" | cut -c1-16
echo "phone:"; ssh "${S[@]}" $P 'sha256sum /tmp/boot.img /tmp/vendor_boot.img | cut -c1-16; cat /proc/sys/kernel/random/boot_id'
echo COPY_DONE
