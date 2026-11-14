#!/bin/sh
# Acoustic loopback: record two DMICs while a 1 kHz tone plays first on the
# top speaker, then on the bottom one; print the 1 kHz level per mic for
# each half. Tells whether the mics work and which one sits at which end.
# Usage: mic-loopback.sh [dmicA dmicB] [VA_DEC volume dB]
A=${1:-DMIC1}
B=${2:-DMIC3}
G=${3:-0}
C="amixer -c 0 -q cset"
DEV=$(sed -n 's/^00-\([0-9][0-9]\): MultiMedia3.*/\1/p' /proc/asound/pcm | sed 's/^0//')
$C name='MultiMedia3 Mixer VA_CODEC_DMA_TX_0' 1
$C name='VA DEC0 MUX' VA_DMIC
$C name='VA DEC1 MUX' VA_DMIC
$C name='VA DMIC MUX0' "$A"
$C name='VA DMIC MUX1' "$B"
$C name='VA_DEC0 Volume' "$G"
$C name='VA_DEC1 Volume' "$G"
$C name='VA_AIF1_CAP Mixer DEC0' 1
$C name='VA_AIF1_CAP Mixer DEC1' 1
# PLAY=alsa: bypass PulseAudio (suspend its sink, play straight to hw:0,0)
if [ "${PLAY:-pulse}" = alsa ]; then
	pactl suspend-sink @DEFAULT_SINK@ 1
	PL="aplay -q -D hw:0,0"
else
	PL=paplay
fi
arecord -q -D "hw:0,$DEV" -f S16_LE -r 48000 -c 2 -d 9 "$HOME/mic-loop.wav" &
P=$!
sleep 1.5
$PL "$HOME/tone-top.wav"
sleep 0.5
$PL "$HOME/tone-bottom.wav"
wait $P
[ "${PLAY:-pulse}" = alsa ] && pactl suspend-sink @DEFAULT_SINK@ 0
$C name='VA_AIF1_CAP Mixer DEC0' 0
$C name='VA_AIF1_CAP Mixer DEC1' 0
$C name='MultiMedia3 Mixer VA_CODEC_DMA_TX_0' 0
python3 - "$HOME/mic-loop.wav" "$A" "$B" "$G" <<'EOF'
import sys, wave, struct, math
w = wave.open(sys.argv[1]); n = w.getnframes()
a = struct.unpack('<%dh' % (n * 2), w.readframes(n))
def tone_db(s):  # Goertzel at 1 kHz, as dBFS of a sine
    k = 2 * math.cos(2 * math.pi * 1000 / 48000); p1 = p2 = 0.0
    for x in s:
        p0 = x + k * p1 - p2; p2, p1 = p1, p0
    pw = p1 * p1 + p2 * p2 - k * p1 * p2
    amp = 2 * math.sqrt(max(pw, 0)) / len(s)
    return 20 * math.log10(amp / 32768) if amp > 0 else -999
def rms_db(s):
    m = sum(s) / len(s); r = math.sqrt(sum((x - m) ** 2 for x in s) / len(s))
    return 20 * math.log10(r / 32768) if r > 0 else -999
r = 48000
win = {'quiet': (0.6, 1.4), 'top spk': (2.0, 4.0), 'bottom spk': (5.5, 7.5)}
print('VA_DEC gain %s dB' % sys.argv[4])
for c, name in ((0, sys.argv[2]), (1, sys.argv[3])):
    s = a[c::2]
    out = []
    for label, (t0, t1) in win.items():
        seg = s[int(t0 * r):int(t1 * r)]
        out.append('%s: 1k %.1f / rms %.1f' % (label, tone_db(seg), rms_db(seg)))
    print('%-6s %s' % (name, ' | '.join(out)))
EOF
