#!/bin/sh
# CPU frequency scaling check (no root): idle frequencies, one busy core per
# cluster (frequency + real work rate), then all 8 cores (sustained frequency
# and temperatures), then idle again.
P=/sys/devices/system/cpu/cpufreq
f() { echo $(( $(cat $P/policy$1/scaling_cur_freq) / 1000 )); }
freqs() { printf 'silver=%4s gold=%4s prime=%4s MHz' "$(f 0)" "$(f 4)" "$(f 7)"; }
temps() {
	for z in cpu0 cpu4-top cpu7-top cluster0 cluster1 gpu-top; do
		for d in /sys/class/thermal/thermal_zone*; do
			[ "$(cat $d/type)" = "$z-thermal" ] && printf ' %s=%sC' "$z" $(( $(cat $d/temp) / 1000 ))
		done
	done
}
throttle() {
	for c in /sys/class/thermal/cooling_device*; do
		case $(cat $c/type) in cpufreq-*|devfreq-*) printf ' %s=%s' "$(cat $c/type)" "$(cat $c/cur_state)";; esac
	done
}
BUSY='import os,sys,time
cpu=int(sys.argv[1]); dur=float(sys.argv[2])
os.sched_setaffinity(0,{cpu})
n=0; t0=time.time(); end=t0+dur
while time.time()<end:
    for _ in range(20000): pass
    n+=1
print("cpu%d: %.1f M iter/s" % (cpu, n*20000/(time.time()-t0)/1e6))'

echo "== idle (10 samples, 0.5 s apart)"
i=0; while [ $i -lt 10 ]; do echo "  $(freqs)"; sleep 0.5; i=$((i+1)); done
echo "  temps:$(temps)"

for c in 0 4 7; do
	echo "== one busy thread on cpu$c (6 s)"
	python3 -c "$BUSY" $c 6 &
	B=$!
	sleep 1; s1=$(freqs); sleep 2; s2=$(freqs); sleep 2; s3=$(freqs)
	wait $B
	echo "  1s: $s1"; echo "  3s: $s2"; echo "  5s: $s3"
done

echo "== all 8 cores busy (20 s)"
for c in 0 1 2 3 4 5 6 7; do python3 -c "$BUSY" $c 20 & done
i=0; while [ $i -lt 5 ]; do sleep 4; echo "  $(( (i+1)*4 ))s: $(freqs)$(temps)$(throttle)"; i=$((i+1)); done
wait

echo "== idle again"
sleep 2
i=0; while [ $i -lt 6 ]; do echo "  $(freqs)"; sleep 0.5; i=$((i+1)); done
echo "  temps:$(temps)"
