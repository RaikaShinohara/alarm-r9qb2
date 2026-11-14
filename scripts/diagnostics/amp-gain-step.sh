#!/bin/sh
# Set the CS35L41 analog gain (Analog PCM Volume: 0..20 = 0.5..20.5 dB) on both
# speakers and watch the protection firmware (CSPL) while something plays.
# Usage: amp-gain-step.sh <0-20 | keep> [samples] [interval-s]
G=$1
N=${2:-5}
T=${3:-4}
C="amixer -c 0"
amixer -c 0 controls | sed -n "s/.*name='\(.*\)'$/\1/p" | grep -E "^(Top|Bottom) DSP1 Protection" > /tmp/amp-ctls
# Long names get cut at the front by ALSA, so match on the end of the name
name() { grep "^$1 " /tmp/amp-ctls | grep "${2#????}$" | head -1; }
val() { $C cget name="$1" 2>/dev/null | sed -n 's/.*: values=//p' | tail -1; }
# 4 big-endian bytes "0x00,0x06,0x18,0x6c" in Q14 (temperature in degrees C)
q14() {
	[ -n "$1" ] || { echo "?"; return; }
	set -- $(echo "$1" | tr ',' ' ')
	v=$(( ($2 << 16) + ($3 << 8) + $4 ))
	printf '%d.%02d' $((v / 16384)) $(( (v % 16384) * 100 / 16384 ))
}
if [ "$G" != keep ]; then
	for s in Top Bottom; do $C cset name="$s Analog PCM Volume" "$G" >/dev/null || exit 1; done
fi
echo "gain: Top=$(val 'Top Analog PCM Volume') Bottom=$(val 'Bottom Analog PCM Volume') (dB = value + 0.5)"
echo "playing: $(pactl list sink-inputs | sed -n 's/.*media.name = //p' | head -1)"
i=0
while [ $i -lt "$N" ]; do
	sleep "$T"
	for s in Top Bottom; do
		printf '%s %-6s' "$i" "$s"
		printf ' temp=%sC' "$(q14 "$(val "$(name $s CSPL_TEMPERATURE)")")"
		printf ' oversight=%s' "$(val "$(name $s CSPL_OVERSIGHT_GAIN)")"
		printf ' max_exc=%s' "$(val "$(name $s BDLOG_MAX_EXC)")"
		printf ' over_exc=%s' "$(val "$(name $s BDLOG_OVER_EXC_COUNT)")"
		printf ' over_temp=%s' "$(val "$(name $s BDLOG_OVER_TEMP_COUNT)")"
		printf ' mute=%s\n' "$(val "$(name $s BDLOG_ABNORMAL_MUTE)")"
	done
	i=$((i + 1))
done
