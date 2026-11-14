# Generated artifacts

This directory is deliberately empty in Git. The TWRP zips, the root and boot
images and the build logs are regenerable products, they are large and they
contain proprietary firmware. They are never committed: releases publish the
zips as GitHub Release assets.

Each build leaves here, locally:

- `scripts/make-twrp-zip.sh`: `r9q-arch-<edition>-<date>.zip` with its
  `.sha256`; inside, `rootfs.img.gz`, `boot.img`, `vendor_boot.img`,
  `manifest.txt` (sizes and SHA-256 of everything) and the installer;
- `scripts/build-release.sh`: `release/archlinuxarm-<edition>-sm-g990b2-v<VERSION>.zip`,
  the public images (user `alarm`, password `alarm`, no SSH keys).
