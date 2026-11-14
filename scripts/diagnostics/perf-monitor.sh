#!/bin/sh
# Record, every N seconds, what can make a game slow down over time: CPU/GPU
# temperatures, CPU frequency vs. the allowed maximum (thermal limits), GPU
# frequency and load (sum of drm-engine-gpu over all fdinfo), thermal cooling
# states, free memory, pressure (PSI) and the top CPU users. As the user, no
# root needed. Usage: perf-monitor.sh [seconds=900] [interval=5] > out.txt
D=${1:-900}
I=${2:-5}
gpu_ns() {
	cat /proc/[0-9]*/fdinfo/* 2>/dev/null | awk '/^drm-engine-gpu:/ { s += $2 } END { printf "%.0f", s }'
}
temp() { for z in /sys/class/thermal/thermal_zone*; do [ "$(cat "$z/type")" = "$1" ] && echo $(($(cat "$z/temp") / 1000)) && return; done; echo -; }
end=$(($(date +%s) + D))
prev_t=$(date +%s%N)
prev_g=$(gpu_ns)
echo "time cpu7C gpuC batC f0 f4 f4max f7 f7max gpuMHz gpu% memAvailMB psi_cpu10 cooling top3"
while [ "$(date +%s)" -lt "$end" ]; do
	sleep "$I"
	now=$(date +%s%N)
	g=$(gpu_ns)
	busy=$(awk -v a="$prev_g" -v b="$g" -v t0="$prev_t" -v t1="$now" 'BEGIN { d = (b - a) / (t1 - t0) * 100; if (d < 0) d = 0; printf "%.0f", d }')
	prev_g=$g
	prev_t=$now
	f() { cat /sys/devices/system/cpu/cpufreq/policy$1/$2 2>/dev/null | awk '{ printf "%d", $1 / 1000 }'; }
	cool=$(for c in /sys/class/thermal/cooling_device*; do s=$(cat "$c/cur_state" 2>/dev/null); [ "${s:-0}" != 0 ] && printf '%s:%s,' "$(cat "$c/type")" "$s"; done)
	top3=$(top -bn1 -o %CPU | awk 'NR > 7 && NR <= 10 { printf "%s:%s,", $NF, $9 }')
	echo "$(date +%T) $(temp cpu7-top-thermal) $(temp gpu-top-thermal) $(temp max170xx_battery)" \
		"$(f 0 scaling_cur_freq) $(f 4 scaling_cur_freq) $(f 4 scaling_max_freq) $(f 7 scaling_cur_freq) $(f 7 scaling_max_freq)" \
		"$(($(cat /sys/class/devfreq/3d00000.gpu/cur_freq) / 1000000)) $busy" \
		"$(awk '/MemAvailable/ { printf "%d", $2 / 1024 }' /proc/meminfo)" \
		"$(awk 'NR == 1 { sub("avg10=", "", $2); print $2 }' /proc/pressure/cpu)" "${cool:--}" "$top3"
done
