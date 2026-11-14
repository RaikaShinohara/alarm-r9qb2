#!/bin/sh
# First look at a fresh r7 install: versions, failed units, and the features
# added since r6 (USB-C, BT, vibration, speakers, mics, EAS, L3, login).
echo "== versions"; uname -rv
apk info -v 2>/dev/null | grep -E "^(linux|device|firmware)-samsung-r9q"
echo "== boot"; systemctl is-system-running; systemctl --failed --no-legend --plain | head
journalctl -b --no-pager -o short-monotonic | grep -E "plasma-ksplash.service: Consumed|Reached target graphical" | head -3
echo "== modules"; lsmod | grep -cE "^"; lsmod | grep -E "^(msm|panel_samsung_ea8082|synaptics_tcm_i2c|snd_soc_sm8250|snd_soc_cs35l41_i2c|snd_soc_lpass_va_macro|hci_uart|max77693_haptic|pwm_clk|max77705|gpio_sbu_mux|qcom_pon)\b" | awk '{print $1}' | tr '\n' ' '; echo
echo "== cpu"; for c in 0 4 7; do printf 'cpu%s=%s ' $c "$(cat /sys/devices/system/cpu/cpu$c/cpu_capacity)"; done; echo "eas=$(cat /proc/sys/kernel/sched_energy_aware 2>/dev/null)"
ls -la /sys/bus/platform/devices/18590000.interconnect/driver 2>&1 | sed 's/.*-> //'
echo "== sound"; cat /proc/asound/cards; grep -E "MultiMedia" /proc/asound/pcm
pactl list short sinks 2>/dev/null; pactl list short sources 2>/dev/null | grep -v monitor
echo "== bt / usb-c / input"; ls /sys/class/bluetooth 2>&1; ls /sys/class/typec 2>&1; grep -E "^N: Name" /proc/bus/input/devices
echo "== firmware qca (must be empty)"; ls /usr/lib/firmware/qca 2>&1 | head -3
echo "== errors"; journalctl -k -b --no-pager -p err -o short-monotonic | grep -v "Unhandled context fault\|FSR \|FSYNR0" | head -15
