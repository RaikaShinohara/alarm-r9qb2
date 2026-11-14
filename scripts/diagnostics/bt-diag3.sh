#!/bin/sh
# Bluetooth power cycle test (root): rebind with bootmac held back, then
# up / down / up with hciconfig (prints the errno), with the driver's
# dynamic debug in dmesg. Output: ~/bt-diag3.txt
OUT=/home/alarm/bt-diag3.txt
hci() { ls /sys/class/bluetooth/ 2>/dev/null | grep -m1 '^hci[0-9]*$'; }
{
	mount -t debugfs none /sys/kernel/debug 2>/dev/null
	for m in hci_uart btqca bluetooth; do
		echo "module $m +p" > /sys/kernel/debug/dynamic_debug/control 2>&1
	done
	systemctl mask --runtime bootmac@bluetooth.service
	systemctl stop bluetooth
	dmesg -C
	echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind; sleep 2
	echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind; sleep 8
	H=$(hci); echo "== after rebind: $H"; hciconfig "$H" | head -3
	echo "== up #1"; hciconfig "$H" up; echo "rc=$?"; sleep 2; hciconfig "$H" | sed -n 3p
	echo "== down"; hciconfig "$H" down; echo "rc=$?"; sleep 2
	echo "== up #2"; hciconfig "$H" up; echo "rc=$?"; sleep 2; hciconfig "$H" | sed -n 3p
	echo "== dmesg"; dmesg | grep -vE "Unhandled context|FSR |FSYNR0" | tail -60
	for m in hci_uart btqca bluetooth; do
		echo "module $m -p" > /sys/kernel/debug/dynamic_debug/control 2>&1
	done
	systemctl unmask --runtime bootmac@bluetooth.service
	systemctl start bluetooth
} > "$OUT" 2>&1
chown alarm:alarm "$OUT"
