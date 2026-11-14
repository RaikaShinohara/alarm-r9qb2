#!/bin/bash
# Wait until the modem remoteproc leaves "offline" (started by hand on the
# phone), then report its state and kernel log for a minute.
R=.
SSH="ssh -o BatchMode=yes -o UserKnownHostsFile=$R/work/known_hosts -o ConnectTimeout=3 alarm@172.16.42.1"
for i in $(seq 1 720); do
	s=$(timeout 8 $SSH 'cat /sys/class/remoteproc/remoteproc1/state' 2>/dev/null)
	[ -n "$s" ] && [ "$s" != offline ] && break
	j=$(timeout 8 $SSH 'journalctl -k -b --no-pager | grep -c "powering up modem"' 2>/dev/null)
	[ "${j:-0}" -ge 2 ] && break
	sleep 5
done
echo "modem state change detected: '$s' $(date +%T)"
for t in 5 30 60; do
	sleep $t
	echo "===== +${t}s"
	timeout 30 $SSH 'cat /sys/class/remoteproc/remoteproc1/state; ls /sys/bus/rpmsg/devices/ | grep -i 4080000 | tr "\n" " "; echo
journalctl -k -b --no-pager -o short-monotonic | grep -iE "remoteproc1|modem|mpss|4080000|rmtfs|sysmon|qrtr|pdr|crash|fatal|ssr" | sed "s/samsung-r9q kernel: //" | tail -25' 2>&1
done
echo "WATCH_MODEM_DONE"
