# Agent instructions

## Project scope

This repository builds Arch Linux ARM (aarch64) with Plasma 6, and optionally
Steam's game mode, for the Samsung Galaxy S21 FE 5G (`SM-G990B2`, `r9q`,
SM8350), on a mainline Linux 7.2.13 kernel first ported with postmarketOS.

Keep changes within the existing architecture:

- `kernel/`: kernel configuration, DTS, drivers and patches.
- `packaging/`: Arch Linux ARM PKGBUILDs (`packaging/<package>/`) and the
  postmarketOS packages (`packaging/postmarketos/`) the kernel is built from.
- `configs/`: image setup, the TWRP installer, boot configuration and the
  dual boot selector (`configs/dualboot/`).
- `scripts/`: reproducible build, deployment and test tooling;
  `scripts/diagnostics/` runs on the phone.
- `docs/`: current status, engineering conclusions and validation evidence.
- `work/` and `artifacts/`: generated or temporary data, never the definitive
  source of a fix.

Do not update the base kernel, distribution or another foundational component
incidentally while fixing an unrelated issue.

## Required reading

Before changing code, read:

1. `README.md`
2. `docs/hardware-status.md`
3. `docs/development-notes.md`
4. `docs/boot-strategy.md`
5. `docs/archlinuxarm-userspace.md`
6. the documentation for the affected component
7. relevant entries in `docs/porting-log.md` (section 0 lists every boot
   blocker that was solved, with its fix)

Newer evidence supersedes older hypotheses. Check the current code before
reusing a historical conclusion.

## Engineering method

1. Record the baseline.
2. Reproduce one concrete failure.
3. Capture only the logs and measurements needed (`scripts/diagnostics/`).
4. Identify the cause before modifying code.
5. Apply the smallest fix at the responsible layer.
6. Repeat the original reproduction exactly, then check related regressions
   and persistence across a reboot.

Always distinguish measured facts, hypotheses, and behavior confirmed on the
physical phone. Compilation, driver binding and package installation are not
physical validation.

## Build environment

Everything runs on an x86_64 Linux PC: rootless podman with qemu-user
(`binfmt` for aarch64) for the Arch packages and image, no sudo. Under
qemu-user setuid is ignored, so `scripts/build-packages.sh` installs
`makedepends` as root and runs `makepkg -d`; a library a package compiles
against must also be listed in `makedepends`.

The kernel and firmware come from the postmarketOS packages in
`packaging/postmarketos/`, built with `pmbootstrap`; the Arch packages
`linux-samsung-r9q` and `firmware-samsung-r9q` repack those `.apk` files.

Do not edit a script while it is running: Bash reads it incrementally.

## Kernel and boot invariants

The Samsung ABL boots Android boot header v3:

- `boot`: gzip kernel only, no ramdisk;
- `vendor_boot`: DTB, initramfs and the cmdline (`configs/vendor_boot/`);
- `dtbo`: its first 4 KiB are zeroed so the ABL applies no Samsung overlays;
- `param` word 0 and the `misc` BCB are cleared, or the phone keeps booting
  TWRP.

`r9q-bootimg` (device package) rebuilds both images after every kernel or
initramfs change and injects the real MAC addresses into the DTB.

Hard rules found the hard way (see `docs/porting-log.md`, section 0):

- `qcrypto` is TrustZone's: keep it blacklisted, but keep `crypto`/`cryptobam`
  enabled in the DT, or the SoC freezes about 30 s after boot.
- GPIO 52–59 (and others in `gpio-reserved-ranges`) belong to TrustZone.
- `rmtfs` runs with `-r` and never `-s`: the modem is not booted.
- MAX77705: no CCIC firmware update path, no PPS/APDO, fixed PDOs up to 9 V
  only, never enable the OTG boost while a charger is connected.
- Never install linux-firmware's `qca/` Bluetooth files or the generic
  WCN6855 `board-2.bin`.

Never write the bootloader, `efs`, `sec_efs`, `vbmeta`, `super`, `recovery`,
modem or calibration partitions. `efs` is only ever mounted `ro,noload`.
The one exception is the dual boot release installer
(`configs/twrp/dualboot-update-binary`): by design it installs the fixed TWRP
(`scripts/make-twrp-fix.sh`) in `recovery`, read back after writing.

## Packaging and updates

A live-phone change is diagnostic only until it is in this repository. Every
fix must reach both clean installations (the image) and existing ones (a
package with a higher `pkgrel`).

Do not hardcode account names, UIDs, IP addresses other than the USB link
(`172.16.42.1`), home directories or local build paths in shipped code.

## Phone access

Over USB the phone is `172.16.42.1` (NCM gadget + DHCP). Verify the SSH host
key before sending credentials. Do not store passwords, private keys, MAC
addresses, serial numbers or personal information in code, documentation,
test output or shared logs.

## Safe deployment

Obtain explicit authorization before any operation that writes a partition,
restarts the display manager or reboots the phone. Resolve partitions through
`/dev/block/by-name/` (TWRP) or `/dev/disk/by-partlabel/` (Linux); never
hardcode `sdX`. Exception: the storage split works on the GPT of the UFS disk
`sda` itself, and partitions it has just created have no `by-name` link until
the next boot, so it opens them through their sysfs device numbers. Check sizes and hashes before writing and read the result back.
If any step fails, do not reboot: preserve logs and report.

## Test and verification policy

Read every test before running it; diagnostics may change power, display or
peripheral state.

```sh
bash -n <changed-shell-scripts>
python3 -m py_compile <changed-python-files>
bash scripts/test-twrp-installer.sh          # after touching the installer
EDITION=kde bash scripts/check-image.sh      # after building an image
```

## Documentation and completion

Update the current status and append chronological evidence to
`docs/porting-log.md`: root cause, changes, package versions, tests run,
physical observations and skipped checks. Do not mark a component complete
while physical validation is missing.
