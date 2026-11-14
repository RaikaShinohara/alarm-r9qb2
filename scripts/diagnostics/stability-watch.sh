#!/bin/bash
# Wait for the phone (USB or Wi-Fi), run a checks script once, then poll its
# uptime/boot_id every 20 s for N minutes to catch hangs or reboots.
# Usage: stability-watch.sh <checks.sh> <out> [minutes] [wifi-ip]
R=.
CHECKS=$1; OUT=$2; MIN=${3:-10}; WIFI=${4:?phone Wi-Fi IP}
S=(-o UserKnownHostsFile=${KH:-$R/work/known_hosts} -o HostKeyAlias=172.16.42.1 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes)
pick() { for ip in 172.16.42.1 "$WIFI"; do ssh "${S[@]}" alarm@$ip true 2>/dev/null && { echo $ip; return; }; done; }
for i in $(seq 1 60); do IP=$(pick); [ -n "$IP" ] && break; sleep 5; done
[ -n "$IP" ] || { echo "phone not reachable"; exit 1; }
echo "up via $IP at $(date +%T)"; sleep 30
ssh "${S[@]}" alarm@$IP sh -s < "$CHECKS" > "$OUT" 2>&1
BOOT=$(ssh "${S[@]}" alarm@$IP cat /proc/sys/kernel/random/boot_id)
end=$(( $(date +%s) + MIN * 60 )); last=""
while [ "$(date +%s)" -lt "$end" ]; do
	IP=$(pick)
	if [ -z "$IP" ]; then echo "$(date +%T) UNREACHABLE (last uptime ${last:-?})"; sleep 20; continue; fi
	read -r up b < <(ssh "${S[@]}" alarm@$IP 'echo $(cut -d" " -f1 /proc/uptime) $(cat /proc/sys/kernel/random/boot_id)' 2>/dev/null)
	[ -n "$b" ] && [ "$b" != "$BOOT" ] && { echo "$(date +%T) REBOOTED (new uptime $up, previous last $last)"; exit 3; }
	last=$up; sleep 20
done
echo "stable for $MIN min, uptime $last"
