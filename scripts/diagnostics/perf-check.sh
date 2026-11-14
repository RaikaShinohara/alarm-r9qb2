#!/bin/sh
# After a boot with the CPU performance DT (epss_l3, OPP bandwidth votes,
# capacities): did cpufreq/L3 probe, what the scheduler sees, cache/RAM speed.
uname -v
echo "== kernel log"
journalctl -k -b --no-pager -o short-monotonic | grep -iE "epss|osm.l3|cpufreq|opp|energy|EAS|sched_energy|failed to update OPP|Invalid opp" | sed 's/samsung-r9q kernel: //' | head -20
echo "== capacity / policies"
for c in 0 1 4 7; do printf 'cpu%s capacity=%s\n' $c "$(cat /sys/devices/system/cpu/cpu$c/cpu_capacity)"; done
for p in 0 4 7; do
	d=/sys/devices/system/cpu/cpufreq/policy$p
	echo "policy$p $(cat $d/scaling_driver) $(cat $d/scaling_governor) $(cat $d/cpuinfo_min_freq)-$(cat $d/cpuinfo_max_freq) n=$(wc -w < $d/scaling_available_frequencies)"
done
cat /proc/sys/kernel/sched_energy_aware 2>/dev/null | sed 's/^/sched_energy_aware=/'
echo "== interconnect sync_state"
journalctl -k -b --no-pager | grep -c "sync_state() pending" | sed 's/^/pending lines: /'
echo "== memory bandwidth"
python3 "$HOME/mem-bw.py" 7 4 0
