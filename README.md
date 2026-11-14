# Arch Linux ARM for Samsung Galaxy S21 FE 5G

[![Support me on Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/raikashinohara) [![Join the Discord server](https://img.shields.io/badge/Discord-Join%20the%20server-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/9rqq27mCx)

Arch Linux ARM (aarch64) for the Samsung Galaxy S21 FE 5G Snapdragon
(`SM-G990B2`, `r9q`, SM8350), with Plasma 6 on Wayland and Linux 7.2.13.
Three editions share the same system:

- **KDE**: Plasma desktop with its login screen.
- **Plasma Mobile**: the touch shell on the phone; a screen connected to the
  USB-C port gets a desktop Plasma panel, Samsung DeX style.
- **Steam**: boots straight into Steam's game mode (Big Picture in gamescope,
  like SteamOS) with the arm64 Steam client and Proton ARM64; Plasma is the
  desktop mode. **Being worked on**: not in the current release.

## Hardware compatibility

| Component | Status | Summary |
|---|---:|---|
| Display | ✅ | Samsung EA8082 AMOLED, 1080×2340 at 120 Hz |
| Desktop | ✅ | Plasma 6, Wayland, on-screen keyboard |
| Game mode | ✅ | Steam Big Picture in gamescope, Proton ARM64 |
| GPU | ✅ | Adreno 660, freedreno and Turnip (Vulkan) |
| Touchscreen | ✅ | Synaptics S3908 multitouch |
| Power and volume buttons | ✅ | Screen on/off, long press to power off, volume |
| Wi-Fi | ✅ | QCA6490 / ath11k, the phone's own MAC address |
| Bluetooth | ✅ | QCA6490, controllers tested (DualShock 4) |
| Speakers and microphones | ✅ | Both speakers with factory calibration, both microphones |
| Vibration | ✅ | MAX77705 haptics |
| Sensors | ✅ | Auto-rotation, accelerometer, proximity, light and compass |
| Battery and charging | ✅ | Charge level and USB-PD charging up to 9 V |
| USB device mode | ✅ | USB networking and SSH |
| USB host | ✅ | OTG for keyboards, mice and storage |
| USB-C DisplayPort | ✅ | External video (DP Alt Mode) |
| Clock | ✅ | Keeps the time across reboots without network |
| Suspend / resume | ❌ | Does not resume yet; disabled |
| Modem (calls, SMS, data) | ❌ | Not started on purpose |
| Cameras | ❌ | |
| Fingerprint reader | ❌ | |
| NFC | ❌ | |
| Charging while powered off | ❌ | The phone boots Linux instead |
| Dual boot with Android | ✅ | Boot menu (Mu-Silicium v3.0.1 UEFI built in RELEASE, no on-screen log, + systemd-boot): Arch or Android, storage split 25/50/75 %, or Linux on 100 % through the UEFI |

✅ working on the physical phone · 🟡 experimental or partially validated ·
❌ unavailable · ❓ not tested

The evidence and technical limitations for every component are documented in
[hardware-status.md](docs/hardware-status.md). This table records behavior on
the development SM-G990B2; a second unit has not been tested yet.

## Installation

The installation ZIP is installed from TWRP and contains the whole system.

> [!WARNING]
> **Everything Android keeps in `userdata` (internal storage) is erased**: its
> apps, its settings and its files. Back up anything you want to keep first.
> The installer does not touch the bootloader, `recovery`, `efs`, the modem or
> `super`, but as always: you flash this at your own risk. The dual boot ZIP
> (below) keeps Android and lets you choose how much of it is erased.

### Before you start

1. **An unlocked bootloader** and **TWRP for `r9q`** in `recovery`, with AVB
   verification disabled in `vbmeta`.
2. The model must be **SM-G990B2**: the installer checks `ro.boot.em.model`
   and refuses anything else.
3. Get the ZIP from the
   [releases](https://github.com/RaikaShinohara/alarm-r9qb2/releases) and
   check its SHA-256: `archlinuxarm-kde-sm-g990b2-vX.Y.Z.zip` or
   `archlinuxarm-steam-sm-g990b2-vX.Y.Z.zip` (whole phone), or
   `archlinuxarm-kde-dualboot-sm-g990b2-vX.Y.Z.zip` or
   `archlinuxarm-mobile-dualboot-sm-g990b2-vX.Y.Z.zip` (beside Android). The
   Steam edition is being worked on and is not in the current release.

### Arch Linux ARM on the whole phone

1. From TWRP flash the installation ZIP from a USB drive (USB-C OTG adapter,
   FAT32 or exFAT) or with ADB Sideload (`adb sideload <zip>`). **Don't flash
   it from internal storage**: that is the partition being replaced, and the
   installer refuses it.
2. Wait 10–20 minutes. Everything is verified before anything is written, and
   the system is verified again after writing. It ends with "Listo.".
3. Reboot to System. On the first boot the phone **reboots once by itself** to
   apply its real Wi-Fi and Bluetooth addresses; don't press anything until
   the login screen or Steam appears.

The installer writes `userdata` (the root filesystem, which grows to fill the
partition), `boot`, `vendor_boot`, blanks the `dtbo` header (the bootloader then
skips Samsung's overlays) and clears the "boot to recovery" flags in
`param`/`misc`.

### First steps

- **User `alarm`, password `alarm`**, as in stock Arch Linux ARM. Change it
  with `passwd`.
- Plasma Mobile edition: it logs in automatically into Plasma Mobile.
- Steam edition: it logs in automatically into game mode. Steam is preloaded
  but needs Internet on its first start (Wi-Fi from Steam's own setup, or
  Settings → Internet). Desktop mode: Steam → Power → *Switch to Desktop*;
  back with **Game Mode** in Plasma's application menu.
- Over the USB cable the phone is `172.16.42.1` (the PC gets `172.16.42.2`):
  `ssh alarm@172.16.42.1`. SSH accepts passwords only over the USB link; from
  Wi-Fi only keys work.

The full installation guide is in [docs/installation.md](docs/installation.md).

### Arch Linux ARM beside Android (dual boot)

One ZIP installs Arch Linux ARM next to the Android ROM that is already on
the phone, in any edition: `archlinuxarm-kde-dualboot-sm-g990b2-vX.Y.Z.zip`
(KDE Plasma), `archlinuxarm-mobile-dualboot-sm-g990b2-vX.Y.Z.zip` (Plasma
Mobile) or `archlinuxarm-steam-dualboot-sm-g990b2-vX.Y.Z.zip` (Steam game
mode, SteamOS style; being worked on). At power-on a boot menu
shows **Arch Linux ARM** (default, 5 s) or **Android** (Xiaomi Pad 5 style:
Android's own `boot.img` carries a small selector and the Mu-Silicium UEFI). It works on the 128 GB and the 256 GB models. Details in
[docs/dual-boot.md](docs/dual-boot.md).

1. Android must be installed and booting (its own `boot`, `vendor_boot` and
   `dtbo`), and TWRP in `recovery`.
2. From TWRP, flash the ZIP with ADB Sideload (`adb sideload <zip>`) or from a
   USB drive. The internal storage is encrypted by Android, so TWRP cannot
   read it, and it may be erased anyway.
3. Choose with the **volume keys** and confirm with **Power**:
   - **Linux 25 % / Android 75 %**, **Linux 50 % / Android 50 %** or
     **Linux 75 % / Android 25 %** (the sizes for your phone are shown).
     A new split **erases Android's data** (apps, photos, accounts: the same as
     a Format Data); the Android system itself stays installed.
   - **Linux 100 %**: no Android. `boot` gets only the selector and the UEFI
     (Android's kernel is not needed), `userdata` keeps a 256 MiB stub and Linux
     gets the rest. Android's `boot.img` is kept in the ESP.
   - **Keep** the current split (only when the phone is already split): Android
     is not touched, Arch is reinstalled.
   - **Remove Linux: Android 100 %** (only when split and Android's `boot.img`
     is in the ESP): writes Android's own `boot` back, deletes `esp` and
     `linux`, gives the whole area back to `userdata` and formats it (Android
     starts as freshly formatted). The fixed TWRP stays.
   - **Cancel**: nothing is written.

   A second screen asks for confirmation. If the screen turns off while it
   waits, touch it (the keys are reserved for the menu).
4. Wait 10–20 minutes. It ends with "Done."; reboot to System.

What it does, after checking everything (model, partition table, the boot
image, the SHA-256 of every file) and before writing anything:

- splits the old `userdata` area into `userdata` (Android), a 512 MiB `esp`
  and `linux`, with one `sgdisk` call (the other 33 entries stay byte for
  byte), and tells TWRP's kernel about it so no reboot is needed;
- writes Arch to `linux`, its kernel, initramfs and DTB, systemd-boot and the
  "Android" entry to the ESP;
- adds the selector and the UEFI to Android's `boot.img`, or with Linux 100 %
  writes the selector and the UEFI alone (the original is saved first in the
  ESP as `r9q/boot-android-original.img`, and carried over when the ESP is
  formatted again);
- installs the **fixed TWRP** in `recovery`: leaving it goes back to the boot
  menu (Samsung's bootloader keeps a sticky "boot recovery" flag that only the
  stock recovery clears) and it no longer hangs at its logo trying to decrypt
  Android (`/data` stays encrypted and unmounted in it); the changed files are in the
  [TWRP device tree fork](https://github.com/RaikaShinohara/twrp_device_samsung_r9q/tree/r9q-dualboot);
- clears the "boot to recovery" flags.

Never touched: `super`, `vendor_boot`, `dtbo`, `efs`, the modem, the
bootloader.

### Back to Android

From the dual boot or Linux 100 %: flash the dual boot ZIP again and choose
**Remove Linux: Android 100 %**. Otherwise flash the stock SM-G990B2 firmware
with Odin (or restore your `boot`, `vendor_boot` and `dtbo` backups from TWRP)
and format data.

## Updating an existing installation

`sudo pacman -Syu` updates everything that comes from Arch Linux ARM. The
phone's own packages (kernel, firmware, device configuration, game mode) are
built from this repository with `scripts/build-packages.sh` and installed over
SSH with `scripts/update-phone.sh`, which also rebuilds and flashes the boot
images and reboots.

**Do not flash the TWRP installer to update**: it is for clean installations
and replaces the whole filesystem.

## Known issues

- **Suspend** does not resume (the phone stays dead until a forced reboot), so
  it is disabled; the screen just turns off.
- **Charging while powered off**: with the cable in, the bootloader starts
  Linux in charger mode; it boots the full system instead.
- **Bluetooth LE** with the Samsung patch is pending a retest; classic
  Bluetooth (game controllers) works.
- A controller paired from Steam may need `bluetoothctl trust <address>` once
  to reconnect by itself.
- The GPU throttles at about 86 °C in long gaming sessions, and the MangoHud
  overlay costs about 40 % of one CPU core at 120 Hz.

## Documentation

| Document | Contents |
|---|---|
| [Hardware status](docs/hardware-status.md) | Evidence, limitations and pending hardware tests |
| [Overview](docs/overview.md) | Goals, current state and how to run everything |
| [Boot strategy](docs/boot-strategy.md) | Samsung bootloader requirements, partitions, kernel and drivers |
| [Arch Linux ARM userspace](docs/archlinuxarm-userspace.md) | Root filesystem, device integration, TWRP zip |
| [Steam game mode](docs/steam-game-mode.md) | arm64 Steam client, gamescope session, MangoHud |
| [Development notes](docs/development-notes.md) | Open problems, debugging tools and lessons |
| [Dual boot](docs/dual-boot.md) | Android + Linux with a boot menu, Xiaomi Pad 5 style; UEFI sources: [Mu-Silicium fork, branch r9q-dualboot](https://github.com/RaikaShinohara/Mu-Silicium/tree/r9q-dualboot); TWRP changes: [twrp_device_samsung_r9q fork, branch r9q-dualboot](https://github.com/RaikaShinohara/twrp_device_samsung_r9q/tree/r9q-dualboot) |
| [Arch plan](docs/arch-plan.md) | How the Arch port was planned |
| [Porting log](docs/porting-log.md) | Chronological engineering history |
| [Installation](docs/installation.md) | Full installation guide: both editions and the dual boot |

## Building

Everything runs on an x86_64 Linux PC with rootless podman and qemu-user
(`binfmt` for aarch64); the Arch part needs no sudo.

```sh
# 1. kernel and firmware: postmarketOS packages built with pmbootstrap
bash scripts/prepare-pmaports.sh
pmbootstrap build linux-samsung-r9q device-samsung-r9q firmware-samsung-r9q
# 2. Arch Linux ARM packages into work/repo (needs work/dl/ArchLinuxARM-aarch64-latest.tar.gz)
bash scripts/build-packages.sh
# 3. image, checks and TWRP zip (EDITION=kde or steam) into artifacts/
PUBLIC=1 EDITION=kde bash scripts/build-image.sh
PUBLIC=1 EDITION=kde bash scripts/check-image.sh
PUBLIC=1 EDITION=kde bash scripts/make-twrp-zip.sh
# or both public editions, each one installed on the PC as a test
bash scripts/build-release.sh
bash scripts/test-twrp-installer.sh
# the dual boot release: public DUAL=1 image, then the all-in-one ZIP
PUBLIC=1 DUAL=1 EDITION=kde bash scripts/build-image.sh
bash scripts/test-dualboot-release.sh     # the installer in a TWRP sandbox, 128/256 GB
bash scripts/make-dualboot-release.sh
```

Without `PUBLIC=1` the image uses your own account: user, locale and time zone
from `work/pmbootstrap-r9q.cfg`, the password from `work/CREDENTIALS.txt`
(`password=...`) and your `~/.ssh/id_*.pub`. All paths are in
`scripts/paths.sh`.

## Repository layout

```text
kernel/       Device tree, drivers, patches and kernel configuration
packaging/    Arch Linux ARM packages; postmarketos/ for the kernel and firmware build
configs/      Image setup, the TWRP installer, the vendor_boot cmdline and the dual boot selector
scripts/      Reproducible build, test and deployment tools; diagnostics/ runs on the phone
docs/         Detailed documentation and engineering history
artifacts/    Generated release files; not versioned
work/         Scratch space for builds; not versioned
```

## Firmware and licensing

Keep in mind the project has been made with the help of agentic AI (Claude
Code), so some things might not be done in the best possible way.

Proprietary Samsung and Qualcomm firmware is not stored in Git. The firmware
packages repack the blobs from the phone's own stock `vendor` partition; the
release images include them.

The project default license is MIT; per-file SPDX headers take precedence.
Kernel code and patches remain GPL-2.0-only, and the device tree remains
BSD-3-Clause. Imported sources are listed in
[kernel/PROVENANCE.md](kernel/PROVENANCE.md).

Contributions must be reproducible in the repository and validated on physical
hardware before a component is marked as working.
