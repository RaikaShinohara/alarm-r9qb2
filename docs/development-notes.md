# Galaxy S21 FE (r9q) — open problems, debugging and lessons

- **Date:** 2026-11-03
- **Status:** in progress (a living list of what is left)
- **Project:** galaxy-s21-fe-linux · scripts in `scripts/diagnostics/`

## Summary

What is left to do in the S21 FE port, the debugging tools and techniques that worked on this phone, and
the lessons worth knowing before touching it.

## Context / Goal

For the next model or person who carries the port on: what is open, how to diagnose without root, and
above all what must not be done because it can damage the phone's hardware or data.

## Technical decisions (working rules)

- **Non-negotiable:**
  - `rmtfs` always with `-r` and never with `-s`;
  - MAX77705 with no CCIC update path, no PPS/APDO, only fixed PDOs ≤ 9 V and no OTG boost with a charger
    connected;
  - `qcrypto` blacklisted;
  - GPIOs 17–19 and 52–59 reserved;
  - nothing of the bootloader nor `efs`/`sec_efs` is flashed: `efs` is only read, mounted `ro,noload`.
- **Security:**
  - never use the PC's sudo password nor set up passwordless sudo;
  - on the phone, what needs root is run by the user (`ssh -t … sudo …`);
  - do not weaken pacman's sandbox.
- **Backups:** all of Android's partitions are in `dump/`. To go back: `boot`, `vendor_boot` and `dtbo`
  from TWRP.

## How to run it (debugging)

| Tool | Use |
|---|---|
| `/proc/last_kmsg` in TWRP | the previous boot's log (persistent console in `sec_log`) and the XBL's reset history. Enter TWRP with **Vol+ + Power at the logo** without booting Linux again |
| `scripts/diagnostics/full-review.sh` | full review over SSH (pmOS and Arch): display, GPU, USB-C/DP, CPU, thermals, DSPs, Wi-Fi/BT, audio, sensors, kernel errors |
| `scripts/diagnostics/stability-watch.sh` | waits for the phone, runs a script and watches uptime/boot_id for N minutes (catches hangs and reboots) |
| `scripts/diagnostics/perf-monitor.sh` | every 5 s: temperatures, frequencies against their maximum, GPU load from fdinfo, memory, PSI, cooling states and processes. This is how the games' OOM was found |
| `scripts/diagnostics/bt-gamepad-diag.sh` | btmon + a dump of the chip's firmware while a controller connects |
| `scripts/diagnostics/bt-fw-switch.sh patch\|rom` | switches the Bluetooth firmware without rebooting (rebind of `hci_uart_qca`) |
| `scripts/diagnostics/mic-loopback.sh` | speaker→microphone acoustic test with Goertzel at 1 kHz (identifies each microphone and speaker) |
| `gamescopectl focus_info` / `screenshot` | what gamescope shows and a screenshot, without touching the phone |
| `/proc/<pid>/fdinfo` (`drm-engine-gpu`) | the real GPU load per process (what MangoHud uses) |

## Results and lessons

**Pending:**
1. **Suspend:** `deep` never resumes. Try `s2idle` (`mem_sleep_default=s2idle`) carefully, and an own
   charging mode for `androidboot.mode=charger` (now, if it is turned off with the cable plugged in, the
   whole of Linux boots).
2. **Bluetooth LE** with Samsung's patch: LE connections used to drop (`0x3e`). With the ROM, LE worked
   but classic did not. The real address (there was none before) may change something.
3. **Memory and performance in games:**
   - ~~check zram with long games~~ (done: Silksong no longer closes);
   - `CAP_SYS_NICE` for gamescope;
   - lower `mangoapp`'s cost, or limit its rate;
   - watch the GPU temperature (86 °C with throttling).
4. **Buses:** the interconnects' `sync_state` never happens (it waits for `crypto`, which has no driver),
   so DDR and the NoCs always run at their maximum and that costs battery. Fixing it without freezing the
   SoC needs an own vote for the `crypto` path.
5. **Steam:** brightness (a helper like `steamos-priv-write`), ffmpeg 7 for recording/streaming,
   auto-trusting paired controllers.
6. **Hardware not done:** modem/telephony (rmtfs `-s` brings the SLPI down; the modem crashes with
   `BADVA`), IPA, camera, NFC, fingerprint, earpiece in calls, PD at 9 V with a fast charger, USB 3 with DP
   (pin D).
7. Upstream the port to pmaports/Nura.

**Lessons:**
- "Everything built in" test kernels do not test automatic module loading: two modules with the same name
  left the phone without a display.
- A log without errors is not proof: the bottom speaker was silent, the game mode "worked" with a black
  screen and MangoHud "worked" at 0 %. Measure with the hardware: tones and microphones, gamescope
  screenshots, fdinfo, monitors.
- What looked like a kernel hang turned out to be a suspend that never resumes; what looked like a broken
  game was a controller without `uinput`; what looked like a slow GPU was a lack of memory.
- In aarch64 containers under qemu-user, setuid does not work; `makepkg -s` is no use.
- When porting between distributions, the "invisible" integration (zram, udev rules, RTC offset, stable
  MAC, power button handling) is what fails most.
- For the S21 FE, Samsung's firmware is often better than the generic one (Wi-Fi, classic Bluetooth,
  audio), but it has to be tested case by case (Bluetooth LE).
