#!/bin/sh
# After a boot: did hexagonrpcd-sdsp and iio-sensor-proxy come up on their
# own, and what do the sensors report.
uname -v; cut -d' ' -f1 /proc/uptime
systemctl is-active hexagonrpcd-sdsp iio-sensor-proxy | tr '\n' ' '; echo
journalctl -b --no-pager -o short-monotonic -u hexagonrpcd-sdsp -u iio-sensor-proxy | grep -E "Start|Deactivated|No sensors|Exiting|Failed|skipped" | head -12
timeout 10 monitor-sensor 2>&1 | head -25
