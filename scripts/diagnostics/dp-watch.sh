#!/bin/bash
# DP test watcher: wait for the reboot (boot_id change), run dp.sh, start the
# state logger on the phone as a user unit, then wait for the USB link to go
# (cable moved to the HDMI adapter) and come back, and fetch the results.
# Usage: dp-watch.sh <old-boot-id> <outdir>
R=.
S=(-o UserKnownHostsFile=$R/work/known_hosts -o ConnectTimeout=4 -o BatchMode=yes)
P=alarm@172.16.42.1
OLD=$1; OUT=$2; mkdir -p "$OUT"
up() { ping -c1 -W2 172.16.42.1 >/dev/null 2>&1; }
for i in $(seq 1 240); do
	B=$(ssh "${S[@]}" $P cat /proc/sys/kernel/random/boot_id 2>/dev/null)
	[ -n "$B" ] && [ "$B" != "$OLD" ] && break
	B=""; sleep 5
done
[ -n "$B" ] || { echo "no new boot after 20 min"; exit 1; }
echo "new boot $B at $(date +%T)"; sleep 30
ssh "${S[@]}" $P sh -s < $R/scripts/diagnostics/dp.sh > "$OUT/dp-boot.txt" 2>&1
ssh "${S[@]}" $P 'rm -f usblog/state.log; XDG_RUNTIME_DIR=/run/user/$(id -u) systemd-run --user --unit=usblogger --collect $HOME/usb-logger.sh' > "$OUT/logger-start.txt" 2>&1
echo "boot checks done, logger started at $(date +%T)"
for i in $(seq 1 1800); do up || break; sleep 2; done
echo "link down at $(date +%T)"
for i in $(seq 1 1800); do up && break; sleep 2; done
up || { echo "link did not come back"; exit 1; }
echo "link back at $(date +%T)"; sleep 8
ssh "${S[@]}" $P 'cat usblog/state.log' > "$OUT/state.log" 2>&1
ssh "${S[@]}" $P sh -s < $R/scripts/diagnostics/dp.sh > "$OUT/dp-after.txt" 2>&1
echo "results in $OUT"
