#!/bin/sh
# Full read-only review of an installed build: one section per subsystem.
# Run as the normal user over SSH (no root needed).
export XDG_RUNTIME_DIR=/run/user/$(id -u)
sec() { echo; echo "===== $*"; }
val() { cat "$1" 2>/dev/null || echo "?"; }

sec SYSTEM
. /etc/os-release; echo "$PRETTY_NAME"
uname -rv; cut -d' ' -f1 /proc/uptime
# postmarketOS (apk) or Arch Linux ARM (pacman)
{ apk info -v 2>/dev/null || pacman -Q 2>/dev/null; } | grep -E "^(linux|device|firmware)-samsung-r9q|^hexagonrpcd[- ]0|^postmarketos-initramfs-|^(rmtfs|tqftpserv|qrtr|libssc) "
systemctl is-system-running
systemctl --failed --no-legend --plain
systemctl --user --failed --no-legend --plain 2>/dev/null
journalctl -b --no-pager -o short-monotonic | grep -E "plasma-ksplash.service: Consumed" | head -1

sec DISPLAY
for c in /sys/class/drm/card*-*; do echo "$(basename $c): $(val $c/status) $(val $c/enabled) modes=$(head -1 $c/modes 2>/dev/null)"; done
for b in /sys/class/backlight/*; do echo "backlight $(basename $b): $(val $b/brightness)/$(val $b/max_brightness) actual=$(val $b/actual_brightness)"; done
cat /sys/module/panel_samsung_ea8082/parameters/refresh_rate 2>/dev/null | sed 's/^/refresh_rate param=/'
journalctl -b --no-pager -o cat -u 'systemd-backlight@*' | tail -3

sec GPU
ls /dev/dri/; cat /sys/class/devfreq/3d00000.gpu/cur_freq /sys/class/devfreq/3d00000.gpu/governor 2>/dev/null | tr '\n' ' '; echo
journalctl -k -b --no-pager | grep -iE "adreno|a6xx|gmu|zap|msm_dpu|\[drm\]" | grep -v "Unhandled context" | tail -8

sec USB-C / DISPLAYPORT
ls /sys/class/typec/ 2>&1 | tr '\n' ' '; echo
for p in /sys/class/typec/port*; do [ -d "$p" ] && echo "$(basename $p): data_role=[$(val $p/data_role)] power_role=[$(val $p/power_role)] pwr_op=$(val $p/power_operation_mode) orientation=$(val $p/orientation)"; done
ls /sys/class/typec_mux/ 2>/dev/null | tr '\n' ' '; echo
for d in ae90000.displayport-controller 88e8000.phy usb-sbu-mux; do echo "$d -> $(readlink /sys/bus/platform/devices/$d/driver | sed 's|.*/||')"; done
readlink /sys/bus/i2c/devices/1-0025/driver | sed 's|.*/|typec@25 -> |'
cat /sys/class/usb_role/*/role 2>/dev/null | sed 's/^/usb role: /'

sec CPU
for p in 0 4 7; do d=/sys/devices/system/cpu/cpufreq/policy$p; echo "policy$p $(val $d/scaling_governor) $(val $d/cpuinfo_min_freq)-$(val $d/cpuinfo_max_freq) cur=$(val $d/scaling_cur_freq) n=$(wc -w < $d/scaling_available_frequencies) trans=$(val $d/stats/total_trans)"; done
for c in 0 4 7; do printf 'cap%s=%s ' $c "$(val /sys/devices/system/cpu/cpu$c/cpu_capacity)"; done; echo "eas=$(val /proc/sys/kernel/sched_energy_aware)"
readlink /sys/bus/platform/devices/18590000.interconnect/driver | sed 's|.*/|epss_l3 -> |'
cat /sys/devices/system/cpu/cpuidle/current_driver
grep -cE "dcvsh" /proc/interrupts | sed 's/^/dcvsh irq lines: /'

sec THERMAL / BATTERY
for z in cpu0 cpu7-top gpu-top max170xx_battery; do for d in /sys/class/thermal/thermal_zone*; do [ "$(cat $d/type)" = "$z-thermal" ] || [ "$(cat $d/type)" = "$z" ] && echo "$z=$(( $(cat $d/temp) / 1000 ))C"; done; done | tr '\n' ' '; echo
for s in /sys/class/power_supply/*; do echo "$(basename $s): online=$(val $s/online) status=$(val $s/status) cap=$(val $s/capacity) V=$(val $s/voltage_now) I=$(val $s/current_now) health=$(val $s/health)"; done

sec DSPs
for r in /sys/class/remoteproc/remoteproc*; do printf '%s=%s ' "$(cat $r/name)" "$(cat $r/state)"; done; echo
systemctl is-active rmtfs pd-mapper tqftpserv qrtr-ns 2>/dev/null | paste -sd' '

sec WIFI / BLUETOOTH
ip -br link | grep -E "wlan|usb"
nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null
journalctl -k -b --no-pager | grep -iE "ath11k" | grep -iE "fw_version|firmware|error|fail" | head -4
for h in /sys/class/bluetooth/hci*; do echo "$(basename $h) $(val $h/address 2>/dev/null)"; done
bluetoothctl show 2>/dev/null | grep -E "Powered|Name:|Address" | head -3

sec AUDIO / MIC
cat /proc/asound/cards | head -2
pactl info 2>/dev/null | grep -E "^Server Name"
pactl list short sinks 2>/dev/null; pactl list short sources 2>/dev/null | grep -v monitor

sec SENSORS
systemctl is-active hexagonrpcd-sdsp iio-sensor-proxy | paste -sd' '
timeout 6 monitor-sensor 2>&1 | head -8

sec INPUT
grep -E "^N: Name" /proc/bus/input/devices

sec "KERNEL ERRORS / WARNINGS, deduplicated"
journalctl -k -b --no-pager -p warning -o cat | grep -vE "Unhandled context fault|FSR    =|FSYNR0|callbacks suppressed|Fixed dependency cycle" | sed -E 's/[0-9a-f]{8,}/X/g' | sort | uniq -c | sort -rn | head -40

sec DEFERRED / UNBOUND
journalctl -k -b --no-pager -o cat | grep -E "deferred probe pending|probe with driver .* failed|sync_state\(\) pending" | sort | uniq -c | sort -rn | head -20
