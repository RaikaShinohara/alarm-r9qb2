# Galaxy S21 FE (r9q) — boot, kernel and hardware (postmarketOS)

- **Date:** 2026-11-03
- **Status:** done for what is listed here (modem, camera and suspend pending)
- **Project:** galaxy-s21-fe-linux · kernel in `kernel/ (packaging/postmarketos/linux-samsung-r9q)` (7.2.13-r10)

## Summary

How Samsung's bootloader is made to boot a mainline kernel on the SM-G990B2, and what each hardware block
needed in the device tree and in the kernel. This kernel is the same for postmarketOS and for Arch Linux
ARM.

## Context / Goal

SM8350 has good mainline support, but Samsung's phone changes the memory map, protects GPIOs with
TrustZone, uses peripherals with no mainline driver (panel, touchscreen, USB-C CCIC) and its bootloader
(ABL) has quirks of its own. The goal was an own DTS and a series of small patches on top of 7.2.13.

## Technical decisions

### Bootloader (ABL) and partitions

- **Images:** header v3. `boot.img` carries the `Image.gz`; `vendor_boot.img` carries the DTB, initramfs
  and command line. Values: base 0, kernel 0x8000, ramdisk 0x2000000, tags 0x1e00000, dtb 0x1f00000, page
  4096, board `SRPVC21A007`.
- **DTB selection:** the ABL requires the legacy compatibles `qcom,lahaina-mtp`/`qcom,lahaina`/`qcom,mtp`,
  plus `qcom,msm-id = <0x19f 0x20001>, <0x1c8 0x20001>, <0x1f5 0x20001>` and
  `qcom,board-id = <0x10008 0x0e>`.
- **`dtbo`:** the ABL applies Samsung's overlays, which break a mainline DTB. Fix: 4 KiB of zeros at the
  start of the partition, so the header is invalid and the overlays are ignored.
- **"Always back to TWRP":** `adb reboot recovery` sets the first word of `param` to 2 and TWRP does not
  clear it. It must be zeroed, together with the BCB in `misc`, before rebooting. The installers do it.
- **Command line:** the ABL replaces `console=` with `console=null`, so nothing relies on the console.
  Consequence: `systemd-firstboot` is masked.
- **`EFI_ZBOOT` disabled:** the ABL only boots `Image.gz`. With an EFI kernel it went logo → black →
  *watchdog bite*.

### Memory and TrustZone

- Samsung's memory map differs from `sm8350.dtsi`: PIL regions (adsp, modem, camera, slpi…), dynamic
  rmtfs and regions of its own (`splash_region` 0xe4000000, ramoops 0xf0b00000, sec_debug…). See
  `info/reserved-memory-downstream.txt`.
- **Reserved GPIOs:** 17–19 and 52–59. Touching 52–59 hangs the SoC.
- **The APSS watchdog is not touched:** its MMIO raises an SError.
- **`qcrypto` blacklisted:** the crypto engine belongs to TrustZone and the SoC freezes ~40 s later. The
  `crypto`/`cryptobam` nodes must **stay enabled** in the DT; without them it freezes too.
- **LDO7C** at 3.304 V: 3.3 V is not on the regulator's grid and brought the whole PM8350C down.

### Hardware blocks

