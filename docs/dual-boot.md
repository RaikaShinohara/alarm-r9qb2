# Galaxy S21 FE (r9q) — Android + Linux dual boot, Xiaomi Pad 5 style (UEFI)

- **Date:** 2026-11-11 (updated 2026-11-14)
- **Status:** working (Android and Arch Linux side by side with a UEFI boot menu; Linux on the whole storage, or removed again)
- **Project:** galaxy-s21-fe-linux · `configs/dualboot/` (selector, Reboot2Android) and `scripts/dualboot-patch.py`

## Summary

A boot menu to choose Android or Arch Linux, with the same mechanism as the Xiaomi Pad 5 Linux
projects: Android's `boot.img` carries, inside its kernel, a selector of a few instructions and the
Mu-Silicium UEFI. On every power-on the UEFI starts (systemd-boot menu: Arch, Android); "Android" leaves a
mark in RAM and resets, and the selector, seeing the mark, boots Android's kernel with everything
Samsung's bootloader has prepared. Tested on the phone: the mark survives the reset, the selector sees it
and clears it, and the menu comes back on the next reboot.

## Context / Goal

- Android and Linux on the same phone, the storage split between them, and a menu at boot.
- Without touching the bootloader (ABL), `efs` or the modem: if something fails, Vol+ and Power bring
  back TWRP and `boot` is restored. `recovery` was changed only once, to fix TWRP (see below).
- Android's kernel takes 52 MB and the `boot` partition 96 MiB: the second system has to be small (the
  UEFI, 3 MiB), not our kernel (56 MB).

## Technical decisions

- **The Pad 5 mechanism** (Project-Aloha's DualBootKernelPatcher, the "boot manager" variant of
  rodriguezst/nabu-dualboot-img): Samsung's ABL keeps booting Android's `boot.img` with its `vendor_boot`
  and its `dtbo`; only 127 bytes of its kernel header change and the UEFI is appended.
