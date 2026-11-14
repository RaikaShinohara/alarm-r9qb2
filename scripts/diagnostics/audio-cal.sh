#!/bin/sh
# Write the factory speaker calibration (sec_efs/cirrus) into the CS35L41
# protection firmware, as Samsung's cirrus_cal_apply() does after the DSP
# boots: VIMON (VSC, ISC, state 2 = success) and CAL_R/AMBIENT/STATUS/CHECKSUM.
# The DSP must be running (preload on, after one stream). Usage: sh audio-cal.sh
C=0
w() { amixer -c $C -q cset name="$1" "$2" || echo "FAILED: $1"; }
cal() { # prefix rdc_bytes checksum_bytes vsc isc
	p="$1 DSP1 Protection"
	w "$p 400a4 VSC" "$4"
	w "$p 400a4 ISC" "$5"
	w "$p 400a4 VIMON_CAL" 0x00,0x00,0x00,0x02
	w "$p cd CAL_STATUS" 0x00,0x00,0x00,0x01
	w "$p cd CAL_R" "$2"
	w "$p cd CAL_AMBIENT" 0x00,0x00,0x00,0x24
	w "$p cd CAL_CHECKSUM" "$3"
	for c in "cd CAL_STATUS" "cd CAL_R" "cd CAL_CHECKSUM" "400a4 VIMON_CAL"; do
		printf "%s %-18s" "$1" "$c"; amixer -c $C cget name="$p $c" | grep ": values"
	done
}
cal Top 0x00,0x00,0x20,0xe4 0x00,0x00,0x20,0xe5 0x00,0xff,0xe5,0x73 0x00,0xff,0xf4,0xae
cal Bottom 0x00,0x00,0x21,0x74 0x00,0x00,0x21,0x75 0x00,0xff,0xe3,0x4b 0x00,0xff,0xfa,0x1e
