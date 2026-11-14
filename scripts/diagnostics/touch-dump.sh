# Run on the phone: the touch report config and the first controller messages
echo "== uptime $(cut -d' ' -f1 /proc/uptime)"
grep synaptics-tcm /proc/interrupts | tr -s ' '
journalctl -k -b --no-pager | grep -E "R9Q-DEBUG|msg code" | sed 's/^.*kernel: //' | head -40
echo "codes seen:"
journalctl -k -b --no-pager | grep -o "msg code 0x[0-9a-f]* len [0-9]*" | sort | uniq -c
