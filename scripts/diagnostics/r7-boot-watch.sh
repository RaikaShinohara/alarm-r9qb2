#!/bin/bash
# Watch the first boots of a fresh install: when SSH answers, run the
# post-install checks; if the initramfs dropped to its debug shell instead,
# fetch its log over telnet. Usage: r7-boot-watch.sh <outdir> [minutes]
R=.
OUT=$1; MIN=${2:-15}
mkdir -p "$OUT"
# Fresh install = new host key: keep it apart from the old known_hosts
S=(-o UserKnownHostsFile=$R/work/known_hosts -o StrictHostKeyChecking=accept-new
   -o HostKeyAlias=172.16.42.1 -o ConnectTimeout=5 -o BatchMode=yes)
end=$(( $(date +%s) + MIN * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
	if ip -br addr 2>/dev/null | grep -q "172.16.42.2"; then
		if ssh "${S[@]}" alarm@172.16.42.1 true 2>/dev/null; then
			echo "ssh up $(date +%T)"; sleep 40
			ssh "${S[@]}" alarm@172.16.42.1 sh -s < "$R/scripts/diagnostics/r7-post-install.sh" > "$OUT/post-install.txt" 2>&1
			echo "checks written to $OUT/post-install.txt"; exit 0
		fi
		if nc -z -w 3 172.16.42.1 23 2>/dev/null; then
			echo "initramfs debug shell $(date +%T)"
			printf 'cat /pmOS_init.log\nexit\n' | nc -w 8 172.16.42.1 23 > "$OUT/pmOS_init.log" 2>&1
			echo "initramfs log written to $OUT/pmOS_init.log"; exit 2
		fi
	fi
	sleep 5
done
echo "timeout: no ssh/telnet after $MIN min"; exit 1
