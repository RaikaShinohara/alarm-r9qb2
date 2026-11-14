#!/bin/sh
# After a reboot with the sensor and Bluetooth fixes: did both come up by
# themselves, and how long the Plasma splash took.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
uname -v; cut -d' ' -f1 /proc/uptime
echo "== sensors"; systemctl is-active hexagonrpcd-sdsp iio-sensor-proxy | paste -sd' '
journalctl -b --no-pager -o short-monotonic -u hexagonrpcd-sdsp -u iio-sensor-proxy | grep -E "Started|Deactivated|No sensors|skipped" | head -6
timeout 8 monitor-sensor 2>&1 | head -12
echo "== bluetooth"; journalctl -b --no-pager -o short-monotonic -u 'bootmac@bluetooth' | tail -4
bluetoothctl show 2>&1 | grep -E "Controller|Powered" | head -2
rfkill list bluetooth | grep -E "Soft|Hard"
echo "== login"; journalctl -b --no-pager -o short-monotonic | grep -E "plasma-ksplash.service: Consumed" | head -1
systemctl is-system-running; systemctl --failed --no-legend --plain
apk info -v 2>/dev/null | grep -E "^(linux|device)-samsung-r9q"
