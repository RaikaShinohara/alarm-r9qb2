# Hardware status

Behavior on the development SM-G990B2 with kernel 7.2.13 (`linux-samsung-r9q`
r10) and `device-samsung-r9q` 1-12. "Row N" refers to the table in section 0
of [porting-log.md](porting-log.md), which records each problem, its symptom
and its fix; the dated entries below it hold the measurements.

✅ working on the physical phone · 🟡 partial or not fully validated ·
❌ unavailable · ❓ not tested

| Component | Status | Evidence and limitations |
|---|:---:|---|
| Boot (ABL, header v3) | ✅ | DTB matched by `qcom,msm-id`/`board-id`, `dtbo` header zeroed, `param`/`misc` flags cleared (rows 1–3). TrustZone GPIOs reserved (row 5), `qcrypto` blacklisted (row 13) |
| Display | ✅ | Samsung EA8082 AMOLED 1080×2340, own panel driver, DSC, 60/120 Hz, brightness (row 16) |
| Touchscreen | ✅ | Synaptics S3908 over TouchComm, Samsung coordinate events (patches 0006–0009) |
| GPU | ✅ | Adreno 660, Mesa freedreno and Turnip (Vulkan); zap shader from the stock firmware (row 17). Thermal limiting seen at 86 °C in long games |
| CPU scaling | ✅ | Stock capacities, EAS on, L3/DDR votes (row 26) |
| Wi-Fi | ✅ | QCA6490 / ath11k with Samsung's firmware and board file (row 15). Real MAC from `efs`, written into the DT on first boot |
| Bluetooth | ✅ | QCA6490 on UART18 (row 20). Samsung patch + NVM: classic BT works (DualShock 4 tested in games). BLE with the patch: 🟡 retest pending |
| Speakers | ✅ | 2× CS35L41 on primary MI2S with Samsung's protection firmware and factory calibration (row 22) |
| Microphones | ✅ | 2 DMICs through the VA macro (row 25) |
| Earpiece for calls | ❓ | top speaker in receiver mode not set up (no modem anyway) |
| Sensors | ✅ | SLPI via hexagonrpcd + libssc + iio-sensor-proxy: accelerometer (auto-rotation), proximity, light, compass (rows 27) |
| Battery and charging | ✅ | MAX77705 charger and fuel gauge, 4.35 V conservative limit (row 10b); USB PD sink up to 9 V / 15 W (row 18) |
| USB-C device mode | ✅ | NCM gadget + DHCP: SSH at 172.16.42.1 |
| USB-C host (OTG) | ✅ | role switch via the MAX77705 CCIC (row 18) |
| USB-C video out | ✅ | DisplayPort Alt Mode, 4 lanes (row 19). Audio over DP not tested |
| Vibration | ✅ | MAX77705 haptic with GP2 PWM (row 21) |
| Power and volume buttons | ✅ | short press toggles the screen, long press powers off |
| Clock | ✅ | PMIC RTC + offset kept across reboots (`r9q-clock`) |
| Suspend / resume | ❌ | `deep` never resumes; disabled (logind, Plasma). `s2idle` untested |
| Charging while off | ❌ | the ABL boots Linux in charger mode instead |
| Modem (calls, SMS, data) | ❌ | deliberately not booted (`rmtfs -r`, no `-s`) |
| Cameras, flash | ❌ | |
| Fingerprint (under display) | ❌ | Goodix in the secure world |
| NFC | ❌ | |
| Wireless charging | ❓ | IDT P9321, no driver |
| Dual boot with Android | ✅ | Xiaomi Pad 5 mechanism with the official Mu-Silicium v3.0.1 UEFI: menu with Arch and Android, mark at `0x17FE00000`, PSCI `SYSTEM_RESET`; storage split 52.5 / 0.5 / 52 GiB ([dual-boot.md](dual-boot.md)). With `scripts/fix-uefi-memmap.py` (4 entries of the UEFI's memory table, 68 bytes) Linux sees 4.92 GiB of RAM, as with Samsung's bootloader; with `scripts/fix-uefi-mmu.py` the UEFI also boots after a software restart (it crashed in ArmCpuDxe) |

## Desktop and gaming

| Feature | Status | Notes |
|---|:---:|---|
| Plasma 6 (Wayland) | ✅ | on-screen keyboard, auto-rotation |
| Steam game mode | ✅ | gamescope-session-plus + arm64 Steam client, autologin, switch to desktop and back |
| Proton ARM64 | ✅ | Hollow Knight: Silksong (Windows x86) plays |
| MangoHud overlay | ✅ | with GPU load (msm fdinfo patch); `mangoapp` costs ~40 % of one core at 120 Hz |
| Memory under games | ✅ | zram 150 % of RAM, zstd, swappiness 180: without it games were OOM-killed |
| Controller input in games | ✅ | Valve's Steam Input udev rules (uinput, hidraw) |
