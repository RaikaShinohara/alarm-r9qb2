# Run on the phone (normal user): touchscreen and panel refresh rate
echo "== uptime $(cut -d' ' -f1 /proc/uptime)"
echo "== panel refresh_rate param: $(cat /sys/module/panel_samsung_ea8082/parameters/refresh_rate 2>&1)"
echo "== DSI: $(cat /sys/class/drm/card*-DSI-1/status) $(cat /sys/class/drm/card*-DSI-1/modes | tr '\n' ' ')"
echo "== input devices"
grep -A5 -i "synaptics\|touch" /proc/bus/input/devices | grep -E "^N:|^H:|^B: ABS"
echo "== touch irq"
grep -iE "synaptics|tcm" /proc/interrupts | tr -s ' '
echo "== display irq rate (mdss) over 2 s"
a=$(grep -E "mdss|msm" /proc/interrupts | head -1 | tr -s ' ' | cut -d' ' -f3-10)
sleep 2
b=$(grep -E "mdss|msm" /proc/interrupts | head -1 | tr -s ' ' | cut -d' ' -f3-10)
echo "before: $a"; echo "after:  $b"
echo "== kernel log"
journalctl -k -b --no-pager -o short-monotonic | grep -iE "synaptics|tcm|touch|990000|i2c4|tsp|ea8082|panel|dsi|dpu.*err" | sed "s/samsung-r9q kernel: //" | grep -v "Fixed dependency" | tail -40
