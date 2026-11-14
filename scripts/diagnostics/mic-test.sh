#!/bin/sh
# Record from the DMICs through the LPASS VA macro (VA_CODEC_DMA_TX_0 ->
# MultiMedia3) and print peak/RMS per channel. No root needed.
# Usage: mic-test.sh [seconds] [dmicA dmicB]   (default: 4 DMIC1 DMIC3)
S=${1:-4}
A=${2:-DMIC1}
B=${3:-DMIC3}
C="amixer -c 0 -q cset"
OUT=${OUT:-$HOME/mic-$A-$B.wav}
echo "== card / pcm"
grep -E "MultiMedia3|VA" /proc/asound/pcm
DEV=$(sed -n 's/^00-\([0-9][0-9]\): MultiMedia3.*/\1/p' /proc/asound/pcm | sed 's/^0//')
[ -n "$DEV" ] || { echo "no MultiMedia3 PCM"; exit 1; }
echo "MultiMedia3 = hw:0,$DEV"
$C name='MultiMedia3 Mixer VA_CODEC_DMA_TX_0' 1
$C name='VA DEC0 MUX' VA_DMIC
$C name='VA DEC1 MUX' VA_DMIC
$C name='VA DMIC MUX0' "$A"
$C name='VA DMIC MUX1' "$B"
$C name='VA_AIF1_CAP Mixer DEC0' 1
$C name='VA_AIF1_CAP Mixer DEC1' 1
echo "== recording $S s: left=$A right=$B -> $OUT"
arecord -D "hw:0,$DEV" -f S16_LE -r 48000 -c 2 -d "$S" "$OUT" 2>&1 | tail -2
$C name='VA_AIF1_CAP Mixer DEC0' 0
$C name='VA_AIF1_CAP Mixer DEC1' 0
$C name='MultiMedia3 Mixer VA_CODEC_DMA_TX_0' 0
python3 - "$OUT" <<'EOF'
import sys, wave, struct, math
w = wave.open(sys.argv[1])
n, ch = w.getnframes(), w.getnchannels()
a = struct.unpack('<%dh' % (n * ch), w.readframes(n))
skip = 48000 // 2  # first 0.5 s: decimator HPF/unmute settling
for c in range(ch):
    s = a[c + skip * ch::ch]
    if not s:
        print('ch%d: empty' % c); continue
    m = sum(s) / len(s)
    pk = max(abs(x) for x in s)
    rms = math.sqrt(sum((x - m) ** 2 for x in s) / len(s))
    db = lambda v: 20 * math.log10(v / 32768) if v > 0 else -999
    print('ch%d: peak %.1f dBFS  rms %.1f dBFS  dc %d  distinct %d' % (c, db(pk), db(rms), m, len(set(s[:20000]))))
EOF
journalctl -k -b --no-pager -o short-monotonic | grep -iE "va.macro|va_macro|lpass|lpi|q6afe|VA_CODEC|codec_dma" | tail -8
