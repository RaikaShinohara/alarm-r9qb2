#!/bin/sh
# Reproduce the Bluetooth failure under control (root): rebind hci_uart_qca
# with bootmac held back, check the controller, then set the address the way
# bootmac does while btmon records the HCI traffic. Output: ~/bt-diag2.txt
OUT=/home/alarm/bt-diag2.txt
ADDR=${1:-02:00:00:12:34:56}  # any locally administered address
hci() { ls /sys/class/bluetooth/ 2>/dev/null | grep -m1 '^hci[0-9]*$'; }
{
	echo "== before"; hciconfig -a 2>&1 | head -6
	systemctl mask --runtime bootmac@bluetooth.service
	apk add -q bluez-btmon >/dev/null 2>&1; which btmon
	btmon -w /tmp/bt.snoop >/dev/null 2>&1 &
	BM=$!
	sleep 1
	echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind; sleep 2
	echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind; sleep 8
	H=$(hci); echo "== after rebind: $H"
	btmgmt info 2>&1 | head -6; hciconfig -a "$H" 2>&1 | head -5
	echo "== power off / public-addr / power on (like bootmac)"
	yes | btmgmt -i "$H" power off 2>&1 | tail -1
	yes | btmgmt -i "$H" public-addr $ADDR 2>&1 | tail -1
	sleep 1
	yes | btmgmt -i "$H" power on 2>&1 | tail -1
	sleep 8
	btmgmt info 2>&1 | head -6; hciconfig -a "$H" 2>&1 | head -5
	kill $BM; sleep 1
	echo "== btmon"; btmon -r /tmp/bt.snoop 2>&1 | tail -120
	echo "== kernel"; dmesg | grep -iE "hci[0-9]|qca|bluetooth: " | tail -20
	systemctl unmask --runtime bootmac@bluetooth.service
} > "$OUT" 2>&1
chown alarm:alarm "$OUT"
