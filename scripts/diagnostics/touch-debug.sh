#!/bin/sh
# Run as root on the phone while touching the screen for ~15 s.
# Enables the touch driver's debug messages and records raw evdev events.
O=/tmp/touchdbg
mkdir -p $O
echo 'file synaptics_tcm_i2c.c +p' > /sys/kernel/debug/dynamic_debug/control
echo "touch the screen now (15 s)..."
timeout 15 evtest /dev/input/event0 > $O/evtest.txt 2>&1
echo 'file synaptics_tcm_i2c.c -p' > /sys/kernel/debug/dynamic_debug/control
dmesg | grep -E "synaptics|tcm" | tail -200 > $O/dmesg.txt
chmod -R a+r $O
echo "done: $(wc -l < $O/evtest.txt) evtest lines, $(grep -c slot $O/dmesg.txt) driver slot lines"
