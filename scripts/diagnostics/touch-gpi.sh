# Run on the phone: touchscreen health (GPI ring errors, IRQ count, evdev)
echo "== uptime $(cut -d' ' -f1 /proc/uptime)"
grep -A5 TouchComm /proc/bus/input/devices | grep Handlers
grep synaptics-tcm /proc/interrupts | tr -s ' '
echo "gpi ring errors: $(journalctl -k -b --no-pager | grep -c 'not enough space in ring')"
echo "i2c failures:    $(journalctl -k -b --no-pager | grep -c 'GPI transfer failed')"
echo "DSI: $(cat /sys/class/drm/card*-DSI-1/status 2>&1)  login: $(systemctl is-active plasmalogin)"
journalctl -k -b --no-pager | grep -iE "synaptics|tcm|gpi|geni_i2c" | sed 's/^.*kernel: //' | tail -6
