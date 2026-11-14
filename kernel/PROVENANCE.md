# Provenance of the kernel sources

The kernel is Linux 7.2.13 from kernel.org (`linux-7.2.tar.xz` +
`patch-7.2.13.xz`, checksums in
`packaging/postmarketos/linux-samsung-r9q/APKBUILD`) with the patches below,
built by pmbootstrap as the postmarketOS package `linux-samsung-r9q`
(`scripts/prepare-pmaports.sh`); the Arch package of the same name repacks it.

Licences, without exception:

| Path | Licence | Reason |
|---|---|---|
| `kernel/drivers/*.c` | `GPL-2.0-only` | Derivative works of Linux |
| `kernel/patches/*.patch` | `GPL-2.0-only` | Derivative works of Linux |
| `kernel/dts/*.dts` | `BSD-3-Clause` | Convention of the upstream Qualcomm DTS |
| `kernel/config/*` | `MIT` | Project configuration |

The device tree is this port's own, built on mainline's `sm8350.dtsi`; the
values it needs (reserved memory, GPIOs, regulators, panel timings, speaker
calibration routing) were read from the phone's stock device tree and kernel
logs, as recorded in `docs/porting-log.md`.

## Patches

| Patch | Origin | SHA-256 |
|---|---|---|
| `0001-soc-qcom-samsung-sec-log-console.patch` | this port | `723718c0cf8ebf41…` |
| `0002-probe-trace-and-sec-log-kconfig.patch` | this port | `6b752fba5ae67929…` |
| `0003-misc-max77705-usb-switch.patch` | this port; CCIC mailbox protocol from the Galaxy Tab S8+ port (aaronsb/sm-x800-linux) | `2998534dbd641bf4…` |
| `0004-mfd-max77705-accept-pass2.patch` | this port | `ae3662386bbc8a1d…` |
| `0005-drm-panel-add-samsung-ea8082.patch` | this port | `971ecf4d5e589042…` |
| `0006-input-add-synaptics-touchcomm-i2c.patch` | Vsevolod Nevorotov, Synaptics TouchComm driver as posted for upstream review (patchwork) | `baca1291e573354d…` |
| `0007-input-synaptics-tcm-i2c-optional-reset.patch` | this port | `cc8b1f6439e9a4d7…` |
| `0008-dmaengine-qcom-gpi-retire-linked-tx-descriptors.patch` | this port | `5f7dd21a80c01535…` |
| `0009-input-synaptics-tcm-i2c-samsung-coordinate-events.patch` | this port | `91f51b1924db1721…` |
| `0010-max77705-charger-otg-regulator.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `19a0075268f4d207…` |
| `0011-max77705-charger-battery-info.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `0dcca0b80738d9fa…` |
| `0012-max77705-charger-otg-shutdown.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `b4f680004b98bcc1…` |
| `0013-max77705-charger-aicl-bounded.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `ebe05993553f34f3…` |
| `0014-max77705-charger-aicl-notify.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `2bb2a3a15e962874…` |
| `0015-max77705-charger-review-fixes.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `833c77312feae820…` |
| `0016-max77705-typec.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `7b05b8fac8736051…` |
| `0017-max77705-typec-source-attach.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `a5559b2f016f16db…` |
| `0018-max77705-typec-prefer-voltage.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `83b9422b1b62285c…` |
| `0019-max77705-typec-review-fixes.patch` | Galaxy Tab S8+ port ([aaronsb/sm-x800-linux](https://github.com/aaronsb/sm-x800-linux), ADR-003), same MAX77705; adapted here | `5356dad97b9283d4…` |
| `0020-max77705-typec-displayport-altmode.patch` | this port | `b87241092db17bc1…` |
| `0021-clk-qcom-gcc-sm8350-gp-clock-ops.patch` | this port | `56d73ff54fa75a9c…` |
| `0022-input-max77693-haptic-max77705-bias.patch` | this port | `88e3c44fdb0435d9…` |
| `0023-asoc-qcom-sm8250-samsung-r9q-cs35l41.patch` | this port | `dc45a6b358fc91c4…` |
| `0024-asoc-cs35l41-cspl-mailbox-irq.patch` | this port | `adcc4363372a3dc3…` |
| `0025-asoc-cs35l41-calibration-first-resume.patch` | this port | `ba8c26cb962fc0d4…` |
| `0026-usb-typec-max77705-module-name.patch` | this port | `221e2ab4a3a48fc6…` |

`kernel/patches/debug/` holds diagnostic patches used during bring-up (trace
points, feature switches); they are not applied by the package.
`kernel/config/debug/` holds the fragments of the test kernels built without
modules or initramfs while bringing up each block.