- **UEFI**: Mu-Silicium **v3.0.1**, which boots on this phone's bit F bootloader. The one built from
  `main` (`r9qb2`, marked "Inactive" and asking for BIT-18) hangs in UFS and ends in *Warm Reset by
  Watchdog Bite*. The official v3.0.1 file is a DEBUG build that prints its log on the screen; since
  v1.2.0 the release carries v3.0.1 built in RELEASE mode from the
  [fork](https://github.com/RaikaShinohara/Mu-Silicium/tree/r9q-dualboot), with this port's RAM and MMU
  fixes in the source (a rebuild gives the same bytes).
- **Own selector and patcher** (`shellcode-r9q.S`, `dualboot-patch.py`): the same header format as
  DualBootKernelPatcher (branch to `0x40`, FD base/size and kernel size at `0x20/0x28/0x30`, FD appended),
  written for this port because downloaded code is not run. When jumping to the UEFI it leaves the
  registers as the official BootShim does.
- **Own Reboot2Android** (`reboot2android.c`, AArch64 PE without libraries, clang + lld-link):
  - reserves the mark's page with `AllocatePages` (Project Mu does not map free memory: writing without
    reserving raises an exception with no message);
  - fills the page at **`0x17FE00000`** (the Pad 5's address; no DT reserves it here) with a 4 KiB
    pseudo-random pattern (xorshift64), with the MMU and the cache off;
  - resets with **PSCI `SYSTEM_RESET`**, calling TrustZone directly: the UEFI's warm reset is not
    implemented and its cold reset clears the RAM.
- **The selector compares the page bit by bit** and boots Android if fewer than 3/8 of the bits differ.
  Every reset of this phone is a PMIC *hard reset* (the XBL log in `/proc/last_kmsg` says so): DRAM goes
  without refresh for a moment and some bits change, more so with a warm phone. With a 64-bit mark
  compared whole, "Android" needed 2 or 3 presses.
- **Linux through the UEFI**: systemd-boot, an uncompressed kernel (the EFI stub needs a PE),
  `devicetree` and `acpi=off`. Mu creates boot options from any FAT with `\EFI\BOOT\BOOTAA64.EFI`.

## Installation

One ZIP per edition (`archlinuxarm-kde-dualboot-sm-g990b2-vX.Y.Z.zip` or `archlinuxarm-steam-dualboot-sm-g990b2-vX.Y.Z.zip`, from TWRP; `configs/twrp/dualboot-update-binary`)
does everything, with a menu on the volume keys and Power:

- **Linux 25 / 50 / 75 %** beside Android: splits the old `userdata` area into `userdata` (Android), `esp`
  (512 MiB FAT32) and `linux` (ext4) with one `sgdisk` call, without a reboot (TWRP's kernel learns about
  the new table through BLKPG, `r9q-tool`), and adds the selector and the UEFI to Android's own `boot`;
  the stock `boot` is kept in the ESP.
- **Linux 100 %**: `userdata` keeps a 256 MiB stub and `boot` holds only the selector and the UEFI.
- **Keep** the current split: Android is not touched, Arch is reinstalled.
- **Remove Linux: Android 100 %**: Android's own `boot` back, `esp` and `linux` deleted, `userdata` over
  the whole storage again and formatted.

Arch (`DUAL=1`) goes to `linux` and its files to the ESP (uncompressed kernel, initramfs, DTB with the
real MACs, entry `root=PARTLABEL=linux acpi=off`). On the system, `BOOT_MODE=uefi`: every kernel or
systemd-boot update goes to the ESP, never to `boot`.

Result: a menu with **Arch Linux ARM** (default) and **Android**; both boot and come back to the menu.

## How to run it

```bash
make -C configs/dualboot            # selector and Reboot2Android.efi
# patch Android's boot.img (header v3/v4) with the selector and the FD
python3 -I scripts/dualboot-patch.py patch boot.img R9Q_UEFI.fd \
    configs/dualboot/shellcode-r9q.bin boot-dualboot.img
# Linux 100 %: the selector and the FD alone, with the header and ramdisk of BOOT.img
python3 -I scripts/dualboot-patch.py patch-uefi boot.img R9Q_UEFI.fd \
    configs/dualboot/shellcode-r9q.bin boot-uefi.img
python3 -I scripts/dualboot-patch.py info boot-dualboot.img
EDITION=steam bash scripts/make-dualboot-release.sh   # the release ZIP (EDITION=kde or steam)
bash scripts/test-dualboot-release.sh     # its installer in a sandbox of TWRP's own tools
```

## Results and lessons

- **Works**: power-on → UEFI → Arch; "Android" → mark + `SYSTEM_RESET` → the selector boots the kernel
  the ABL prepared; reboot → menu again. Arch through the UEFI: display, GPU, Wi-Fi, Bluetooth, audio,
  DSPs and battery.
- **What failed along the way**, each thing hidden behind the previous one:
  - the UEFI from `main` is not the one that worked: use the v3.0.1 release;
  - `mkfs.fat` with 4 KiB sectors needs `-s 1` (otherwise EDK2 reads the FAT32 as FAT16);
  - writing the mark without reserving the page: exception;
  - `EfiResetWarm` returns and stops at `ASSERT (FALSE)`;
  - the end of ramoops (`0xF0BFFFF0`) is overwritten by the firmware and TWRP with their logs;
  - a warm `SYSTEM_RESET2` keeps the RAM but leaves the hardware half done: whatever boots next hangs.
    `SYSTEM_RESET` keeps the RAM and leaves it clean;
  - with the MMU fix, writing the mark through the UEFI's page tables fails: it is written with the MMU
    off (cleaning that code to DRAM first);
  - a 64-bit mark does not always survive the *hard reset*: a whole page and a comparison that tolerates
    flipped bits are used. Setting the PMIC to a "warm" reset over SPMI did not help: TrustZone asks for a
    *hard reset* again.
- **Diagnosis** that made it clear: measuring from the PC how many times it went round the menu (the PC's
  time minus Android's `/proc/uptime`: ~31 s per round) and reading each reset's type in the XBL log
  (`/proc/last_kmsg` in TWRP: `Reset Type: Hard Reset`).
- **RAM**: the official UEFI's memory map did not declare ~870 MiB that Samsung's bootloader does give
  the kernel. Four entries the UEFI does not need now declare the four largest free ranges (the
  bootloader's RAM minus all of our DT's reservations): Linux goes from 4.2 to **4.92 GiB**.
- **Hang after a software restart** (Linux, Android or TWRP, with USB connected): `ArmCpuDxe` died
  splitting a memory block "with the MMU disabled" (the CPU could not execute when it came back).
  ArmMmuLib no longer does that split: the block keeps its attributes.
- **Fixed TWRP** (`scripts/make-twrp-fix.sh`, from the original TWRP; the files are in the
  [TWRP device tree fork](https://github.com/RaikaShinohara/twrp_device_samsung_r9q/tree/r9q-dualboot)):
  - *leaving TWRP came back to TWRP*: the ABL marks "enter recovery" in `param` every time it enters and
    only Samsung's recovery clears it. A small TWRP service clears that mark (and the `boot-recovery` in
    `misc`) every 3 s;
  - *it stayed at the logo*: with Android encrypted, TWRP waited forever for the `weaver` service, which
    its service list declares but does not exist. It is removed from the list: TWRP cannot decrypt, says
    so and shows the menu (Android's `/data` unmounted; Arch does not need it).
  Only files are added to the ramdisk; kernel and header unchanged. Tested.
- **Bugs that only showed on the phone**: `blkpg del` with empty arguments; TWRP's device-mapper over
  `userdata` ("In use by the system", now removed with `r9q-tool dmremove`); TWRP's `unzip` holding a whole
  entry in RAM (kernel panic with the ZIP in `/tmp`: the system image is now read straight from the ZIP);
  and a false "writing linux failed" from `tail` ending with SIGPIPE.
- **Stuck at the Samsung logo over LineageOS** (Android and Linux alike): its `boot` is signed only with
  AVB, with the vbmeta right after the image and the footer (last 64 bytes of the partition) pointing at
  it. The dual boot image is longer and overwrote that vbmeta; Samsung's ABL read the UEFI's bytes as
  vbmeta and crashed (`DXE_ASSERT` in `String.c`, in `/proc/last_kmsg`). The installer and
  `dualboot-patch.py` now move the vbmeta after the new image and point the footer at it (as `avbtool`
  lays it out); *Remove Linux* puts both back as they were. Kernels shipped compressed (`Image.gz`,
  `Image.lz4`, `.bz2`, `.xz`) are unpacked (LZ4 by `r9q-tool unlz4`: TWRP has no lz4), and this port's own
  kernel is told apart by its `pmos@` build string instead of its version.
- **ZIP in internal storage**: the installer unmounted `userdata` before writing and lost its own ZIP
  ("verifying linux failed"). *Keep* now leaves `userdata` mounted; the options that format it refuse to
  run from there before writing anything.
- **Tested on the phone**: "Android" at the first press 13/13; the stock `boot` → dual boot → reinstall
  over it (same `boot` byte for byte); dual → Linux 100 % → Remove Linux; Arch booting end to end through
  the RELEASE UEFI 6/6 (with a test entry that makes Arch reboot itself into recovery).
