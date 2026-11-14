#!/bin/sh
# Run as root on the phone, once. Leaves btmon recording to ~alarm/btmon.txt
# as a transient unit (stop: systemctl stop btmon-cap), re-runs the Bluetooth
# setup with the firmware installed now (to log the LE features it reports),
# then switches to the chip's ROM firmware (no patch, no NVM), re-runs the
# setup again and restores the public address with bootmac.
H=/home/alarm
Q=/usr/lib/firmware/qca
D=/sys/bus/serial/drivers/hci_uart_qca
rebind() {
	echo serial0-0 > $D/unbind; sleep 1; echo serial0-0 > $D/bind; sleep 8
	systemctl restart bootmac@bluetooth; sleep 2
}
systemctl stop btmon-cap 2>/dev/null
rm -f $H/btmon.txt
systemd-run --unit=btmon-cap --collect sh -c "exec btmon > $H/btmon.txt 2>&1"
sleep 2
echo "== setup with the installed firmware ($(ls $Q | tr '\n' ' '))"
rebind
mkdir -p $H/qca-lfw
mv $Q/hpbtfw21.tlv $Q/hpnv21.bin $Q/hpnv21g.bin $H/qca-lfw/ 2>/dev/null
echo "== setup with the ROM firmware (qca now: $(ls $Q | tr '\n' ' '))"
rebind
chmod 644 $H/btmon.txt
bluetoothctl show | grep -E "Controller|Powered"
echo "btmon keeps recording to $H/btmon.txt"
