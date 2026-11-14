# Galaxy S21 FE (r9q) — Arch Linux ARM, phase 1: a base image on par with pmOS

- **Date:** 2026-11-07
- **Status:** done (zram checked with Silksong; ZIP installable from TWRP since 2026-11-07)
- **Project:** galaxy-s21-fe-linux · `scripts/` (plan in `docs/arch-plan.md`)

## Summary

An Arch Linux ARM image for the S21 FE with the same kernel and firmware as postmarketOS, built on the PC
**without sudo** (rootless podman + qemu-user), installed from TWRP into `userdata`, that boots into
Plasma 6.8 with all of pmOS's hardware. Reaching parity meant rebuilding what pmOS gives without it
showing: RTC, sensor rules, zram, a stable MAC, power button handling…

## Context / Goal

The step before the game mode (phase 2): a normal Arch that boots with display, touchscreen, audio,
microphones, Wi-Fi, BT, sensors, USB-C/DP and SSH over USB. Constraint: no sudo on the PC, and nothing
of the owner's configuration is touched.

## Technical decisions

- **Building** (`scripts/build-packages.sh`): `podman import` of the official ALARM tarball, checked with
  md5 and its signature. On top of it an aarch64 "builder" container is created and the packages are
  built in order into a local repository, `work/repo`:
  - Qualcomm services: `qrtr`, `rmtfs`, `tqftpserv` and `hexagonrpcd` (with pmOS's patch);
  - kernel and firmware **repackaged** from pmOS's `.apk` files;
  - `device-samsung-r9q`, which shares UCM, sensor rules, modprobe and `kwinrc` with the pmaports one.
- **A qemu-user lesson:** the setuid bit does not count (binfmt without the `C` flag), so `sudo` inside
  the container fails. Root installs the `makedepends` and the build uses `makepkg -d`. That is why the
  libraries built against must also be in `makedepends`.
- **Image** (`build-image.sh` + `image/setup.sh`):
  - no `linux-aarch64` and no `linux-firmware*` (`NoExtract` for `qca/*` and for WCN6855's `board-2.bin`);
  - Plasma 6.8 with `plasma-login-manager` and `plasma-keyboard`, as in pmOS;
  - PipeWire with `soc-qcom`'s WirePlumber setting;
  - NetworkManager instead of `systemd-networkd`;
  - user, locale and time zone from the pmbootstrap config;
  - the pacman keyring and the host's SSH keys are created on the phone.
  - The ext4 is made with `podman unshare` + `mkfs.ext4 -d`: 4 KiB blocks, **no `orphan_file`** so TWRP's
    5.4 kernel can mount it, and `x-systemd.growfs`.
- **Boot:** a pacman hook (`r9q-bootimg`) that, after every kernel or initramfs change, builds `boot.img`
  and `vendor_boot.img` with the `deviceinfo` values and writes them. mkinitcpio's initramfs only has
  `base systemd modconf fsck`, because UFS and ext4 are built into the kernel: ~14 MB, as in pmOS.
- **USB network:** an NCM gadget through configfs + dnsmasq. The phone is `172.16.42.1` and gives the PC
  `172.16.42.2`.

## First-boot problems and fixes (`device-samsung-r9q 1-1` → `1-11`)

| Problem | Cause | Fix |
|---|---|---|
| Clock in **1970**; `pacman-key` fails ("key from the future") | the PMIC's RTC only counts from its last reset; Android adds an offset to it | `r9q-clock`: stores "real time − RTC" in `/var/lib/r9q/rtc-offset` (after NTP, at shutdown and when updating) and applies it at boot. A udev rule starts it when `rtc0` appears: with the driver as a module, the kernel set 1970 again when loading it. Since kernel `r10` the driver is built in |
| Only the light sensor | upstream's udev rule does not declare `ssc-accel`/`ssc-proximity` | rule 90 from `postmarketos-base-ui` copied |
| "It hangs" | Plasma or the login screen **suspend** and `deep` never resumes | `sleep.conf.d` `AllowSuspend=no` |
| The power button turns the phone off | at the login screen nothing of Plasma handles it: logind powers off; with a cable, the ABL boots into charging mode and it looks like a reboot | `logind.conf.d` (short = ignore, long = power off) + `powerdevilrc` (`PowerButtonAction=128`, screen on/off) |
| pacman does not sync | pacman 7 downloads inside a **Landlock** sandbox the kernel did not have | kernel `r10` with `CONFIG_SECURITY_LANDLOCK=y` (turning the sandbox off was ruled out: it weakens security) |
| Wi-Fi does not reconnect by itself after a reboot | with no MAC in OTP, ath11k makes up a `00:03:7f:12:xx:xx` on every boot, and Steam ties every saved network to that MAC | `r9q-macs` reads Samsung's real MACs from `efs` (mounted `ro,noload`) and `r9q-bootimg` puts them in the DT (`local-mac-address`, `local-bd-address`) |
| Games that slow down until they close | no swap: the game fills the ~5 GB, the kernel drops the programs' code and reads it again, and in the end the OOM killer kills the game | **zram** as in pmOS: 150 % of the RAM with zstd, `vm.swappiness=180`, `vm.page-cluster=0`, `vm.min_free_kbytes=100000` (`1-11`). Tested: the game no longer closes |

## How to run it

```bash
bash scripts/build-packages.sh [package ...]       # local repository in work/repo
EDITION=kde bash scripts/build-image.sh        # or EDITION=steam; work/out/$EDITION/{arch-r9q.img,boot.img,vendor_boot.img}
EDITION=kde bash scripts/check-image.sh        # checks the image with debugfs, without mounting it
EDITION=kde bash scripts/make-twrp-zip.sh      # ZIP for TWRP (Install → USB-OTG or adb sideload) in artifacts/
bash scripts/test-twrp-installer.sh            # tests the ZIP's installer on the PC
EDITION=kde scripts/flash-twrp-adb.sh --yes-erase-userdata   # or over adb from TWRP: ERASES userdata
bash scripts/update-phone.sh [--sync] [pkg…]   # on an installed Arch: pacman -U over SSH and reboot
```

Two editions: `kde` (Plasma with its login screen, no Steam) and `steam` (autologin into the game mode,
Steam already downloaded, Plasma as the desktop mode). The TWRP ZIP carries `rootfs.img.gz` (gzip: TWRP
has `unpigz` but neither zstd nor xz), the boot images, a `manifest.txt` with sizes and SHA-256, and an
`update-binary` that checks everything (model, that the ZIP is not in internal storage, SHA-256) before
writing anything, streams `userdata` and verifies it. It has to stay under 4 GiB (FAT32 USB drive). The
real MACs are applied by themselves on the first boot (one automatic reboot).

`update-phone.sh` also sets the PC's time on the phone if it is behind, and stores the RTC offset. sudo
operations on the phone ask the user for the password: the agent does not use it.

## Results and lessons

- First boot worked the first time: USB network and SSH ~100 s after flashing and Plasma at 31 s; the
  root grows by itself to 104 GB. The full review (`scripts/diagnostics/full-review.sh`, works with apk
  and pacman) shows the same parity as pmOS.
- pmOS hides a lot of integration in generic packages (`postmarketos-base-ui`, `soc-qcom`,
  `postmarketos-zram`, `bootmac`, `swclock-offset`). When changing distributions they have to be gone
  through one by one: zram was missed, and it was why games were closing.
- `deep` suspend was probably the "hang after 3–7 min" chased in pmOS.
- Things that only show when measuring: the race between `r9q-bt-power` and loading the NVM, the RTC going
  back to 1970 when its module loads, or Wi-Fi having a different MAC on every boot.
