# Arch Linux ARM on the S21 FE (r9q) with an Armada-style Steam session — plan

Goal: install from TWRP an **Arch Linux ARM (aarch64)** image that uses the same kernel and firmware as
the postmarketOS port and boots straight into **Steam Big Picture (game mode, gamescope)**, with
**Plasma as the desktop mode** and switching between them from Steam, as in
[Armada](https://github.com/armada-os/armada). Everything must be ready in the image: no manual steps
after installing.

## 1. How Armada does it (and what we copy)

Armada is Fedora bootc + ROCKNIX's device support. What matters for us:

| Piece | Armada | Here |
|---|---|---|
| Steam client | **Valve's native arm64 client** (the Steam Frame one): the `steam_client_steamdeck_publicbeta_linuxarm64` manifest on `client-update.steamstatic.com` + the arm64 `steamrt3c` runtime (`repo.steampowered.com/steamrt3c/images/<ver>/steam-runtime-steamrt-arm64.tar.xz`), preinstalled in `~/.local/share/Steam` | the same: downloaded at build time (not redistributed) and left in the user's home |
| Session | `gamescope` (patched for aarch64), `gamescope-session` + `gamescope-session-steam`, `steamos-manager`, `jupiter-hw-support` | `gamescope` 3.17 from `extra` (ALARM); `gamescope-session(-steam)` and `steamos-manager` from the AUR or packaged here |
| x86 | FEX + an Arch x86 rootfs, x86 Mesa | `fex-emu` from the AUR (not in ALARM) + an x86 rootfs (phase 3) |
| Windows games | Proton ARM64 (proton-cachyos arm64 / Valve's Proton 11 ARM64) | Valve's Proton ARM64 from Steam itself; proton-cachyos optional |
| GPU | own Mesa | `mesa` + `vulkan-freedreno` (Turnip) from `extra` (26.2.6) |
| Boot | systemd-boot/OpenABL, EFI | **does not apply**: Samsung's ABL only boots `boot.img` v3 + `vendor_boot` (see §2.1) |

## 2. Architecture on the r9q

### 2.1 Boot
- Samsung's ABL → `boot` (`Image.gz`, header v3) + `vendor_boot` (DTB + initramfs + command line);
  `dtbo` with 4 KiB of zeros; `param`/`misc` cleared (rows 1–4 of docs/porting-log.md). The same as now.
- Initramfs: **mkinitcpio** (UFS, PHY, the MAX77705's I²C are already built into the kernel; `ext4`).
- Root: **ext4 straight on `userdata`** (`root=PARTLABEL=userdata rw rootwait`), without pmOS's image
  with subpartitions. The image is written to `userdata` and grown (`resize2fs`) on the first boot.
- A pacman hook (like `boot-deploy`): after a kernel or initramfs update, `mkbootimg` (from
  `android-tools`) builds `boot.img`/`vendor_boot.img` with the `deviceinfo` values and writes them with
  `dd` to their partitions.
- Reminder: the ABL forces `console=null`; nothing may depend on the console.

### 2.2 Kernel and firmware
- The same kernel: `linux-samsung-r9q` (7.2.13 + patches `0001`–`0026` + DTS + config) as an Arch
  package. Built on the PC with clang (as today); the PKGBUILD packages `Image.gz`, the DTB and the modules
  in `/usr/lib/modules/<ver>`; `/usr/lib/modules/<ver>/pkgbase` for mkinitcpio.
- Firmware: a package with the same files as `firmware-samsung-r9q-*` (DSPs, Samsung Wi-Fi, Adreno zap,
  CS35L41, hexagonfs). ALARM's `linux-firmware-qcom` for `a660_sqe/gmu`; **no** `linux-firmware-qca`
  (Bluetooth from ROM) nor generic `ath11k` (row 15).

### 2.3 Services and device configuration (what pmOS gives today)
| What | How in Arch |
|---|---|
| `rmtfs -r -P` (read-only EFS), `tqftpserv` | ALARM packages if they exist, otherwise an own PKGBUILD; rmtfs drop-in |
| `qrtr`, `pd-mapper` | in the kernel (already) |
| Sensors | `hexagonrpcd` with our patch `0001`, `libssc`, `iio-sensor-proxy`; udev rule + drop-in (row 27) |
| Audio | PipeWire + WirePlumber; our UCM (rows 22, 25) |
| Bluetooth | `bluez`; without bootmac: `rfkill unblock` when `hci0` appears (row 28) |
| Wi-Fi | NetworkManager; stable MAC (a bootmac-like script for Wi-Fi only) |
| `qcrypto` | `blacklist qcrypto` (row 13) |
| USB network for debugging | NCM gadget through configfs + `172.16.42.1` + a minimal DHCP server + `sshd` with the PC's key |
| ModemManager | not installed (modem not started) → the uim-selection drop-in is not needed |
| CPU | EAS/L3/OPP come in the DT; `cpupower` is not needed |

### 2.4 Sessions
- Manager: **plasma-login-manager** (the same as pmOS with systemd; phase 1 without autologin, with the
  on-screen keyboard) → in phase 2, autologin of the user into `gamescope-session-steam` (game mode by
  default).
- "Switch to Desktop" in Steam → `steamos-session-select plasma` switches the autologin to Plasma
  (Wayland) and restarts the session; in Plasma, a "Back to Game Mode" shortcut does the opposite.
- Portrait display (1080×2340): gamescope with `--force-orientation` to landscape, touchscreen rotated
  with the same matrix; 120 Hz (`panel_samsung_ea8082.refresh_rate=120`); lower internal resolution + FSR
  for games. In Plasma, automatic rotation with `iio-sensor-proxy`.
- Controllers: Bluetooth (LE works with the ROM) and USB OTG; the touchscreen works for Big Picture.

### 2.5 Steam
1. arm64 client: at build time, download and verify the `..._linuxarm64` manifest of the pinned version
   and its packages, plus the arm64 `steamrt3c` runtime; extract them into
   `/home/<user>/.local/share/Steam`. The client updates itself afterwards.
2. `gamescope-session-steam` runs `steam -gamepadui -steamos3` inside gamescope.
3. Valve's Proton ARM64 (the client itself offers it); arm64 `proton-cachyos` as an alternative.
4. FEX (AUR `fex-emu`) + an Arch x86 rootfs for x86 Linux games (phase 3).

## 3. Building and installing

- Without sudo, with rootless podman + qemu-user (binfmt `PF`), starting from the official tarball
  `ArchLinuxARM-aarch64-latest.tar.gz` (checked with its signature, in `scripts/dl/`):
  - `scripts/build-packages.sh`: builds `packaging/*` in an aarch64 container → local repository
    `work/repo` (`qrtr`, `rmtfs`, `tqftpserv`, `hexagonrpcd`; kernel and firmware repackaged from pmOS's
    `.apk` files; `device-samsung-r9q`, which shares UCM/rules/drop-ins with the pmaports one).
  - `scripts/build-image.sh`: a container from the tarball → `image/setup.sh` (packages, user and password
    as in pmOS, services, locale) → `podman unshare` + `mkfs.ext4 -d` → `work/out/` (`arch-r9q.img`,
    `boot.img`, `vendor_boot.img`, `SHA256SUMS`).
  - `scripts/update-phone.sh`: updates packages on the phone without TWRP (`pacman -U`; the hook rebuilds
    and writes `boot`/`vendor_boot`).
  - Note: the PC's podman storage is on an external disk shared with another project; only the
    `alarm-r9q:*` images and the `r9q-arch-rootfs` container are added there.
- Heavy AUR packages under qemu (FEX in C++, `steamos-manager` in Rust): either built natively on the
  phone after the first boot and the packages kept for the next image, or postponed to phase 3.
- `scripts/flash-twrp-adb.sh` from TWRP: like `flash-pmos.sh` (uploads in chunks, `dd` to `userdata`,
  SHA-256, `boot`/`vendor_boot`, `dtbo` zeroed, `param`/`misc` cleared). **It erases pmOS** (`userdata`);
  the pmOS images stay in the development tree to go back.

## 4. Phases
0. **Blocking**: the hang after 3–7 min with the kernels that have EAS/L3 (log 2026-11-02). Arch would
   use the same kernel.
1. An Arch that boots on par with pmOS: display, touchscreen, audio, microphones, Wi-Fi, BT, sensors,
   USB-C/DP, USB network + SSH, Plasma.
2. Game mode: gamescope-session-steam + the arm64 Steam client preinstalled + autologin + mode switching +
   rotation + controller.
3. Proton ARM64 / FEX / x86 rootfs, `steamos-manager`, MangoHud, per-game settings.

## 5. Risks
- The arm64 client is the Steam Frame beta (officially only for it); it may ask for SteamOS pieces
  (`steamos-manager`, `jupiter-hw-support`) for quick menu features. Armada shows it works outside the
  Frame.
- gamescope with a portrait panel and a rotated touchscreen on Adreno/msm (Armada uses a patched
  gamescope).
- Performance: Adreno 660 with Turnip does well natively/with DXVK; FEX adds CPU cost.
- Space: Steam + runtime + Proton take several GB (there are 100 GB).
- Licenses: the Steam client is downloaded from Valve at build time; the image is not published.
