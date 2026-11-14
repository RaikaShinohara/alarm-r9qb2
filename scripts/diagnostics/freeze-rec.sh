#!/bin/sh
# Freeze recorder (runs on the phone as a user unit): follows the journal and
# every 2 s logs load, memory, the busiest processes, GPU frequency and the
# hottest thermal zones, syncing to disk so a hard freeze leaves the last
# seconds behind. Output: ~/freeze/{journal,stats}.txt
D=$HOME/freeze; mkdir -p "$D"
journalctl -f -o short-monotonic --no-hostname > "$D/journal.txt" 2>&1 &
while :; do
	{
		echo "=== $(cut -d' ' -f1 /proc/uptime) load $(cut -d' ' -f1-3 /proc/loadavg)"
		grep -E "MemAvailable|SwapFree|Dirty" /proc/meminfo | tr -s ' ' | tr '\n' ' '; echo
		echo "gpu $(cat /sys/class/devfreq/3d00000.gpu/cur_freq 2>/dev/null) cpu $(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq | tr '\n' ' ')"
		for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/temp) $(cat $z/type)"; done | sort -rn | head -3 | tr '\n' ' '; echo
		top -b -n1 | sed -n '5,12p'
	} >> "$D/stats.txt"
	sync
	sleep 2
done
