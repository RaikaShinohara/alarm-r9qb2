#!/bin/sh
# After a test boot: restart the freeze recorder and list the input devices,
# the virtual keyboard process and the audio state.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
uname -v
systemctl --user stop freezerec 2>/dev/null
rm -f "$HOME/freeze/journal.txt" "$HOME/freeze/stats.txt"
systemd-run --user --unit=freezerec --collect sh "$HOME/freeze-rec.sh"
echo "== input"; for e in /sys/class/input/event*; do echo "$e $(cat $e/device/name)"; done
echo "== virtual keyboard"; ps -ef | grep -i "plasma-keyboard" | grep -v grep
echo "== audio"; pactl list short sinks 2>&1
journalctl -k -b --no-pager | grep -iE "mailbox|CSPL not|calibration" | tail -4
