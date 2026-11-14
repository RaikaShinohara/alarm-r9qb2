#!/bin/bash
# Wait for the USB link to the phone to go away (cable unplugged for an OTG
# test) and come back, then fetch the logger output and the kernel log.
# Usage: usb-replug-watch.sh <output-file>
R=.
S=(-o UserKnownHostsFile=$R/work/known_hosts -o ConnectTimeout=4 -o BatchMode=yes)
OUT=$1
up() { ping -c1 -W2 172.16.42.1 >/dev/null 2>&1; }
for i in $(seq 1 900); do up || break; sleep 2; done
echo "link down at $(date +%T)"
for i in $(seq 1 1800); do up && break; sleep 2; done
up || { echo "link did not come back"; exit 1; }
echo "link back at $(date +%T)"; sleep 5
ssh "${S[@]}" alarm@172.16.42.1 'cat /proc/sys/kernel/random/boot_id; echo "=== state.log"; cat usblog/state.log; echo "=== kernel"; journalctl -k -b --no-pager -o short-monotonic | grep -iE "max77705|typec|dwc3|usb |usb-|xhci|hid|input:|scsi|sd |otg|vbus|role|charger|pd " | tail -150' > "$OUT" 2>&1
echo "written $OUT"
