# Galaxy S21 FE (r9q) — mainline Linux: overview and status

- **Date:** 2026-11-03
- **Status:** in progress (postmarketOS working; Arch Linux ARM with the Steam game mode in daily use)
- **Project:** galaxy-s21-fe-linux · code in `.` · full engineering log in `docs/porting-log.md`

## Summary

A port of **mainline Linux 7.2.13** to the Samsung Galaxy S21 FE 5G, Snapdragon variant (**SM-G990B2**,
codename `r9q`, SoC SM8350 / Snapdragon 888). First came a **postmarketOS** port (Plasma Desktop) with
almost all the hardware working and then, on the same kernel, an **Arch Linux ARM** image that boots
straight into **Steam Big Picture** with Valve's native arm64 client, in the style of ArmadaOS. Windows
x86 games (Hollow Knight: Silksong) already run with Proton 11 (ARM64).

## Context / Goal

The owner wanted real Linux (not Android, not a chroot) on their S21 FE: first a postmarketOS for daily
use and then an Arch with a "console mode" like ArmadaOS (Fedora bootc for Snapdragon phones), with
everything ready after installing. There was no port: the pmOS wiki only mentions an almost-mainline 6.7
kernel booted with uniLoader.

The phone: Samsung bootloader unlocked (`verifiedbootstate=orange`), no A/B, `boot` and `vendor_boot`
with header v3, TWRP in `recovery`, 6 GB of RAM (the kernel sees ~5 GB), UFS.

## Hardware status

| Area | Status | Notes |
|---|---|---|
| Boot, UFS, 8 CPUs, cpufreq, EAS, L3 | ✅ | capacities 325/828/1024, `epss_l3` |
| EA8082 display (DSI, DSC, 120 Hz, brightness) | ✅ | own driver `panel-samsung-ea8082` |
| Adreno 660 GPU | ✅ | freedreno (GL ES 3.2 / GL 4.6) and Turnip (Vulkan), 315–840 MHz |
| Synaptics S3908 touchscreen | ✅ | TouchComm (linux-input v2 series + 3 own patches) |
| QCA6490 Wi-Fi (ath11k) | ✅ | Samsung's firmware; real MAC read from `efs` |
| QCA6490 Bluetooth | ✅ with caveats | classic (DualShock 4) fine with Samsung's patch; LE to be tested again |
| 2× CS35L41 speakers | ✅ | stereo with the protection DSP and the factory calibration |
| Microphones (2 DMICs) | ✅ | VA macro |
| Sensors (SLPI: accelerometer, light, proximity, compass) | ✅ | hexagonrpcd + libssc + iio-sensor-proxy |
| USB-C: OTG, automatic role, PD ≤ 9 V | ✅ | patches from the Tab S8+ port |
| HDMI output (DP Alt Mode) | ✅ | own patch (VDMs through the CCIC) |
| Battery and charging, vibration, buttons, RTC | ✅ | RTC with a stored offset (as Android does) |
| ADSP / CDSP / SLPI | ✅ | the modem is deliberately not started |
| Suspend | ❌ | `deep` does not resume; disabled |
| Modem/telephony, camera, NFC, fingerprint | ❌ | not started |

## Technical decisions

- **One kernel for both systems:** 7.2.13 + 26 patches (`kernel/patches/0001`–`0026`), an own DTS
  (`kernel/dts/sm8350-samsung-r9q.dts`) and pmOS's `stable` config + the `r9q.config` fragment.
  pmbootstrap builds it; Arch **repackages** the `.apk` (the same binaries and module signatures).
- **pmOS:** packages in `packaging/postmarketos/{linux,device,firmware}-samsung-r9q`, pmbootstrap with its
  own config (`work/pmbootstrap-r9q.cfg`) so the owner's is not touched.
- **Arch:** built **without sudo**, with rootless podman and qemu-user, from the verified official ALARM
  tarball; packages in `packaging/`, an ext4 image written straight to `userdata`.
- **Firmware:** Samsung's (`/vendor/firmware`, NON-HLOS) where the generic one fails (Wi-Fi, Bluetooth,
  DSPs, audio, zap shader); `linux-firmware` is excluded on purpose.
- **Safety rules that are never broken:**
  - `rmtfs` always `-r` (read-only EFS) and never `-s` (the modem does not start: its crash took the SLPI
    down with it);
  - MAX77705: never the CCIC firmware update path, never PPS/APDO, only fixed PDOs ≤ 9 V, never OTG boost
    with a charger connected;
  - `qcrypto` blacklisted (it belongs to TrustZone and freezes the SoC);
  - GPIOs 17–19 and 52–59 reserved (TrustZone).

## How to run it

```bash
# postmarketOS (needs sudo on the PC): packages + image, installed from TWRP (ERASES userdata)
bash scripts/prepare-pmaports.sh && pmbootstrap build linux-samsung-r9q device-samsung-r9q firmware-samsung-r9q
# (the pmOS image and flashing: development-tree tools, not included)

# Arch Linux ARM (no sudo): packages, image, check and install from TWRP (ERASES userdata)
bash scripts/build-packages.sh && EDITION=kde bash scripts/build-image.sh && EDITION=kde bash scripts/check-image.sh
EDITION=kde bash scripts/make-twrp-zip.sh                 # ZIP to install from TWRP without a PC (artifacts/)
EDITION=kde scripts/flash-twrp-adb.sh --yes-erase-userdata    # or over adb (EDITION=steam: game mode)
bash scripts/update-phone.sh [--sync] [package ...]       # update on the phone over SSH (USB)
```

USB network: the phone is `172.16.42.1` (NCM gadget + DHCP), SSH with the PC's key. Back to Android:
restore `boot`, `vendor_boot` and `dtbo` from `dump/` in TWRP (section 5 of `docs/porting-log.md`).

## Results and lessons

- This project's documents: **boot, kernel and hardware** (pmOS); **Arch phase 1** (base image);
  **Arch phase 2** (Steam game mode); **open problems, debugging and lessons**; **dual boot**.
- What took the most time:
  - Samsung's bootloader (DTB selection, `dtbo`, the `param` flag that always sends you to TWRP);
  - the TrustZone things (GPIOs, `qcrypto`, watchdog);
  - audio (the CS35L41 protection DSP);
  - and, in Arch, everything pmOS gives "for free" without it showing: zram, udev rules, RTC, stable MAC.
- General lesson: verify on the real hardware and measure (logs + acoustic tests, monitors), instead of
  taking something as good because the log shows no errors.
