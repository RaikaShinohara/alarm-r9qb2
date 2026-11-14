#!/bin/sh
# Audio checks on the phone (as the desktop user, no root needed for ALSA
# thanks to the seat ACL). Usage: sh audio-test.sh [play]
echo "== cards"; cat /proc/asound/cards; ls /dev/snd 2>&1 | tr '\n' ' '; echo
echo "== kernel"
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | \
	grep -iE 'cs35l41|snd|asoc|q6afe|q6asm|q6adm|q6core|apr|wm_adsp|cs_dsp|dsp1|sm8250|r9q-snd' | grep -v Handover | tail -40
C=$(awk '/Samsung-Galaxy-S21-FE|S21-FE|sm8350/ {print $1; exit}' /proc/asound/cards)
[ -n "$C" ] || { echo "no sound card"; exit 0; }
echo "== card $C controls"
amixer -c "$C" scontrols | head -60
if [ "$1" = play ]; then
	echo "== routing + speaker protection"
	amixer -c "$C" cset name='PRI_MI2S_RX Audio Mixer MultiMedia1' 1
	amixer -c "$C" cset name='Top DSP1 Preload Switch' 1
	amixer -c "$C" cset name='Bottom DSP1 Preload Switch' 1
	amixer -c "$C" cset name='Top PCM Source' DSP
	amixer -c "$C" cset name='Bottom PCM Source' DSP
	sleep 3
	journalctl -k -b --no-pager -o short-monotonic | grep -iE 'cs35l41|dsp1|wmfw|firmware' | tail -12
	echo "== playing: 1.5 s left (top), 0.5 s silence, 1.5 s right (bottom)"
	aplay -D "hw:$C,0" "$HOME/test-lr.wav" 2>&1
	journalctl -k -b --no-pager -o short-monotonic | grep -iE 'cs35l41|q6|afe|error' | tail -12
fi
