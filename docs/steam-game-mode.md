# Galaxy S21 FE (r9q) — Arch Linux ARM, phase 2: Steam game mode (arm64) like ArmadaOS

- **Date:** 2026-11-03
- **Status:** in progress (it works and games are played; memory, performance and Bluetooth LE tuning left)
- **Project:** galaxy-s21-fe-linux · packages in `packaging/{gamescope-session-plus,gamescope-session-steam,steam-session-r9q,mangohud}`

## Summary

The phone boots straight into **Steam Big Picture** inside gamescope, with **Valve's native arm64
client** (the Steam Frame one). From Steam you can switch to Plasma and back. Steam downloads Proton 11.0
(ARM64) and the arm64 Steam Linux Runtime 4.0 by itself; **Hollow Knight: Silksong** (Windows x86) starts
and is playable with a DualShock 4 over Bluetooth and MangoHud's performance overlay.

## Context / Goal

Reproduce the ArmadaOS experience (Fedora bootc for Snapdragon phones: gamescope-session-steam + arm64
client + Proton ARM64) on Arch with the r9q's own kernel, with everything ready after installing. Arch has
no `steam` package for arm64 (nor `mangohud`, nor the `steam-devices` rules).

## Technical decisions

- **Session:** OpenGamingCollective's `gamescope-session-plus` and `gamescope-session-steam`, at the same
  commits Terra/ArmadaOS use and with their SHA-256 checked. gamescope 3.17 from ALARM. The device
  settings go in `/etc/gamescope-session-plus/sessions.d/steam`: `OUTPUT_CONNECTOR=DSI-1`,
  `PANEL_TYPE=internal`, `ORIENTATION=right` (the 1080×2340 portrait panel turned to landscape).
- **Steam client:** `/usr/bin/steam` is a launcher based on ArmadaOS's `launch-steam`.
  - The first time, `r9q-steam-bootstrap` seeds `~/.local/share/Steam` with the `bins_linuxarm64` package
    of the `steam_client_steamdeck_stable_linuxarm64` manifest, checked against the manifest's own SHA-256.
  - It also downloads the arm64 `steamrt3c` runtime, at the version and SHA-256 pinned by ArmadaOS. Steam
    updates the rest.
  - The image already comes seeded.
- **Libraries the client takes from the system:**
  - **GTK 2**, which Arch no longer has: linked from Valve's runtime in
    `~/.local/share/Steam/lib/aarch64-linux-gnu`, refreshed at every start, as ArmadaOS does with
    `libibus`;
  - `openal` (`vgui2_s.so` and `steamclient.so` ask for it);
  - **`lsof`**: without it Steam rejects the connection of its own web UI and the screen stays black.
- **Login and session switching:**
  - `plasma-login-manager` with autologin to `gamescope-session-steam.desktop` and `Relogin=true`;
  - "Switch to Desktop" calls the hook `/usr/lib/os-session-select` → `r9q-session-set` (pkexec, a polkit
    action allowed only to the active local session), which picks the next session, and ends the current
    one;
  - in Plasma, "Game Mode" does the opposite, and every boot goes back to the game mode;
  - after 5 short sessions in a row, gamescope-session-plus falls back to Plasma by itself.
- **Controllers:** Valve's udev rules `60-steam-input.rules` (`ValveSoftware/steam-devices`, pinned
  commit), which give `uaccess` to `/dev/uinput` and to the controllers' `hidraw`. Without them Steam Input
  cannot create the virtual controller and the game gets nothing.
- **Performance overlay:** MangoHud 0.8.4's `mangoapp`, Arch's PKGBUILD built for aarch64. With an own
  patch, because the GPU load always showed 0 %: the kernel's fdinfo says `drm-driver: msm` and MangoHud
  expected `msm_dpu`, so it dropped every descriptor.
- **Bluetooth for controllers:** the QCA6490's ROM firmware fails with classic Bluetooth. The DualShock 4
  connects, but encryption comes too late (HID channel rejected with `security block`) or the chip crashes
  (`hardware error 0x8c`). **Samsung's patch + NVM, unmodified**, are used, in
  `/usr/lib/firmware/updates/qca/`. With them the chip starts without an address, and it gets Samsung's
  real one from the DT (`local-bd-address`, read from `efs`).

## How to run it

```bash
bash scripts/build-packages.sh mangohud gamescope-session-plus gamescope-session-steam steam-session-r9q
bash scripts/update-phone.sh --sync       # first time: pacman -Syu + gamescope and dependencies
# remote debugging (over SSH, as the user):
gamescopectl focus_info                     # which window gamescope shows (it goes to journalctl --user)
gamescopectl screenshot /tmp/x.png          # a screenshot of what is on screen
systemctl --user stop gamescope-session-plus@steam   # restarts the session (the login comes back in)
```

Settings without sudo: `~/.config/gamescope-session-plus/sessions.d/steam` is read after the one in `/etc`.

## Results and lessons

- **Works:**
  - autologin → gamescope (Turnip, 1080×2340@120, touchscreen bound to the panel) → Steam arm64;
  - GPU-accelerated UI (ANGLE on freedreno FD660);
  - Silksong through Proton 11.0-2 (ARM64) with the GPU at ~70 %;
  - DualShock 4 over Bluetooth and an overlay with the real GPU load.
- **Chain of failures the first time**, each one hidden behind the previous one:
  1. Steam starts before Wi-Fi (it does not update).
  2. GTK 2 missing.
  3. `openal` missing.
  4. `lsof` missing (black screen).
  5. Rotation upside down.
  6. No `uinput` (dead controller in the game).
  7. MangoHud at 0 %.
- **The most treacherous:**
  - Steam ties each saved Wi-Fi network to the MAC of the moment. With a different MAC on every boot, it
    never reconnects by itself, which is why the real MACs from `efs` are used.
  - When pairing from Steam, the controller is left `Trusted: no` and does not reconnect with the PS
    button (`bluetoothctl trust` fixes it).
- **Performance:**
  - the overlay (`mangoapp`) uses ~40 % of a core drawing at 120 Hz;
  - while gaming, the GPU reaches 86 °C and the kernel throttles it;
  - without zram the game ended up killed by the OOM killer: see the phase 1 document.
- Pending:
  - `CAP_SYS_NICE` for gamescope and Steam ("failed to set thread priority");
  - brightness from Steam (it tries `sudo tee` on `/sys/class/backlight`);
  - `libavutil.so.59` (ffmpeg 7) for recording/streaming;
  - testing Bluetooth LE controllers with the patch;
  - marking controllers paired from Steam as trusted.
