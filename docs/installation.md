# Installation

Arch Linux ARM for the Galaxy S21 FE (SM-G990B2) in three editions (KDE, Plasma Mobile and Steam), installed from TWRP.
The Steam edition is being worked on and is not in the current release. The ZIPs are in [Releases](../../../releases):

| File | What it is |
|---|---|
| `archlinuxarm-kde-sm-g990b2-vX.Y.Z.zip` | **KDE edition**: the Plasma desktop with its login screen. No Steam. |
| `archlinuxarm-steam-sm-g990b2-vX.Y.Z.zip` | **Steam edition**: boots straight into Steam's game mode (Big Picture + gamescope, like SteamOS). Plasma stays as the "desktop mode". |
| `archlinuxarm-kde-dualboot-sm-g990b2-vX.Y.Z.zip` | **Dual boot, KDE**: the KDE edition **next to the Android you already have**, with a boot menu (see [Dual boot with Android](#dual-boot-with-android)). |
| `archlinuxarm-mobile-dualboot-sm-g990b2-vX.Y.Z.zip` | **Dual boot, Plasma Mobile**: Plasma Mobile next to Android, with the same boot menu; a screen on USB-C gets a desktop panel, Samsung DeX style. |
| `archlinuxarm-steam-dualboot-sm-g990b2-vX.Y.Z.zip` | **Dual boot, Steam**: the Steam edition (game mode, SteamOS style) next to Android, with the same boot menu. Being worked on: not in the current release. |

Each ZIP comes with its `.sha256`. They all fit on a FAT32 USB drive (under 4 GiB).
What follows (up to "First boot") is for the first two, which take the **whole** phone.

## Before installing

- **It erases the whole internal storage** (`userdata`: Android, photos, everything). The system is
  installed there.
- It also writes `boot`, `vendor_boot`, the `dtbo` header (zeroed) and clears the "boot to recovery"
  flags in `param`/`misc`.
- **It does not touch** the bootloader, `recovery` (TWRP stays), `efs`, the modem or `super`.
- That is why the ZIP **cannot be in internal storage**: put it on a USB drive or use `adb sideload`. If
  you try from internal storage, the installer refuses without writing anything.
- Before writing anything it checks that it is a SM-G990B2, the sizes and the SHA-256 of everything. If
  something fails, it says so and does not touch the phone.

## Installing

### Option A: USB drive (recommended)

1. Copy the ZIP to a FAT32 (or exFAT) USB drive.
2. With the phone in TWRP, connect the drive through a USB-C OTG adapter.
3. TWRP → **Install** → **Select Storage** → **USB-OTG** → choose the ZIP → swipe to confirm.
4. Wait (10–20 minutes): it checks the ZIP, writes the system, verifies it and writes the boot images.
   It ends with "Done.".
5. **Reboot** → **System**.

### Option B: adb sideload

1. TWRP → **Advanced** → **ADB Sideload** → swipe.
2. On the PC:

   ```bash
   adb sideload archlinuxarm-kde-sm-g990b2-vX.Y.Z.zip
   ```

3. When it ends, **Reboot** → **System**. It is slower than the USB drive (the ZIP goes through the cable
   twice: once to check it and once to write it). If sideload fails with such a big file, use the USB
   drive.

## Dual boot with Android

The `archlinuxarm-kde-dualboot-...`, `archlinuxarm-mobile-dualboot-...` and `archlinuxarm-steam-dualboot-...` ZIPs install Arch (KDE, Plasma Mobile or the Steam game mode) **without removing Android**. At power-on a
menu shows: **Arch Linux ARM** (default, after 5 s) or **Android**. It works on the 128 GB and the 256 GB
models.

Before:

- Android must be installed and booting (your ROM, with its `boot`, `vendor_boot` and `dtbo`).
- TWRP in `recovery`. The ZIP also installs a **fixed TWRP** (see below).

Installing:

1. Put the phone in TWRP. Install the ZIP with **adb sideload** (TWRP → Advanced → ADB Sideload, and on
   the PC `adb sideload archlinuxarm-kde-dualboot-sm-g990b2-vX.Y.Z.zip`), from a USB drive, or after
   copying it to `/tmp` (`adb push … /tmp/`). TWRP cannot read Android's internal storage: Android keeps
   it encrypted.
2. Choose with the **volume keys** and confirm with **Power**:
   - **Linux 25 % / Android 75 %**, **Linux 50 % / Android 50 %** or **Linux 75 % / Android 25 %**. Each
     option shows the GB left on your phone. **A new split erases Android's data** (apps, photos,
     accounts: the same as a Format Data). The Android system stays installed and starts as freshly
     formatted.
   - **Linux 100 %**: no Android. `boot` gets only the selector and the UEFI (Android's kernel is not
     needed), `userdata` keeps an unused 256 MiB and Linux takes the rest. Android's `boot` is kept in
     the `esp`.
   - **Keep** the current split (only shown if the phone is already split): Android is not touched and
     Arch is reinstalled.
   - **Remove Linux: Android 100 %** (only if split and Android's `boot` is kept in the `esp`): puts
     Android's original `boot` back, deletes `esp` and `linux`, gives everything back to `userdata` and
     formats it (Android starts as freshly formatted). The fixed TWRP stays.
   - **Cancel**: nothing is written.

   A second screen asks to confirm ("Yes, install"). If the screen turns off while you wait, touch it to
   turn it on: the keys are reserved for the menu.
3. Wait (10–20 minutes) until "Done." and **Reboot** → **System**.

What it does, after checking everything (model, partition table, Android's `boot`, the SHA-256 of every
file) and before writing anything:

- splits the `userdata` area into `userdata` (Android), `esp` (512 MiB) and `linux`, without touching the
  other 33 partitions and without a reboot;
- writes Arch to `linux`, and its kernel and the menu (systemd-boot with the "Android" entry) to the
  `esp`;
- adds to Android's `boot` the selector and the Mu-Silicium v3.0.1 UEFI built in RELEASE mode, with no
  log on the screen (as on the Xiaomi Pad 5), or with Linux 100 % writes only the selector and the UEFI to
  `boot`. Before that it keeps the original `boot` in the `esp` (`r9q/boot-android-original.img`; if the
  `esp` is formatted again, the copy moves to the new one);
- installs the **fixed TWRP**: leaving TWRP goes back to the menu (the original TWRP left the phone stuck
  in recovery) and it no longer stays at its logo trying to decrypt Android (in this TWRP, Android's
  `/data` stays encrypted and unmounted);
- clears the "boot to recovery" flags.

It does not touch `super`, `vendor_boot`, `dtbo`, `efs`, the modem or the bootloader.

To remove Linux and keep only Android: install the ZIP again and choose **Remove Linux: Android 100 %**
(or flash Samsung's firmware with Odin and format data). UEFI sources with the fixes:
[Mu-Silicium fork, branch `r9q-dualboot`](https://github.com/RaikaShinohara/Mu-Silicium/tree/r9q-dualboot);
TWRP changes: [twrp_device_samsung_r9q fork, branch `r9q-dualboot`](https://github.com/RaikaShinohara/twrp_device_samsung_r9q/tree/r9q-dualboot).

## First boot

- The system partition grows by itself to fill the whole internal storage (in the dual boot, the whole
  `linux` partition).
- The phone **reboots once by itself**: it reads the real Wi-Fi and Bluetooth MACs from `efs` (read
  only) and puts them into the boot. Do not press anything until you see the login screen.
- User **`alarm`**, password **`alarm`** (as in Arch Linux ARM). Change it with `passwd` as soon as you
  are in.
- No Wi-Fi networks are saved: connect the first time.
- Over the USB cable the phone is at `172.16.42.1` with SSH (the PC gets `172.16.42.2`):
  `ssh alarm@172.16.42.1`. SSH accepts a password only over the cable; over Wi-Fi it needs a key.

### KDE edition

A normal login screen → Plasma. Wi-Fi is set up from the network icon in the panel.

### Plasma Mobile edition

- Boots without asking for a password straight into Plasma Mobile (touch shell, on-screen keyboard).
  Wi-Fi is in the quick settings (swipe down from the top).
- **Desktop on an external screen**: connect a monitor to the USB-C port (DP Alt Mode,
  for example a USB-C to HDMI adapter). Plasma Mobile switches to its docked mode (windows with
  borders) and the monitor gets a desktop Plasma panel: application menu, task manager, system tray
  and clock. The phone keeps its mobile shell. Unplugging the screen hides the panel; plugging it in
  again brings it back.

### Steam edition

Being worked on: not in the current release.

- Boots without asking for a password straight into the game mode.
- Steam comes downloaded (the ARM64 client and its runtime), but **the first time it needs Internet** to
  update and sign in. Steam shows its network assistant; it is also in Settings → Internet.
- If you cannot connect from Steam: plug in the USB cable and, from the PC, `ssh alarm@172.16.42.1` and
  then `nmcli device wifi connect "YOUR_NETWORK" --ask`.
- **Desktop mode**: Steam → Power → *Switch to Desktop*. To go back, open **Game Mode** from Plasma's
  application menu.
- Controllers: DualShock 4 over Bluetooth tested (pair it from Steam's Settings → Bluetooth).

## What is included (both editions)

- Mainline kernel 7.2.13 (r10) with everything of the port: display at 120 Hz, touchscreen, Adreno 660
  GPU, USB-C (charging up to 9 V, OTG, DisplayPort video output), battery, vibration.
- **Sensors**: accelerometer (automatic rotation), proximity, light and compass (SLPI: hexagonrpcd +
  libssc + iio-sensor-proxy).
- Audio: both speakers with the factory calibration, and the microphones.
- Wi-Fi and Bluetooth with their **real MACs**; Bluetooth with Samsung's patch and NVM (needed for classic
  Bluetooth controllers).
- A clock that is kept across reboots, even without a network.
- **zram**: compressed swap in RAM (zstd) of 150 % of the RAM, about **7.5 GB**, with postmarketOS's
  settings (`swappiness` 180). It is what kept games from closing for lack of memory.
- Suspend disabled (on this phone it does not wake up yet). Power button: a short press turns the screen
  on/off; holding it powers off.
- Arch Linux ARM packages: `sudo pacman -Syu` works. The phone's own packages (kernel, firmware,
  configuration) come from this repository: they are built and installed from the PC with
  `scripts/update-phone.sh`.

Only in the Plasma Mobile edition: Plasma Mobile and `r9q-dock` (the desktop panel on external
screens).

Only in the Steam edition: Steam with Proton ARM64, gamescope-session, MangoHud (with the GPU load),
Steam Input rules for controllers.

## What does not work yet

Calls, SMS and mobile data (the modem is deliberately not started), cameras, fingerprint, NFC, suspend
and the charging mode with the phone off.

## How they are built

```bash
bash scripts/build-packages.sh
bash scripts/build-release.sh     # both public editions (alarm/alarm) in artifacts/release/
EDITION=kde bash scripts/make-dualboot-release.sh     # the dual boot ZIPs (EDITION=mobile or steam for the others)
```

The installers are `configs/twrp/update-binary` (whole phone; tested on the PC with
`bash scripts/test-twrp-installer.sh`) and `configs/twrp/dualboot-update-binary` (dual boot; tested with
`bash scripts/test-dualboot-release.sh`).
