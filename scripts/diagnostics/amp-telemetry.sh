#!/bin/sh
# Play a WAV through the speakers and read the CS35L41 protection firmware
# (CSPL) telemetry while it plays: peak voltage/current, coil temperature and
# excursion log, plus the amplifier gain controls. No root needed.
# Usage: amp-telemetry.sh [file.wav] [seconds-into-playback]
WAV=${1:-$HOME/tone1k-6db.wav}
AT=${2:-2}
C="amixer -c 0"
ctl() { $C cget name="$1" 2>/dev/null | sed -n 's/.*: values=//p' | tail -1; }
for s in Top Bottom; do
	echo "$s: Analog PCM Volume=$(ctl "$s Analog PCM Volume") Digital PCM Volume=$(ctl "$s Digital PCM Volume") DSP RX2=$(ctl "$s DSP RX2 Source")"
done
paplay "$WAV" &
P=$!
sleep "$AT"
for s in Top Bottom; do
	for c in CSPL_STATE CSPL_VOLTAGE_PEAK CSPL_CURRENT_PEAK CSPL_TEMPERATURE CSPL_SURFACE_TEMP BDLOG_MAX_EXC BDLOG_MAX_TEMP BDLOG_OVER_EXC_COUNT BDLOG_ABNORMAL_MUTE; do
		echo "$s $c: $(ctl "$s DSP1 Protection cd $c")"
	done
done
wait $P