| Block | What it needed |
|---|---|
| EA8082 display (DSI0, command mode, DSC 1.1) | own driver (`0005`) with the power-on sequence from Samsung's DTBO (mainline's PPS comes out identical byte for byte); 60/120 Hz (`panel_samsung_ea8082.refresh_rate`); 10-bit brightness; `deferred_probe_timeout=60` so msm does not bind without `gpucc` |
| Adreno 660 GPU | `&gpu` + Samsung's zap shader joined from `.mdt/.bNN` (`scripts/squash-mdt.py`); SQE/GMU from linux-firmware |
| S3908 touchscreen | linux-input's TouchComm v2 series (`0006`), optional reset (`0007`), a fix for the GPI DMA that did not release TX (`0008`) and Samsung's 0xC1 report instead of the standard 0x11 (`0009`); `&gpi_dma0` enabled |
| USB | the XBL leaves the MAX77705 MUIC switch with D+/D− open → `max77705-usb-switch` (`0003`) sets it to USB through the CCIC mailbox |
| MAX77705 battery/charging | accept the PASS2 revision (`0004`); `simple-battery` 4500 mAh with a **conservative** 4.35 V limit |
| USB-C (MAX77705 CCIC) | patches `0010`–`0019` from the Galaxy Tab S8+ port (typec DRP, role switch, OTG, PD ≤ 9 V); `0026` renames the module to `max77705_typec`: it clashed with the built-in MFD, and without it there was no display |
| HDMI (DP Alt Mode) | own patch `0020`: Enter Mode and DP Configure through the CCIC mailbox with the same bytes as the stock kernel; `gpio-sbu-mux` (GPIO15/16) |
| QCA6490 Wi-Fi | `wcn6855-pmu` (pwrseq) + PCIe0; **Samsung's firmware** (WLAN.HSP.2.0), because linux-firmware's hangs with its calibration; `firmware-name = "samsung-r9q"`; no generic `board-2.bin` |
| QCA6490 Bluetooth | UART18 (GPIOs 68–71, which were not protected) on the same PMU; firmware: see the Arch phase 2 document |
| Audio | `0023`: `samsung,r9q-sndcard` card in the sm8250 driver (Primary MI2S, 2× CS35L41 on I²C5); `0024`: the DSP's IRQ for the mailbox; `0025`: factory calibration before the first RESUME; UCM with `DSP RX2 Source = ASPRX1` and 6.5 dB |
| Microphones | 2 DMICs on the LPI pins through the **VA macro** (mainline's TX macro does not generate its clock) |
| Vibration | GCC's GP2 as PWM (`0021`), `BIASEN` in the MAX77705 (`0022`), motor supply through GPIO198 |
| DSPs | ADSP/CDSP/SLPI with Samsung's firmware; L2C 1.8 V (`sensor_vdd`) always on, or the SLPI crashes |
| Scheduler | stock `capacity-dmips-mhz` and `dynamic-power-coefficient`, `epss_l3` + OPPs with L3/DDR votes |

## How to run it

```bash
# test kernels (everything =y, no modules) from src/linux-7.2.13, flashed from TWRP
# (pmOS-phase test kernels: development-tree tools, not included)
# pmOS packages (kernel, device, firmware); Arch uses them too
bash scripts/prepare-pmaports.sh && pmbootstrap build linux-samsung-r9q
```

The patches are in `kernel/patches/` and the config in `kernel/config/config-samsung-r9q.aarch64`
(regenerated with `olddefconfig` on the patched tree, with a separate `KCONFIG_CONFIG` so the tree's
`.config` is not touched). Since `r10`: `CONFIG_SECURITY_LANDLOCK=y` (pacman 7 needs it) and
`CONFIG_RTC_DRV_PM8XXX=y`.

## Results and lessons

- To debug boots that die without a console:
  - `/proc/last_kmsg` in TWRP: Samsung's `sec_log` buffer from the previous boot, with a persistent
    console thanks to patch `0001`;
  - `initcall_debug` + the "probing X with driver Y" trace (patch `0002`): the last line points at the
    culprit;
  - the XBL's reset history (`Warm Reset by Watchdog Bite`).
- pstore only survives if Linux reboots itself: a *watchdog bite* wipes the RAM.
- Test kernels with everything built in **do not test module loading**. The `max77705` name clash only
  showed up in the packaged build.
- Measure before calling something good:
  - the bottom speaker "worked" according to the logs, but was silent; an acoustic test with the
    microphones (a 1 kHz tone and Goertzel) uncovered it;
  - the gain was tuned by reading the protection firmware's telemetry.
- Most fixes already existed in sibling ports (Tab S8+, Tab S9, S22) or in Samsung's stock kernel.
  Reading them saved days.
