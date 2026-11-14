# postmarketOS on the Samsung Galaxy S21 FE (r9q) — porting log

> **Paths.** This log was written in the development tree; here the paths already follow this repository's layout (`scripts/`, `packaging/`, `kernel/`, `configs/`). The `port/…` paths left are tools from the postmarketOS phase (test images, pmOS flashing) that are not included.

Status (2026-11-02): **postmarketOS ("Nura edge") with Plasma Desktop is in daily use** with mainline
kernel 7.2.13. On the phone: rootfs `r6` + test kernel #38 (built on the PC, with rows 18–24 inside the
kernel). The `r7` packages already carry everything, but **have not been built yet**:
`linux-samsung-r9q 7.2.13-r7` (patches `0001`–`0025`), `device-samsung-r9q 1-r7`,
`firmware-samsung-r9q 1-r5`. It was checked that this patch series on a clean 7.2.13 gives exactly the
tested tree (only a debugging `pr_info` in `pinctrl-msm.c` is left over).

Works: display with its own driver (EA8082, DSC, brightness, 120 Hz), Adreno 660 GPU (Mesa freedreno,
OpenGL ES 3.2), touchscreen, Wi-Fi, USB network (SSH at 172.16.42.1), UFS, 8 CPUs, CPUfreq, thermals,
RTC, buttons (power/vol±), battery and charging, sensors (SLPI), USB-C OTG/automatic role/PD, HDMI output
(DP Alt Mode), Bluetooth, vibration, **both speakers** (stereo) with Samsung's protection and calibration
and **both microphones**. The Plasma login takes ~4 s.
Not done: modem/telephony, camera, the Wi-Fi's real MAC.

Known detail: `systemd-firstboot.service` fails ("Failed to set up standard input") because the ABL
forces `console=null`; it is harmless (pmbootstrap already sets up locale/user).

## 0. Summary: what it took to boot

| # | Problem | Symptom | Fix |
|---|---|---|---|
| 1 | `adb reboot recovery` leaves `param[0]=2` | always boots TWRP | zero the first 4 bytes of `param` (+ the BCB in `misc`) |
| 2 | The ABL applies the overlays of Samsung's `dtbo` | — | 4 KiB of zeros at the start of `dtbo` |
| 3 | The ABL picks the DTB by `qcom,msm-id`/`board-id` + legacy compatibles | — | added to the DTS |
| 4 | The ABL replaces `console=` with `console=null` | no text | `CONFIG_CMDLINE_FORCE` in test builds |
| 5 | GPIOs 52–59 (and 16–19, 68–71) belong to TrustZone | hang at `probing f100000.pinctrl` → watchdog bite | `gpio-reserved-ranges` |
| 6 | `qcom-wdt` through MMIO | SError | node removed (the watchdog does not bite without TZ faults) |
| 7 | LDO7C at 3.3 V is not on the 8 mV grid | the whole PM8350C goes down → UFS/USB `-EPROBE_DEFER` | 3.304 V |
| 8 | `dispcc` reprograms PLLs and lets MDSS turn off | logo → "weird things" → black | `&dispcc { status = "disabled"; }` + framebuffer with `power-domains = <&rpmhpd RPMHPD_MMCX>`, `required-opps = <&rpmhpd_opp_nom>` |
| 9 | Alpine's busybox without `telnetd`/`udhcpd` | ping yes, telnet no | `nc -lk -p 23 -e /bin/sh` |
| 10 | The XBL leaves the MAX77705's MUIC switch at `CTRL1 = 0x3f` (D+/D− open) | USB does not show up until replugged | driver `max77705-usb-switch` (patch `0003`, `drivers/misc`): through the CCIC mailbox (I²C `0x25` on `i2c7`/QUP SE7, opcode `0x06`) it sets `CTRL1 = 0x09` (COM_USB) at boot. Log: `MUIC CTRL1 0x3f -> 0x09`. Protocol taken from the Tab S8+ port (`aaronsb/sm-x800-linux`) |
| 10b | Battery and charging (MAX77705: `pmic@66`, `charger@69`, `fuel-gauge@36` on `i2c7`, IRQ = PM8350C GPIO5) | mainline's MFD driver rejects the chip's revision (`Rev.0x2 is not tested`) | patch `0004` accepts PASS2; drivers built in; `simple-battery` 4500 mAh with a **conservative 4.35 V** limit (Samsung uses 4.42 V) and 500 mA. Tested: 97 %, 4.33 V, 32.5 °C, USB charger online |
| 11 | pmOS's generic config enables `CONFIG_EFI_ZBOOT` (kernel = EFI executable) | pmOS: logo → black → *watchdog bite*, not a single line of Linux | `# CONFIG_EFI_ZBOOT is not set` (the ABL only boots `Image.gz`) |
| 12 | systemd applies `kernel.printk = 4 4 1 7` | the persistent console stops getting messages at ~5.8 s | `ignore_loglevel` on the command line when debugging |
| 13 | **`qcrypto`**: the crypto engine (`crypto@1dfa000`) and its BAM (`dma-controller@1dc4000`) belong to TrustZone | pmOS reaches the login and freezes after ~30–40 s (TZ → *watchdog bite*) | **Only** `blacklist qcrypto`; `crypto`/`cryptobam` must **stay enabled** in the DT (r2 disabled them and then every boot froze after ~30 s; fixed in `pkgrel=3`). Found with `port/modtest/` (loads module by module and survives reboots): `qcom_stats`, `qcom_refgen_regulator`, `llcc_qcom`, `qcom_rng`, `qcomtee` → OK |
| 14 | LPASS LPI pinctrl and GMU/GPUCC/adreno_smmu stay in `-EPROBE_DEFER` without audio/GPU | (risk when the *deferred probe timeout* expires) | disabled in the DTS until audio/GPU work (GPU enabled since row 17; LPI pinctrl enabled since row 25) |
| 15 | QCA6490 Wi-Fi (WCN6855 family, `17cb:1103`, subsystem `17cb:0108`) on PCIe0 with ath11k: linux-firmware's firmware (`WLAN.HSP.1.1-03125`) hangs when it gets Samsung's ELF calibration | `firmware crashed: MHI_CB_EE_RDDM` → `failed to wait board file download request: -110`, no `wlan0` | **Samsung's** firmware (`/vendor/firmware/qca6490`: `amss20.bin`, `m3.bin`, `regdb.bin` = `WLAN.HSP.2.0.c1-00441`) + `bdwlan.elf` as `board.bin`; DT: node `wcn6855-pmu` (pwrseq), `&pcie0`/`&pcie0_phy`, `firmware-name = "samsung-r9q"` → package `firmware-samsung-r9q-wifi`. **Do not install `linux-firmware-ath11k`**: its `board-2.bin` has a generic entry for these IDs that would win over `board.bin` |
| 16 | Samsung **EA8082 AMB641ZR01** panel (DSI0, command mode, DSC 1.1 8 bpc/8 bpp, 2 slices of 540×30): no mainline driver; `dispcc` reprograms the PLLs and turns off the splash | without a driver: the bootloader's image stays, no brightness/power-off | own driver `panel-samsung-ea8082` (patch `0005`), the `qcom,mdss-dsi-on-command` (`fhd60hs`) sequence from Samsung's DTBO; the PPS mainline computes (`drm_dsc_compute_rc_parameters`, DSC 1.1 pre-SCR) is **identical byte for byte** to Samsung's. Power: vddi = L8C 1.8 V, vci = GPIO166 (3.0 V), reset GPIO22, TE GPIO82 (`mdp_vsync`). Brightness `0x51` 10 bits (2–1023 ≈ 2–420 nits) |
| 17 | Adreno 660 GPU (`qcom,adreno-660.1`) | — | `&gpu` + `gpu_zap_shader` (`qcom/sm8350/samsung/r9q/a660_zap.mbn`, joined from `a660_zap.mdt/.b0x` with `scripts/squash-mdt.py`); SQE/GMU from linux-firmware (`firmware-qcom-adreno-a660`; the SQE is identical to Samsung's). Samsung goes up to 840 MHz (bin 0), as in the mainline table |
| 18 | USB-C: MAX77705 CCIC (0x25) with no mainline driver; dwc3 fixed in device mode | hot-plugged OTG did nothing; charging only at 5 V | patches `0010`–`0019` from the Tab S8+ port (`aaronsb/sm-x800-linux`, ADR-003): OTG regulator in the charger, driver `maxim,max77705-usbc` (DRP typec port, dwc3 role switch, VBUS on attach, PD sink ≤ 9 V / 15 W). DT: `typec@25` with `connector`, `dr_mode = "otg"` + `usb-role-switch` (peripheral by default) |
| 19 | Video output (it is not MHL: it is **DisplayPort Alt Mode** over USB-C) | HDMI adapter without a picture | own patch `0020`: VDMs through the CCIC mailbox (`0x4b` read the reply, `0x48` Enter Mode / DP Configure, the same bytes as stock), pin C (4 lanes; USB goes in HS), typec mux/switch + HPD through `drm_aux_hpd_bridge`. DT: `&mdss_dp`, `&usb_1_qmpphy` (L1B/L6B, `mode-switch`), `usb-sbu-mux` (`gpio-sbu-mux`: enable GPIO16 active low, select GPIO15) and GPIO16 out of `gpio-reserved-ranges` |
| 20 | QCA6490 Bluetooth (WCN6855) on UART18 (QUP SE18, GPIOs 68–71, which were wrongly reserved as "safe") | no `hci0`; with patch+NVM (Samsung's **or** linux-firmware's) every LE connection drops at once: `Connection Failed to be Established (0x3e)` | DT `&uart18` (4 wires, stock pins) + `qcom,wcn6855-bt` on `wcn6855-pmu`; **no files in `qca/`**: the chip works with its ROM firmware (BT 5.2) and connects fine. Do not install `linux-firmware-qca` (it brings `hpbtfw21.tlv` + `hpnv21g.bin` and breaks the connections). **Update (Arch, 2026-11-02)**: the ROM fails with classic Bluetooth (DualShock 4: slow encryption and `hardware error 0x8c`); Arch uses Samsung's patch + NVM unmodified (Arch log, point 12); LE to be tested again |
| 21 | Vibration (linear motor in the MAX77705) | does not vibrate | GCC GP2 PWM on GPIO116 (`clk-pwm`, patch `0021`: GP with `clk_rcg2_gp_ops`), exactly 25.6 kHz → 200 Hz in the motor (stock 205 Hz); patch `0022`: `BIASEN` in the MAX77705 too; **motor supply through GPIO198** (stock `vib_power`) as `haptic-supply` |
| 22 | Speakers: 2× **CS35L41** on I²C5 (1 MHz; `0x40` = bottom, IRQ GPIO26, reset GPIO93; `0x41` = top/earpiece, reset GPIO97) through the ADSP's **Primary MI2S** (APR: q6asm → q6adm → q6afe) | no sound card; then, the amplifiers' DSP did not answer commands and the factory calibration was not applied | patch `0023`: `samsung,r9q-sndcard` in the sm8250 driver (MI2S 48 kHz S16, BCLK 1.536 MHz on GPIO125–128; SCLK as the CS35L41 PLL reference; slot 0 = top, slot 1 = bottom). Samsung's protection firmware (CSPL 20.1.35, `cs35l40-{rcv,bot}-dsp1-spk-prot.*` from `/vendor/firmware`) → `firmware-samsung-r9q-audio`. Patch `0024`: unmask the DSP's IRQ for the mailbox commands (and wait up to 15 ms). Patch `0025`: calibration (`cirrus,calibration`, values from `sec_efs/cirrus`) before the first RESUME, and RESUME after the *global enable*. Boost 1000 nH / 15 µF, peak 4100 mA. UCM `Samsung-Galaxy-S21-FE` (verb `HiFi`, device `Speaker`): **`DSP RX2 Source` = `ASPRX1`** on both (as in stock; the firmware takes the audio from there, and with `ASPRX2` the bottom one was silent and the top one played L+R at half power) and **analog gain 6.5 dB** (`Analog PCM Volume` = 6; the driver starts at 0.5 dB) |
| 23 | Every volume press left ~1 s of silence | music/video cuts out when turning it up/down | pmOS loads `module-role-ducking trigger_roles=event` and Plasma's volume feedback sound is an `event` stream: it ducks everything else while it plays → `/etc/xdg/plasmaparc` with `AudioFeedback=false` |
| 25 | Microphones: 2 DMICs on the LPI pins (DMIC1 = bottom, clock/data pairs GPIO6/7; DMIC3 = top, GPIO8/9; GPIO12/13 give zeros: there is no third microphone) | no audio input | stock records through the **TX macro**, but in mainline the TX macro does not generate the DMIC clock (downstream does it by writing registers of the VA block) → **VA macro** (`qcom,sm8250-lpass-va-macro` at `0x3370000`, clock TX_CORE_MCLK, 2.4 MHz), which `sm8350.dtsi` did not have; the same path Samsung uses for "Hey Bixby" (`VA DMIC MUX0 = DMIC1`). `&lpass_tlmm` enabled with the DMIC states (2 mA, no pull), link `VA_CODEC_DMA_TX_0` → MultiMedia3 (`hw:0,3`). UCM: routes in the verb (PulseAudio probes the PCMs with the verb only) and device `Mic`. `VA_DECn Volume`: 84 = 0 dB (0 = silence) |
| 26 | Scheduler: `sm8350.dtsi` has neither `capacity-dmips-mhz` nor `dynamic-power-coefficient` nor the CPU's L3/DDR votes | every core with `cpu_capacity` 1024 (the A55 "equal" to the X1), EAS off, L3 not voted | DT: stock values (A55 1024/100, A78 1946/499, X1 2048/760) → capacities 325/828/1024 and `sched_energy_aware=1`; `epss_l3` (`qcom,sm8250-epss-l3` as the fallback compatible) + per-cluster OPP tables with exactly the LUT's frequencies and `opp-peak-kBps` = <DDR L3> taken from stock's memlat tables; `CONFIG_INTERCONNECT_QCOM_OSM_L3=y` (cpufreq-hw, built in, waits for the provider). It boots quite a bit faster |
| 27 | Sensors after a clean install (`r7`/`r8`) | `iio-sensor-proxy`: "No sensors… Exiting"; no rotation | boot race: `hexagonrpcd-sdsp` only has `ConditionPathExists=/dev/fastrpc-sdsp` + `WantedBy=multi-user`, and the `fastrpc` module creates the node 0.1 s late → service skipped for good, the SLPI never registered. udev rule in `81-libssc-samsung-r9q.rules` (`SYSTEMD_WANTS+=hexagonrpcd-sdsp` when the node appears) and an `iio-sensor-proxy` drop-in (`After/Wants=hexagonrpcd-sdsp`, `Restart=on-success` every 5 s, ~1 min) |
| 28 | Bluetooth without an adapter in BlueZ (`r8`) | `bluetoothctl`: "No default controller available"; `btmgmt`: 0 controllers; `bootmac`: "Set Powered … Invalid Index" | `bootmac` does power off → `public-addr` → power on; with the ROM firmware (no NVM) that cycle leaves `hci0` hidden from mgmt (besides, right after registering it can stay `HCI_RFKILLED` until an *unblock*: `hciconfig up` gives 132 = `ERFKILL`). Drop-in `bootmac@bluetooth.service.d`: only `rfkill unblock bluetooth` + `btmgmt power on`, without changing the address (the ROM's stays, `00:00:00:00:5A:AD`; Samsung sets the real one with the NVM). Wi-Fi keeps its stable MAC from `bootmac` |
| 24 | Slow Plasma login (~30 s of loading screen and then a frozen desktop) | — | `msm-modem-uim-selection` waits 45 s for a modem that is not started (rmtfs without `-s`) and holds ModemManager's D-Bus activation → kded6's network module → plasmashell. Drop-in with `ExecCondition`: it only runs if the `modem` remoteproc is running. Splash from 31 s → 4.1 s |

postmarketOS installation (from TWRP): `port/flash-pmos.sh --yes-erase-userdata`
(uploads the image to TWRP's RAM, writes it to `userdata`, checks the SHA-256, flashes
boot/vendor_boot, voids dtbo and clears `param`/`misc`). To capture the logs of a boot that
freezes: enter TWRP **with Vol+ + Power at the logo** (do not force Vol− + Power, that makes
the XBL restore an old `sec_log`) and read `/proc/last_kmsg`.

Key debugging tools:
- Persistent console in `sec_log_buf` (0xF0200000) → `/proc/last_kmsg` in TWRP
  (`port/linux/samsung-sec-log-console.c`, adapted from the Tab S9 port).
- `initcall_debug` + the "probing X with driver Y" trace → the last line points at the culprit.
- pstore (ramoops 0xf0b00000): only survives if Linux reboots itself (not a *watchdog bite*).
- The XBL's reset history inside `/proc/last_kmsg` (`Warm Reset by Watchdog Bite`, `Reboot CMD`…).
- From a Linux shell you can get back to TWRP without buttons: `printf '\002\0\0\0' | dd of=/dev/sda7 bs=4 count=1 conv=notrunc` (sda7 = `param`, check the `DLOW` signature at 0x900000) and `reboot -f`.

## How to use what there is

```bash
# test images (kernel from the src/linux-7.2.13 tree + busybox initramfs)
bash port/mkimages-test.sh
# flash from TWRP (boot, vendor_boot, voided dtbo, clears param/misc, reboots)
port/flash-twrp.sh port/out-test
# after booting: replug the cable; the PC uses the NetworkManager profile "r9q-usb" (172.16.42.2)
port/r9q-sh.sh 'dmesg | tail'
# postmarketOS (needs sudo): builds the kernel, device package and image
bash port/build.sh
# Arch Linux ARM (no sudo; uses pmOS's kernel/firmware .apk): packages, image, check.
# Two editions: EDITION=kde (Plasma with login) or EDITION=steam (game mode by default); output in out/$EDITION
bash scripts/build-packages.sh && EDITION=kde bash scripts/build-image.sh && EDITION=kde bash scripts/check-image.sh
# ZIP installable from TWRP (Install → USB-OTG or adb sideload) in artifacts/; test the installer on the PC
EDITION=kde bash scripts/make-twrp-zip.sh && bash scripts/test-twrp-installer.sh
# install Arch from TWRP over adb (ERASES userdata) / update packages on an installed Arch
EDITION=kde scripts/flash-twrp-adb.sh --yes-erase-userdata
bash scripts/update-phone.sh
```

## 1. The device

| Item | Value | Source |
|---|---|---|
| Real model | SM-G990B2 (Galaxy S21 FE 5G, Snapdragon variant) | `ro.boot.em.model`, cmdline |
| Installed ROM | S23 port (`dm1qxeea`, S911B, Android 14) — **ignore** | `getprop` |
| Codename | `r9q` (DT: "Samsung R9Q PROJECT (board-id,14)") | TWRP's DT |
| SoC | Qualcomm SM8350 (Snapdragon 888, "lahaina"), v2.1 | `ro.soc.model`, `qcom,msm-id` |
| RAM | 6 GB (`androidboot.dram_info=01,08,00,6G`) | cmdline |
| Storage | UFS (`1d84000.ufshc`), LUNs sda–sdf | `/dev/block/by-name` |
| Bootloader | `G990B2XXSFHYI1`, **unlocked** (`verifiedbootstate=orange`, `warranty_bit=1`) | props |
| Partitions | No A/B. `boot` (v3), `vendor_boot` (v3), `dtbo`, `recovery` (TWRP, v2), dynamic `super` | `unpack_bootimg` |
| vbmeta | flags=2 (verification already disabled) | `avbtool info_image` |
| Stock kernel | 5.4.254-qgki | `uname` |
| Recovery | TWRP `twrp_r9q` (kernel 5.4.259-aqua_recovery), carries its own DTB+recovery_dtbo | `unpack_bootimg` |

### Peripherals (from TWRP: i2c, dmesg and DT)

| Block | Chip | Bus/notes |
|---|---|---|
| Panel | Samsung **EA8082** AMB641ZR01 (FHD 1080×2340, 60/120 Hz), alt. S6E3FC3 AMB641ZR02 | DSI0, `lcd_id=0x804343` |
| Touchscreen | Synaptics **S3908** (TouchComm protocol, not RMI4) | i2c `35-004b`, fw `s3908_r9.bin` |
| Charger/PD/Type-C | Maxim **MAX77705** + Silicon Mitus **SM5451** (direct charger) | i2c `36-0066`, `36-0063` |
| Wireless charging | IDT P9321 (`mfc-charger`) | i2c `30-003b` |
| Audio | 2× Cirrus **CS35L41** (speakers), WCD (codec in lpass) | i2c `18-0040/41` |
| Vibrator | Cirrus CS40L25A (fw in /vendor/firmware) | |
| Proximity/light sensor | STK3A8X | i2c `39-0045` |
| Grip | ISG5320A | i2c `33-0028` |
| NFC / eSE | NXP SN1xx (`sn-nci`) / P61 on SPI14 | i2c `39-0028`, `spi0.0` |
| Fingerprint | Goodix GW9558 optical (under the display) | SPI in the secure world |
| PMICs | PMK8350 (PON, RTC), PM8350, PM8350C, PMR735A, PMR735B (no PM8350B) | DT |
| Camera PMIC | 2× Samsung S2MPB03 | i2c 31/32 |

Keys: Power = PON kpdpwr (PMK8350), Vol− = PON resin, Vol+ = PM8350 GPIO6 (active low, pull-up).

### Reserved memory (critical)
Samsung changed the memory map compared with Qualcomm's reference (`sm8350.dtsi`).
See `info/reserved-memory-downstream.txt`. Differences applied in the DTS:

| Region | Mainline | Samsung r9q |
|---|---|---|
| cdsp_secure_heap | 0x80c00000 +0x4600000 | 0x80c00000 +0x600000 |
| pil_adsp | 0x86100000 +0x2100000 | 0x85200000 +0x3000000 |
| pil_spss | 0x8b600000 | 0x8b51c000 |
| pil_modem | 0x8b800000 +0x10000000 | 0x8b800000 +0xf600000 |
| pil_camera / video / cvp / slpi | 0x852–0x897… | 0x9b800000… 0x9dd00000 |
| rmtfs | 0x9b800000 (fixed) | dynamic → disabled (it clashed with the camera) |
| removed_mem | up to 0xdf000000 | up to 0xe0500000 |
| Samsung's own | — | hdm 0x9fb00000, kaslr 0xa0001000, tima 0xb0100000, sec_debug 0xf0000000, ss_plog 0xf0900000, **ramoops 0xf0b00000** |
| Bootloader framebuffer | — | `splash_region` 0xe4000000 +0x2300000, 1080×2340 a8r8g8b8 |

### GPIOs protected by TrustZone
Checked: 52–59 (touching them hangs the SoC → watchdog). As a precaution also 17–19 (QUP SE3):
`gpio-reserved-ranges = <17 3>, <52 8>`. **They are not secure** (they were reserved on a guess): GPIO16
(enable of the DisplayPort AUX switch in stock) and 68–71 (QUP SE18, the Bluetooth UART); Linux uses
them without problems.

## 2. Quirks of Samsung's bootloader (ABL)
Lessons from other Samsung-Qualcomm ports (Tab S9 Ultra, Tab S8+, S22 r0q):

1. **DTB selection**: the ABL looks in `vendor_boot` for a DTB with the legacy compatibles
   (`qcom,lahaina-mtp`, `qcom,lahaina`, `qcom,mtp`) and `qcom,msm-id` / `qcom,board-id`.
   Without them: "No match found for Soc Dtb type" → download mode. Values used:
   `qcom,msm-id = <0x19f 0x20001>, <0x1c8 0x20001>, <0x1f5 0x20001>`, `qcom,board-id = <0x10008 0x0e>`.
2. **DTBO**: the ABL applies the overlays of the `dtbo` partition on the DTB; with a mainline DTB it fails.
   Fix: write zeros at the start of `dtbo` (invalid header → the ABL skips the overlays).
   TWRP is not affected because it carries its own `recovery_dtbo`.
3. **splash_region**: the reserved memory node must have this name so the bootloader
   leaves the display on → `simple-framebuffer` works without a panel driver.
4. Header v3: `boot.img` (kernel) + `vendor_boot.img` (DTB + ramdisk + command line).
   The original's parameters: base 0, kernel 0x8000, ramdisk 0x2000000, tags 0x1e00000,
   dtb 0x1f00000, pagesize 4096, board `SRPVC21A007`.

## 3. The port's files

```
r9q2/
├── docs/porting-log.md                     this document
├── info/                          extracted data (cmdline, dmesg, i2c, regulators, memory…)
├── dump/                          BACKUPS of partitions (boot, vendor_boot, dtbo, efs, sec_efs, persist, modem…)
├── fw/                            extracted firmware (vendor/firmware, NON-HLOS, modem)
├── dts/                           the original DTB/DTBO decompiled + r9q-merged.dts
├── unpack/                        boot/vendor_boot/recovery unpacked
├── port/
│   ├── linux/sm8350-samsung-r9q.dts      new mainline device tree
│   ├── linux/r9q.config                  config fragment on top of linux-postmarketos-stable
│   ├── linux/config-samsung-r9q.aarch64  final config
│   ├── pmbootstrap-r9q.cfg               separate pmbootstrap config (does not touch yours)
│   ├── build.sh                          builds packages + pmOS image (needs sudo)
│   ├── mkimages-test.sh, gen_cpio.py     test images without sudo (busybox initramfs)
│   └── testinitramfs/init                test init: USB network + telnet
│   ├── wifi-test.sh                      Wi-Fi test: the PC's kernel + r3 initramfs + firmware cpio
│   ├── gpu-display-test.sh               display+GPU test (the PC's kernel, test-gpu-display.config)
│   ├── gpu-test/gles-test.c              windowless GLES2 test on renderD128 (no headers, no sudo)
│   ├── panel/                            panel driver, decoder of the DTBO's commands
│   ├── squash-mdt.py                     joins split .mdt + .bNN firmware into an .mbn
│   ├── make-test-images.sh               test boot.img + vendor_boot.img (kernel from src/)
│   ├── linux/test-*.config               the test kernels' `=y` options (they load no modules)
│   ├── checks/                           test scripts on the phone (usb, dp, bt, audio, login…)
│   ├── bt-nvm.py                         reads/applies Samsung's NVM XML settings for Bluetooth
│   ├── out-audio/                        cirrus firmware, UCM and test WAVs for the speakers
│   └── after-build-install.sh            checks build.sh's image and installs it from TWRP
└── packaging/postmarketos/
    ├── linux-samsung-r9q/                kernel 7.2.13 + DTS + patches 0001–0025
    ├── device-samsung-r9q/               deviceinfo, qcrypto blacklist, rmtfs and
    │                                     msm-modem-uim-selection drop-ins, UCM, Plasma defaults
    └── firmware-samsung-r9q/             Samsung's firmware (adreno, adsp, audio, cdsp,
                                          hexagonfs, modem, slpi, wifi)
```

## 4. Test log

### 2026-10-30 — first attempt (busybox test image, `port/mkimages-test.sh`)
- Kernel 7.2.13 built on the PC (`make ARCH=arm64 LLVM=1`), DTB `sm8350-samsung-r9q.dtb`,
  busybox initramfs (Alpine `busybox-static` 1.37.0-r20) with an NCM/RNDIS/ACM USB gadget + telnet.
- Flashed from TWRP: `boot`, `vendor_boot`, and 4 KiB of zeros at the start of `dtbo`.
- Result: after rebooting, the phone **always goes back to TWRP** (~20–30 s), with no trace of the
  gadget nor of my kernel in pstore.
- A false lead found: `misc` held the `boot-recovery` BCB (from `adb reboot recovery`).
  Cleared with `dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=8`, but TWRP writes it
  again when it starts.
- Control: with the original `boot`, `vendor_boot` **and** `dtbo`, rebooting from TWRP (`adb reboot`,
  `reboot`, `twrp reboot`) **also** goes back to TWRP. Conclusion: something forces recovery
  regardless of the Linux image → the screen (the ABL's message) has to be seen.
- State at the end: original partitions restored (boot, vendor_boot, dtbo).

### Cause of "always back to TWRP" (SOLVED)
The bootloader's log (in TWRP's `/proc/last_kmsg`, `[ ABL ]` lines) said:
`PARAM Flag is PARAM_BOOT_RECOVERY_ENTER` → `BootMode = 2` → `Booting Into Recovery Mode`.
`adb reboot recovery` sets **the first word (4 bytes) of the `param` partition to 2** and TWRP never
clears it. Fix (from TWRP, before rebooting):
```
dd if=/dev/zero of=/dev/block/by-name/param bs=4 count=1 conv=notrunc
dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=8
```
`port/flash-twrp.sh` always does it after flashing.

### Attempts with Linux
1. **busybox image, no watchdog**: the ABL **accepts the DTB** (`Best match DTB tags
   415/00010008/0x0000000E/20001`), ignores the voided dtbo (`Dtbo hdr magic mismatch`) and jumps to the
   kernel. Screen: logo → black → reboot after ~15 s. No USB. pstore empty (there was no panic).
   The ABL **replaces `console=tty0` with `console=null`** → the command line is forced with
   `CONFIG_CMDLINE_FORCE` in the test builds (`port/linux/test-cmdline.config`).
2. **With a `qcom,kpss-wdt` watchdog node @0x17c10000 + `QCOM_WDT=y`**: Linux boots
   (pstore: "Booting Linux on physical CPU 0x0 … Linux version 7.2.13") and after 0.62 s raises an
   **SError (Tainted: M / MACHINE_CHECK)** in `qcom-wdt`'s probe (x7 = "wdt_bark").
   → Linux cannot touch the APSS watchdog directly on this device. Node removed.
3. pstore: the RAM at 0xf0b00000 comes back with flipped bits after the reset. With compression the
   record is unrecoverable → `PSTORE_COMPRESS` disabled. ECC (`ecc-size`) does not help because
   TWRP's kernel reads without ECC → removed.

4. **Cause of the reboots (confirmed in the XBL log, `/proc/last_kmsg`)**: in every cycle
   `Power ON by Reboot CMD 0x1f` → ~29 s → `Warm Reset by Watchdog Bite` → `Hard Reset at XBL`
   ("not allow normal booting with warm_reset status"). The ABL takes ~19 s, so Linux lives
   ~10 s and nobody feeds the watchdog. The *hard reset* that follows wipes the RAM: that is why pstore
   arrives empty or corrupt. For pstore to survive, Linux must reboot itself (panic →
   PSCI) before the bite: lockup detectors with a 1–3 s threshold and `panic=1`.
5. Screen: after the logo it "does weird things" and then black → Linux's console does get to draw
   on the framebuffer (0xe4000000, 1080×2340, 32 bpp, the same as Mu-Silicium `r9qb2Pkg`).
6. Initramfs built into the kernel (`CONFIG_INITRAMFS_SOURCE`): the same result → the problem
   is not the ABL's ramdisk.

### 2026-10-31 — Wi-Fi (QCA6490 on PCIe0, ath11k)
Test with `port/wifi-test.sh`: the PC's kernel with the whole Wi-Fi stack built in
(`port/linux/test-wifi.config`: cfg80211, mac80211, QRTR/MHI, ath11k, PCIe PHY, pwrseq) and
`vendor_boot` = the r3 initramfs + a cpio with the firmware (no need to reinstall the rootfs).
1. DT (from Android: `wlan_en` GPIO64, `bt_en` GPIO65, `sw_ctrl` GPIO153, PERST GPIO94, WAKE
   GPIO96, CLKREQ GPIO95): node `wcn6855-pmu` with the supplies s10b/s2e/s12b/s11b/s1c, `&pcie0`
   + `&pcie0_phy` (l5b/l6b) and the child `pcie@0/wifi@0` (`pci17cb,1103`). Result:
   `PCIe Gen.3 x1 link up`, `ath11k_pci … wcn6855 hw2.1`, chip_id 0x12, board_id 0xff.
2. The firmware cpio carried `lib/` as a directory and, when unpacked, it **replaced the
   `lib → usr/lib` link** of pmOS's initramfs → `No working init found`. The firmware goes in `usr/lib/firmware`.
3. With linux-firmware (`WLAN.HSP.1.1-03125`) + Samsung's `bdwlan.elf` as `board.bin`: the
   firmware starts and half a millisecond after asking for the calibration it hangs
   (`MHI_CB_EE_RDDM`). `bdwlan.elf` and `bdwlang.elf` (cnss2's "GF" name for chip_id & 0x10)
   are identical.
4. With Samsung's firmware (`amss20.bin` → `amss.bin`, `WLAN.HSP.2.0.c1-00441`) it works:
   `wlan0` appears, NetworkManager scans on 2.4 GHz (channel 8) and 5 GHz (channel 40), signal 87–89 %.
5. Packaging: `firmware-name = "samsung-r9q"` in the DT makes ath11k look for amss/m3/regdb in
   `ath11k/WCN6855/hw2.1/samsung-r9q/` (no clash with linux-firmware); the `board*` files are always
   looked for in `hw2.1/`. The `stable` config already has everything as modules (`PCI_PWRCTRL_PWRSEQ` is
   hidden and `ATH11K_PCI` selects it), it did not need changes.
   Validated on the phone (20:11): amss/m3/regdb from `hw2.1/samsung-r9q/`, `board.bin` from
   `hw2.1/`, `wlan0` up and scanning at 90 %.
6. Pending: the MAC. The firmware gives `00:03:7f:12:59:06`, Qualcomm's generic one (Atheros OUI,
   the same on other devices without a MAC in OTP); the real one is in `/efs/wifi/.mac.info` and ath11k
   accepts `local-mac-address` in the `wifi@0` node (`device_get_mac_address`). Bluetooth (same chip,
   UART) and a connection and speed test are also missing.

### 2026-10-31 — Display (EA8082) and GPU (Adreno 660)
1. Panel: `msm_drm.dsi_display0=ss_dsi_panel_EA8082_AMB641ZR01_FHD` on the ABL's command line. Its node in
   `dts/dtbo_0.dts` has the full sequence; `port/panel/decode-cmds.py` decodes it. The `fhd60hs` and
   `fhd120hs` modes only differ in `60 00 00` / `60 08 00` and the vertical porch (12/16).
   lmdpdg could not be run here (permission denied for downloaded code): the driver was written by
   hand using `panel-samsung-s6e3ha8.c` as a template. The reset is requested with `GPIOD_ASIS` so the
   splash is not turned off before the first `prepare`.
2. First test (`msm.separate_gpu_kms=1`, GPU and display as separate DRM devices): `DSI-1`
   connected 1080×2340, `msm-kmsdrmfb`, a visible console drawn by the driver; a dump of the PPS with
   `panel_samsung_ea8082.dyndbg=+p` = Samsung's PPS. `DSI PLL(0) lock failed` in the PHY's probe is
   harmless (a check of the bootloader's state). ~10 SMMU context faults (SID
   0x820/0xc20) while the MDSS still reads the splash; `iommu-addresses` does not prevent it ("not able to establish
   FW requested direct mapping").
3. The GPU firmware went in the initramfs, but the GPU asks for it when the device is opened (already in the rootfs):
   `error -40` on every `/lib/firmware/...` path. In the test it is built into the kernel
   (`CONFIG_EXTRA_FIRMWARE`); in the build it goes in the rootfs, like the Wi-Fi one in `r4`.
4. Second test (a single DRM device, the final configuration): GPU bound to the DPU, `Loaded GMU
   firmware v3.1.10`, devfreq 315–840 MHz (`simple_ondemand`). `port/gpu-test/gles-test.c` (built
   with clang against the libraries of pmbootstrap's rootfs, own `_start` for musl): `GL_RENDERER =
   FD660`, `OpenGL ES 3.2 Mesa 26.2.6`, the gradient's pixels correct, 300 frames of 1080×2340 in 0.1 s.
5. Pending: 120 Hz (change `60 00 00` → `60 08 00`, porch 16 and ~1.1 Gbps of DSI), HBM (`53 e0`,
   up to 800 nits), testing display blank/unblank and suspend.

### 2026-10-31 — DSPs (ADSP/CDSP/SLPI/modem)
1. NON-HLOS/modem firmware joined with `scripts/squash-mdt.py` in `port/out-dsp/fwroot` (adsp 17 MB, cdsp 8.8 MB,
   slpi 6.1 MB, modem 84 MB); `port/mdt-span.py` confirms they fit in Samsung's PIL regions (48/30/22/246 MiB).
2. DTS: `&adsp`, `&cdsp`, `&slpi`, `&mpss` enabled with `firmware-name` in `qcom/sm8350/samsung/r9q/`; rmtfs
   as a dynamic 2.5 MiB reservation < 4 GiB with `qcom,vmid` MSS (it ended up at 0xffd00000).
3. Test (`port/test-boot.sh port/out-dsp/fwroot scripts/diagnostics/dsp.sh`, `test-dsp.config`): ADSP, CDSP and SLPI
   **running** and stable at 136 s; glink IPCRTR, fastrpc (`/dev/fastrpc-*`), `apr_audio_svc`.
4. Modem: mainline does not start it by itself (rmtfs `-s` does). Started by hand (firmware in `/tmp/fw` +
   `firmware_class.path`, `scripts/diagnostics/modem-start-logged.sh` with a persistent log in the rootfs):
   `remote processor modem is now up`, glink channels `IPCRTR`, `SSM_RTR_MODEM_APPS`, `glink_ssr`. Every ~65 s:
   `fatal error received: dog_hal_common.c:177:DOG detects stalled initialization` (it waits for EFS/tqftpserv)
   and the kernel recovers it (SSR) without affecting the rest: USB, ping and the other DSPs stay fine. The supposed
   hang of the first attempt was the button reset (`Warm Reset by Key Crash` in the XBL's history).
5. Packaging (r5): `firmware-samsung-r9q` with subpackages `-adsp`, `-cdsp`, `-slpi`, `-modem` (+ `modem_pr/`,
   `*.jsn`); `device-samsung-r9q` depends on them, on `rmtfs`, `soc-qcom` (tqftpserv, bootmac → the Wi-Fi's
   stable MAC) and `soc-qcom-modem`. Alpine's service is `rmtfs -r -P -s`: **`-r` = read only** (writes
   go to a RAM buffer), `-P` looks up `modemst1/modemst2/fsc/fsg` by label, `-s` starts the
   modem. `after-build-install.sh` aborts if the service does not carry `-r`. There is a copy of all those partitions
   in `dump/`. pd-mapper: the kernel's already supports `qcom,sm8350`.
6. Pending: IPA (mobile data: `&ipa` + `ipa_fws`), sensors (hexagonrpcd + the sensor registry from
   `/vendor/etc/sensors`, `dsp` partition), audio (APR already available on the ADSP).

### 2026-11-01 — Touchscreen (Synaptics S3908) and 120 Hz
1. Touchscreen: in Samsung's DT, `touchscreen@4b` on `i2c@990000` (QUP SE4 = `&i2c4`), `synaptics,synaptics_ts`,
   IRQ GPIO23, no reset GPIO; `tsp_avdd` = L11C (1.8 V) and `tsp_io` = a fixed regulator on GPIO50.
   Mainline has no TouchComm driver; Vsevolod Nevorotov's linux-input v2 series is used
   (2026-09-10, `synaptics_tcm_i2c` + `syna,s3908.yaml`, patchwork 14804754/14804755, not accepted yet)
   = patch `0006`, plus `0007`, which makes the reset optional (GPIO22 is the panel's reset here).
2. First attempt: `990000.i2c: deferred probe pending: geni_i2c: Failed to get tx DMA ch` → the bootloader
   leaves SE4 in GSI mode; `&gpi_dma0` is enabled (the same 0x7e mask and SID 0x5b6 as Samsung's DT).
3. Result: `TouchComm v1, mode 0x01, part s3908 R0-15.0`, `4096x4096, 10 touch objects`, input
   `Synaptics TouchComm Touchscreen` (INPUT_PROP_DIRECT); the IRQ went from 14 to 927 when touching.
4. 120 Hz: `panel_samsung_ea8082.refresh_rate=120` (mode `fhd120hs`: `60 08 00`, vertical porch 16);
   the display keeps working. Default in `r5`'s `deviceinfo`.
5. `r5`: UI `plasma-desktop` (Plasma desktop) in `work/pmbootstrap-r9q.cfg`; `flash-pmos.sh` writes the image in chunks
   of 1 GiB (TWRP's tmpfs only has ~2.3 GB).

### 2026-11-01 — r5 installed; touchscreen and display with modules
1. r5 (Plasma desktop) booted without a display: with msm/gpucc as modules, after ~13 s the
   *deferred probe timeout* expires and the SMMU/GPU bind without `gpucc` → `failed to bind 3d00000.gpu: -19` and
   the whole of msm goes down. Fix: `deferred_probe_timeout=60` (deviceinfo, device r6).
2. Touchscreen not responding: the GPI DMA does not release the TX of I²C reads (CONFIG+GO with LINK, no IEOT)
   → `not enough space in ring, avail:1 required:3` → patch `0008` (retires that descriptor when the RX
   completes). Then `evtest` still got no events: Samsung's `s3908_r9` firmware does not send the
   TouchComm 0x11 report but **0xC1**, with 16-byte `sec_ts`-style events (byte0: eid[1:0], finger[5:2],
   state[7:6]; x=b1<<4|b3>>4, y=b2<<4|b3&0xf; b4/b5 width, b6 z) → patch `0009`. The touchscreen works in
   Plasma. `debugfs`/dynamic debug are blocked by *lockdown* even as root.
3. Plasma: KWin uses OpenGL ES 3.2 on FD660 (freedreno), DSI-1 1080×2340 at 120 Hz, scale 2.65. The
   `llvmpipe` of `/dev/udmabuf` is only the secondary device (screenshots). The desktop appears ~9 s
   after the password; before that there are 45 s of waiting for `msm-modem-uim-selection` (modem down).
4. Settings are saved; the odd dates come from the RTC (it starts at Oct 15, NTP fixes it;
   soc-qcom's `swclock-offset` stores the offset).
5. fastfetch takes the DT's last compatible (`qcom,mtp`) and on Linux does not translate `sm8350` into a
   marketing name → `/etc/xdg/fastfetch/config.jsonc` in device-samsung-r9q with
   `Qualcomm Snapdragon 888 ({core-types}) @ {freq-max}`.

### 2026-11-01 — Sensors (SSC on the SLPI)
1. All the sensors hang off the SLPI (SSC): in `persist`'s registry (`dump/persist.img`,
   `/sensors/registry/registry`) there are `lsm6dso` (accel/gyro, rotation), `stk3a9x` (light/proximity),
   `ak0991x` (magnetometer), `lps22hh` (pressure) and the virtual ones (`auto_rotation`, `gravity`, `rotv`,
   `step_counter`...). `vendor.img` is the original G990B2 one (Android 11).
2. Linux stack: `hexagonrpcd -d sdsp` serves the "hexagonfs" to the SLPI; `libssc` + `iio-sensor-proxy` (Alpine's
   links `libssc.so.2`). hexagonrpcd guesses the directory from the DT:
   `/usr/share/qcom/sm8350/Samsung/r9q` (model "Samsung ...", first `qcom,` = sm8350, `samsung,r9q`).
3. hexagonfs (`port/hexagonfs`, subpackage `firmware-samsung-r9q-hexagonfs`): `dsp/sdsp` (dsp partition),
   `sensors/config` + `sensors/sns_reg.conf` (`/vendor/etc/sensors`), `sensors/registry` (persist, with this
   unit's factory calibration) and `socinfo/` with the stock kernel's values read in TWRP:
   hw_platform=MTP, platform_subtype=Unknown(0), platform_version=65536, soc_id=415, revision=2.1
   (Samsung also: `ssc_hw_rev`=14 in /sys/class/sensors/ssc_core, hexagonrpcd does not map it).
4. Rule `81-libssc-samsung-r9q.rules` with `ACCEL_MOUNT_MATRIX` (to be checked by turning the phone).
5. In r5 the modem (started by `rmtfs -s`) crashed after 50 ms (`BADVA=0xa0100200`) and its SSR took the SLPI
   down while it was starting (`glink_channel_migration.c:758 Assertion`). Until the
   modem is fixed: drop-in `rmtfs.service.d/10-samsung-r9q.conf` = `rmtfs -r -P` (EFS served, modem not
   started automatically).

### 2026-11-01 — Sensors working
1. Permissions: my `chmod 644 sensors/*` left `config/` and `registry/` without +x for the `fastrpc` user
   (the package is fine, 0755).
2. `hexagonrpcd` resolves `..` in its virtual tree: `registry/registry/../sns_reg_version` did not exist →
   the SSC regenerated the registry endlessly (temp.json). Local package `device/testing/hexagonrpcd` 0.4.0-r4
   with `0001`: it serves `sns_reg_version` and `/sys/class/sensors/ssc_core/ssc_hw_rev` (Samsung, =14).
   `sensors/config` empty (persist's registry is complete). Build with `--arch aarch64` and
   `options="!pmb:crossdirect"` (meson fails with crossdirect).
3. With the registry loaded the SLPI crashed every ~15 s (`SNS_SEE_P_0 exceeded processing time limit`):
   `sensor_vdd` = **L2C 1.8 V** was missing (Samsung's PIL turns it on before the SLPI) → `always-on`;
   also `proxy_int` GPIO89 in `&slpi`.
4. Result: iio-sensor-proxy sees the accelerometer, light, proximity and compass. Plasma's rotation is correct
   with `ACCEL_MOUNT_MATRIX` -1,-1,-1. Light 3–90 lux depending on the lighting. 34 thermal zones + battery.
5. Pending: proximity (libssc aborts: `libssc-sensor-proximity.c:98 code should not be reached`,
   Samsung's format), magnetometer calibration (~576 μT), barometer (lps22hh, iio-sensor-proxy does not expose
   it), and a clean build with L2C + hexagonrpcd r4 + hexagonfs r4.

### 2026-11-01 — USB-C: OTG, automatic role, PD charging and HDMI output (DP Alt Mode)
1. **Type-C driver**: the patches from the Galaxy Tab S8+ port (the same MAX77705, ADR-003 in
   `dl/sx800/003-pd-ownership.md`) apply as they are on 7.2.13 as `0010`–`0019`. Invariants that are
   kept: never enter the CCIC's firmware update path, never PPS/APDO, only fixed PDOs ≤ 9 V, never OTG
   boost with a charger input. The driver filters the opcodes with a whitelist.
2. Test (the PC's kernel, `port/out-usbtest`): with the PC → `data_role device`, `power_role sink`,
   USB gadget intact, charging at 500 mA (PC port). With hot-plugged OTG: Genesys hub `05e3:0618`,
   card reader and Corsair receiver (keyboard+mouse) enumerate; unplug/replug 3 times OK.
   The boot takes ~150 s to give the USB network back (normal in the test kernel).
3. **HDMI**: the S21 FE has no MHL; it outputs DisplayPort on the USB-C's SuperSpeed lanes. Protocol
   taken from the r9q's stock kernel (`Andra297/android_kernel_samsung_r9q`, branch BVA3,
   `drivers/usb/typec/maxim/max77705_alternate.c`): the CCIC's firmware does Discover ID/SVIDs/Modes
   by itself (with `SET_ALTERNATEMODE 0x03`) and reports in `VDM_INT` bits 0–3; DP Status/Configure/Attention
   arrive in `PD_INT` bits 2–4 (stock unmasks them: `VDM_INT_M=0xF0`, `PD_INT_M=0x00`). The host reads
   each reply with `0x4b <id>` and asks for Enter Mode (`48: 09 04 81 01 FF`) and DP Configure
   (`48: 0A 11 81 01 FF 06 <pin> 00 00`). Own patch `0020`.
4. AUX/SBU switch: in stock `qcom,aux-en-gpio` = GPIO16 (high at rest = off) and
   `qcom,aux-sel-gpio` = GPIO15 (1 with CC2); the DT's `fsa4480` is disabled → `gpio-sbu-mux`.
5. Result (`port/out-dptest`, Nintendo Switch dock `057e:2003`): `caps 0x00000c05` → pin C,
   `HPD high` after 5 s, a perfect picture on the external display (Plasma sees `DP-1`); on unplugging
   `HPD low` and `DisplayPort off`. The internal display is not affected.
6. Known noise: `qcom_q6v5_pas 5c00000.remoteproc: Handover signaled, but it already happened`
   every ~0.3 s (SLPI). Harmless; the Tab S8+ port lowered it to debug level (its kernel r41).

### 2026-11-01 — Bluetooth and vibration
1. **Bluetooth**: QCA6490 on UART18 (stock `qupv3_se18_4uart`, 4 wires: CTS/RX `qup18` without bias, RTS
   pull-down, TX pull-up), powered by the `wcn6855-pmu` like the Wi-Fi. Vendor firmware:
   `hpbtfw21.tlv` (BTFW.HSP_C.2.1.1-00382) and NVM `hpnv21{,g}.baa` (a normal TLV; btqca looks for
   `qca/hpnv21g.bin`, the chip is the GF variant). Samsung also applies `bt_nvm_loading.xml` (tags
   36/83/87/204; tool `port/bt-nvm.py`, 83 does not match in length).
2. With patch + NVM (Samsung's, with or without the XML, **and also** the linux-firmware pair
   HSP.2.1.0-00680 + `hpnv21g.baa`) scanning goes fine (mouse at −43/−49 dBm) but every LE connection
   drops: btmon shows `LE Enhanced Connection Complete: Success` and ~160 ms later
   `Connection Failed to be Established (0x3e)` (no packet arrives on data channels).
   Ruled out: deep sleep (tag 27), in-band sleep (tag 17 + `QCA_IBS_DISABLED`), Wi-Fi, the LE feature
   set (identical except subrating/ADI). With the **ROM firmware** (no files in `qca/`,
   `QCA_ROM_FW`) the Corsair Harpoon mouse connects and stays. It is left like that; later, find out
   which RF configuration of this board the patch needs.
3. **Vibration**: three chained failures, seen with temporary traces (`test-0022`):
   GP2 with `clk_rcg2_ops` only allowed 50/100/200 MHz without M/N → `-EINVAL` when setting the duty cycle (patch
   `0021`); mainline's driver only enabled `BIASEN` on the MAX77843 (patch `0022`); and the motor
   has its own power switch on **GPIO198** (`vib_power_default`, output-high in
   stock). Period 39063 ns = exactly 25.6 kHz from CXO (19.2 MHz / 5 / 150) → 200 Hz in the motor.
   Test: `sudo python3 scripts/diagnostics/vibrate.py 1000` (FF_RUMBLE through evdev).

### 2026-11-01/02 — Speakers, microphones, volume keys and slow login
1. **Audio path**: ADSP (APR q6asm → q6adm → q6afe) → Primary MI2S (GPIO125 SCK, 126 DATA0,
   127 DATA1, 128 WS) → both CS35L41 on I²S, one slot each. Mainline's sm8250 driver works
   with a new compatible (`0023`): it sets the codecs' format and clock (SCLK as the PLL reference,
   1.536 MHz) and the channel map (left = top, right = bottom).
2. Samsung's **protection firmware**: CSPL v20.1.35 (`R9_RCVPV2_PPS_logging_20210602.bin` on top).
   The top and bottom `.wmfw` are identical; the `.bin` files differ. Three problems:
   - the mailbox commands (PAUSE/RESUME) timed out: this firmware only serves them if the host
     unmasks the DSP's IRQ (`IRQ2_MASK2` bit 20), and takes up to ~15 ms → patch `0024`;
   - the calibration written from ALSA was ignored (with the DSP running it rejects changes) → `0025`
     writes it in the kernel when the DSP starts. Factory values from `sec_efs/cirrus` (as text):
     `rdc_cal`/`vsc_cal`/`isc_cal` = top (8420, 16770419, 16774318), `*_cal_r` = bottom (8564,
     16769867, 16775710), `temp_cal` = 36 °C → `cirrus,calibration = <rdc temp vsc isc>` in the DT;
   - DAPM powers DSP1 up before "Main AMP" and a RESUME before the *global enable* fails → `0025`
     sends the RESUME from Main AMP's event.
   Test: `scripts/diagnostics/audio-test.sh` (`test-lr.wav`: left = top, right = bottom).
3. **Test kernel without modules**: since *lockdown* rejects the rootfs's modules, these were missing:
   `qcom-pon` (without it there is no `pmic_resin`, that is, no volume-down key), `hid-apple`
   (USB keyboard) and FUSE (Firefox's document portal) → `=y` in `port/linux/test-bt-haptic.config`.
   In `r7` they are normal modules and load by themselves.
4. **Silence when changing the volume** (row 23): ruled out `tsched=0` and the kernel (a simple
   player keeps playing without cuts). Firefox closed and reopened its stream, but the cause of the silence was
   pmOS's *role-ducking* with Plasma's feedback sound. YouTube in Firefox works fine.
5. **Slow login** (row 24): with `busctl --user monitor` started by a user unit in
   `default.target`, plasmashell was seen waiting 25 s for kded6, and kded6 waiting for ModemManager's D-Bus
   activation, which depends on `msm-modem-uim-selection` (45 s of waiting for the modem).
   With the drop-in: `plasma-ksplash.service: Consumed 970ms CPU time over 4.087s wall clock time`.
6. **Bluetooth in `r7`**: `CONFIG_BT_LE=y` (pmOS's `stable` config has it disabled; the
   test kernel had it enabled). It only adds the ISO (LE Audio) and ECRED channels; normal LE connections
   already worked without it. Added to `port/linux/r9q.config`.
7. **Volume lower than in Android**: the CS35L41's analog gain (`Analog PCM Volume`,
   0–20 = 0.5–20.5 dB) starts at 0.5 dB. What Android uses could not be found out: Samsung's `mixer_paths.xml`
   sets `AMP PCM Gain` 0 and `Digital PCM Volume` 0 (which in its driver means *silence*), so
   something else changes those initial values; neither the `/vendor` libraries nor the `.wmfw`/`.bin`
   write those registers. Cirrus uses 17.5 dB with this firmware (`DEFAULT_AMP_GAIN_PCM` of
   `cs35l41_hda`, and the Steam Deck in its UCM). Android also passes the audio through **SoundBooster**
   (Samsung's multiband compressor on the ADSP, `SB RX Volume`), which mainline does not have.
   Telemetry of the protection firmware with music at 100 % (`scripts/diagnostics/amp-gain-step.sh`):
   `CSPL_OVERSIGHT_GAIN` = 1.0 (it does not cut anything), 0 over-excursion/temperature events,
   top coil at ~24–25 °C. Raised live to 6.5 dB: it sounds like Android by ear, still cuts
   nothing and the top coil reaches 25.4 °C. The bottom one reads a fixed 23.00 °C (it probably does not
   estimate temperature at so little power; watch it if it is raised further). Set in the UCM.
   Telemetry format: 4 bytes big-endian; temperature in Q14 (°C), gain in Q20.
   The long names of the "Bottom" controls come out cut at the front (ALSA's 44-character
   limit): e.g. `Bottom DSP1 Protection cd PL_OVERSIGHT_GAIN`.
   **Correction (see point 8)**: that test was done with the bottom speaker silent. With both playing,
   6.5 dB still sounds "more or less like Android" by ear; it stays like that.
8. **The bottom speaker did not play with the protection DSP.** An acoustic test with the
   microphones uncovered it (`scripts/diagnostics/mic-loopback.sh`: a 1 kHz tone through the top only and then through the
   bottom only, measuring the tone on each microphone with Goertzel): with `DSP RX2 Source` = `ASPRX2` both tones
   came out the same and only through the top (muting the bottom changed nothing; muting the top
   left total silence). The CSPL firmware takes the audio from DSP RX2 (Samsung's driver, to
   mute, sets RX2 to zero) and stock sets it to `ASPRX1`. With `ASPRX1`: top tone −30 dBFS on the
   top microphone / −48 on the bottom one; bottom tone −37 / −53 → correct stereo, and the temperature
   of the bottom coil finally moves (25.0 → 26.5 °C). Before this, "it plays through both" had been taken as good
   by looking only at the logs: in DSP mode it had never been confirmed by ear.
9. **Microphones** (row 25): with the microphone test kernel, the room noise comes out at −65…−80 dBFS
   on DMIC1 and DMIC3 and exactly zero on DMIC4/5. The even channels (DMIC0/2) also give a signal: it is the
   data line floating on the edge nobody uses (it repeats the last bit). To identify each
   microphone the acoustic test of point 8 was used (DMIC1 = bottom, DMIC3 = top, like stock's `main-mic`/`sub-mic`).
   Decimator gain at 0 dB (84), like stock's `rec-main-mic`. Scripts:
   `scripts/diagnostics/mic-test.sh` (records and measures) and `scripts/diagnostics/mic-loopback.sh`. To test a new UCM
   without sudo: copy `/usr/share/alsa/ucm2` to `~/ucm2-test` and start PulseAudio as a user unit
   (`systemd-run --user --setenv=ALSA_CONFIG_UCM2=$HOME/ucm2-test pulseaudio --daemonize=no`, with
   `autospawn = no` while restarting; started from SSH, systemd kills it when the session closes).

### 2026-11-02 — CPU and GPU scaling (`scripts/diagnostics/cpu-scaling.sh`)
1. Tables (`qcom-cpufreq-hw`, read from the hardware, `schedutil` governor): silver A55 (cpu0–3)
   300–1804.8 MHz in 16 steps; gold A78 (cpu4–6) 710.4–2419.2 MHz in 16; prime X1 (cpu7)
   844.8–2841.6 MHz in 19. GPU (`simple_ondemand`): 315–840 MHz in 10 OPPs.
2. Under load, each cluster reaches its maximum and with all 8 cores it holds for 20 s (84 °C, no
   cooling states active); at rest they drop to the minimum. `stats/time_in_state` has time in every
   step. Real performance (a Python loop pinned to one core): X1 31.7 / A78 23.7 / A55 4.6 M iter/s.
   With the 8 cores at once, gold and prime give ~30 % less even though sysfs shows the maximum: it is the
   SoC's LMh (interrupts `dcvsh-irq-4`/`-7` in `/proc/interrupts`), normal without a fan.
3. Idle: `psci_idle` + `menu`, each core with WFI and `cpu-sleep` (it spends most of its time there);
   cluster idle goes through the PSCI domains.
4. GPU with `gles-test` in a loop: it goes 315→840 MHz and back to 315 at rest; ~2200–2800 fps at
   1080×2340 (5.6–7.2 Gpix/s). The GPU's RAM bandwidth is voted by the GMU (A660's table in
   `a6xx_hfi.c`).
5. **Gap**: `sm8350.dtsi` declares neither `epss_l3` nor CPU OPP tables with `opp-peak-kBps`, so the
   CPU does not vote L3/DDR bandwidth when it raises its frequency (the `qcom,epss-l3` driver exists and SM8250
   uses it). Today performance is normal (256 MB copy: 15.9 GB/s on the X1, 13.0 on A78, 5.7 on A55),
   so the RAM is not stuck low; the likely cost is battery (it cannot be seen without root:
   `/sys/kernel/debug/interconnect`).
6. **Cause of the RAM always at the top**: `qnoc-sm8350 1580000.interconnect / 1700000.interconnect:
   sync_state() pending due to 1dfa000.crypto`. The `crypto` node is still enabled (row 13) but its
   driver is blacklisted, so it never binds; meanwhile the interconnect framework
   keeps all the buses and the DDR at the maximum they started with. It is probably the same reason why
   `r2` (crypto/cryptobam disabled in the DT) froze after ~30 s: without that consumer
   `sync_state` does happen, the votes without an owner drop and something of TrustZone (the crypto engine?)
   is left without bandwidth. Fixing it needs an own vote for that path before letting
   `sync_state` happen. (Also `gcc`/`gpucc` wait for `3d6a000.gmu`, which has no driver
   of its own: unused clocks that are not turned off; it is common in mainline.)
7. **Capacities + EAS + L3** (row 26, test kernel #40): capacities 325/828/1024, EAS active
   (the energy model marks some low A55 OPPs as inefficient, normal), `epss_l3` bound
   to `osm-l3`, cpufreq intact (16/16/19 steps, goes up and down as before). 2 MB copy on the X1:
   36.7 → 38.5 GB/s (the L3 was not that low; a single core does not squeeze it). The boot is
   visibly faster. Check: `scripts/diagnostics/perf-check.sh` and `scripts/diagnostics/mem-bw.py`.

### 2026-11-02 — First install of `r7`: no display (patch `0026`)
1. After `FLASH_OK`, a "corrupt" screen and no Plasma. `/proc/last_kmsg` (TWRP) showed a 50 min
   boot: the new initramfs (`postmarketos-initramfs` 3.12.5, `check_keys`) saw **Vol+ pressed** at
   2.6 s and stopped on purpose (`fail_halt_boot` → *debug shell*). The "corrupt" image is the
   bootloader's splash: as soon as the SMMU takes the MDSS (SID `0x820`/`0xc20`), reading it fails. **Do not touch buttons
   after installing.** Also, entering TWRP with buttons leaves `param[0] = 2` (back to TWRP): it is
   cleared as `flash-pmos.sh` does (`param` word 0 and 32 KiB of `misc`).
2. Booting without touching anything: system up (SSH after 30 s), everything loaded (sound, microphones, BT, vibration,
   buttons, touchscreen, EAS, L3) **except the display**: `ae90000.displayport-controller` without a driver, so
   `msm` (DPU + DSI + DP components) never creates the DRM card. Cause: the Type-C module was called
   `max77705`, the same as the (built-in) MFD; udev's `modprobe max77705` resolved to the built-in one and
   loaded nothing → no Type-C port, no HPD bridge for DP, no display. In the test kernels everything
   was `=y` and it did not show. Patch `0026`: module `max77705_typec` (kernel `r8`).
3. Lesson: test kernels (everything built in) do not test automatic module loading; check for
   name collisions (`modprobe -n -v <module>` prints nothing if it thinks it is already there).

### 2026-11-02 — Full review of `r8` (`scripts/diagnostics/full-review.sh`)
1. Good: display (DSI 1080×2340 at 120 Hz, brightness), DP/USB-C (controllers bound; testing with
   an adapter is missing), CPU (scales from minimum to maximum; with the 8 cores, gold and prime give ~20 % more than in
   the test kernels thanks to the L3 votes), GPU (315→840 MHz, up to 3243 fps), Wi-Fi, audio,
   microphones, battery/charging, ADSP/CDSP/SLPI, buttons, touchscreen, vibration. Login: 10 s on the first
   boot of a clean install (Plasma caches), 4.8 s on the following ones.
2. Sensors and Bluetooth: rows 27 and 28. Bluetooth diagnosis with `scripts/diagnostics/bt-diag{,2,3,4}.sh`
   (as root; `btmon` from `bluez-btmon`): the chip and the ROM are fine and power off/on without problems; what
   broke was `bootmac`'s address change and an initial `HCI_RFKILLED`.
3. Minor: `systemd-firstboot` masked in the device package (it always fails with 208/STDIN because of
   the ABL's `console=null` and leaves the system "degraded" on the first boot); PMK8350's ADC without
   channels disabled in the DT (`-EINVAL` on every boot; kernel `r9`). Harmless noise: the warning
   `dsi0_phy_pll_out_dsiclk already disabled` when loading `msm`, a failed `app-pulseaudio@autostart` (Plasma
   tries to start a second PulseAudio), a GPT warning on `loop0` (the image's backup header).
4. Updating the phone without TWRP and without erasing anything: `bash port/build-packages.sh` (packages only) and
   `bash port/update-phone.sh` (copies the `.apk` files, `apk add`, flashes `/boot/boot.img` and
   `/boot/vendor_boot.img` to their partitions and reboots). The phone trusts the `pmos@local` key.

### 2026-11-02 — Hangs 3–7 min after booting (open)
1. Symptom: the phone freezes completely (no SSH or display, no watchdog reset) between 3 and
   7 min after booting. Seen with test kernel #40 (08:53), `r7` (12:34) and `r8` with the
   sensors active (13:25). `r8` with the sensors inactive held for 25 min and `r9` (kernel `#10`)
   for 10 min without problems (`scripts/diagnostics/stability-watch.sh`).
2. It only happens with kernels that carry the EAS capacities and the L3/DDR votes (row 26). Main
   suspect: `epss_l3`'s `perf_state` writes (driver `osm-l3`); Samsung's kernel votes the
   L3 per CPU (registers `0x90 + domain×0x1000 + cpu×4`), not with a single vote per domain.
3. If it happens again: enter TWRP directly (Vol+ + Power, without booting Linux again) and save
   `/proc/last_kmsg` and `/sys/fs/pstore/*`; then try a kernel without the L3 part (keeping EAS).
4. **New lead (Arch, 2026-11-02 18:26):** suspending (`deep`) leaves the phone exactly like that (no
   display, USB or SSH, no reset) and Plasma asks for it with the power button or after inactivity. The
   pmOS "hangs" were probably suspends (it cannot be checked: that journal was erased when
   installing Arch). In Arch suspend is disabled since `device-samsung-r9q 1-7`; if with that it does not
   "hang" again, this was the cause and not `epss_l3`.

### 2026-11-02 — Arch Linux ARM, phase 1 (`scripts/`, plan in `docs/arch-plan.md`)
1. Building without sudo: rootless podman + qemu-user. Base: the official ALARM tarball, checked (md5 and
   the signature of key `68B3537F…5DBE6A6`). `build-packages.sh` builds in an aarch64 container `qrtr` 1.2,
   `rmtfs` 1.3, `tqftpserv` 1.3 and `hexagonrpcd` 0.4.0 (+ our patch) and repackages the `r9` kernel and the
   firmware from pmOS's `.apk` files (the same binaries and module signatures). Arch's `device-samsung-r9q`
   shares UCM, sensor rules, modprobe, the `iio-sensor-proxy` drop-in and `kwinrc` with the pmaports one
   and adds what other packages give in pmOS: a pacman hook that builds and writes `boot`/`vendor_boot`
   (`r9q-bootimg`, the same values as `deviceinfo`), an NCM USB gadget + DHCP (`172.16.42.1`), Bluetooth without
   `bootmac` (`r9q-bt-power`), an rmtfs drop-in without `-s`, `soc-qcom` settings (WirePlumber, UPower), a stable
   Wi-Fi MAC through NetworkManager (`wifi.cloned-mac-address=stable`).
2. Lesson: under qemu-user the setuid bit does not count (binfmt without the `C` flag), so `sudo` from the
   `builder` user fails and `makepkg -s` cannot install dependencies → root installs the
   `makedepends` and the build uses `makepkg -d`.
3. Image (`build-image.sh` + `image/setup.sh`): `linux-aarch64` and all of `linux-firmware*` are removed
   (`NoExtract` for `qca/*` and for WCN6855's `board-2.bin` in `pacman.conf`), Plasma 6.8 with
   `plasma-login-manager` and `plasma-keyboard` (as in pmOS), PipeWire instead of PulseAudio, the same user,
   password, locale and time zone as `pmbootstrap-r9q.cfg`, the PC's SSH keys; `systemd-networkd` disabled in favor
   of NetworkManager; the pacman keyring and the host's SSH keys are created on the first boot. mkinitcpio's
   initramfs only with `base systemd modconf fsck` (UFS and ext4 are in the kernel). ext4 root (4 KiB, no
   `orphan_file` so TWRP can mount it) straight on `userdata`, `x-systemd.growfs`.
   Check beforehand: `scripts/check-image.sh`; install: `scripts/flash-twrp-adb.sh
   --yes-erase-userdata` (**it erases pmOS**; its images stay in `port/out`).
4. First boot (17:54, a 6.5 GB image, `device-samsung-r9q 1-1`): it boots the first time; USB network and SSH
   ~100 s after flashing; root grown to 104 GB; Plasma session (Wayland) at 31 s. The same as pmOS
   (`scripts/diagnostics/full-review.sh`, which now works for apk and pacman): DSI 1080×2340 at 120 Hz, Adreno 660,
   EAS/L3, USB-C/DP bound, battery/charging, ADSP/CDSP/SLPI, Bluetooth on, touchscreen, buttons,
   speaker and microphone through PipeWire with our UCM (HiFi profile). Stable > 9 min.
5. The clock starts in **1970** (`RTC time: 1970-04-17`): the PMIC's RTC only counts from its last
   reset and Android adds an offset Linux does not know about. `pacman-key --populate` failed ("key created
   in the future"). First attempt (`1-4`): `/usr/lib/clock-epoch`; it is not enough by itself, because systemd only applies it
   inside the initramfs (which does not carry it) and timesyncd only saves the time after syncing through
   NTP. Fix (`1-5`), as Android does: `r9q-clock` stores the offset "real time − RTC" in
   `/var/lib/r9q/rtc-offset` (after an NTP sync, at shutdown and from `update-phone.sh` right after
   setting the PC's time) and at boot, before `sysinit.target`, sets RTC + offset (the RTC keeps
   counting with the phone off); without an offset, at least the package's date (`clock-epoch`).
   Careful (`1-6`): `rtc-pm8xxx` is a module and when it registers the kernel (`CONFIG_RTC_HCTOSYS=y`) sets
   the RTC's time again ("setting system clock to 1970-04-17", at 6.3 s), so `r9q-clock` cannot go at
   a fixed point of the boot: a udev rule starts it when `rtc0` appears. (With the driver inside the
   kernel the clock would be set before userspace; a candidate for the next kernel.)
   The pacman keyring service moves into the package, waits for `rtc0`/`r9q-clock` and is retried on every
   boot until it works. With `1-6`: correct time at 6.5 s (RTC + offset) and keyring created.
6. Sensors: only light. Upstream's `80-iio-sensor-proxy.rules` only declares `ssc-light ssc-compass` on
   `fastrpc-sdsp`; pmOS adds `ssc-accel ssc-proximity` in `postmarketos-base-ui` (rule 90). Copied into the
   package (`1-4`), together with pmOS's NetworkManager configuration (random MAC when scanning and stable
   per network; the interface is called `wlp1s0` in Arch, not `wlan0`), `udmabuf`, `iio-sensor-proxy`'s
   `TimeoutStopSec=3` and `QT_QUICK_CONTROLS_MOBILE`.
7. **Suspend = hang.** In one boot, at 14.5 s the login screen asked to suspend
   (`suspend requested from client 'plasma-login-gr'`, almost certainly the power button) → `PM: suspend
   entry (deep)` and nothing else: no display, USB or SSH until a forced reboot. `/sys/power/mem_sleep`
   = `s2idle [deep]`. When suspending, `iio-sensor-proxy` also aborted (libssc: "code should not be
   reached" with a proximity report). Temporary fix (`1-7`): `sleep.conf.d` with
   `AllowSuspend=no` (and no hibernation), `Restart=always` for `iio-sensor-proxy`. Pending: try
   `s2idle` (`mem_sleep_default=s2idle`) carefully.
8. **Power button** (`1-8`): at the login screen nothing of Plasma handles it and logind applied its
   default (`Power key pressed short` → `Powering off`); with the cable plugged in the ABL then boots
   in charging mode (`androidboot.mode=charger`) and boots Linux again, it looks like a reboot.
   `logind.conf.d`: short press ignored, long = power off; `/etc/xdg/powerdevilrc`:
   `PowerButtonAction=128` (screen on/off, like Plasma Mobile) and no automatic suspend.
   Pending: an own charging mode when `androidboot.mode=charger`.
9. **Phase 2 (Steam, like ArmadaOS)**: packages `gamescope-session-plus` and `gamescope-session-steam`
   (OpenGamingCollective, the same commits as Terra/ArmadaOS, SHA-256 checked) and `steam-session-r9q`:
   `/usr/bin/steam` starts Valve's native arm64 client (manifest `steam_client_steamdeck_stable_linuxarm64`)
   and the first time installs it in `~/.local/share/Steam` (`r9q-steam-bootstrap`: package
   `bins_linuxarm64` with the manifest's SHA-256 + the pinned arm64 `steamrt3c` runtime, as ArmadaOS does);
   `plasma-login-manager` autologin to `gamescope-session-steam` (`Relogin=true`), "Switch to Desktop"
   → hook `/usr/lib/os-session-select` → `r9q-session-set` (pkexec, active local session only) and
   "Game Mode" in Plasma to go back; every boot goes back to the game mode; gamescope on `DSI-1`,
   `ORIENTATION=left`. Client downloaded on the phone (1792618285, 654 MB). Valve's zip carries
   directory entries with `\` (empty) that `bsdtar` leaves as they are: they are deleted.
10. **pacman does not sync**: pacman 7 downloads inside a sandbox with Landlock and the kernel does not have it
    ("Landlock is not supported by the kernel"). The real fix: kernel `r10` with
    `CONFIG_SECURITY_LANDLOCK=y` (it was already first in `CONFIG_LSM`) and, while at it, `CONFIG_RTC_DRV_PM8XXX=y`
    (the clock no longer goes back to 1970 when the module loads). Disabling pacman's sandbox is not done by
    default (it weakens security). Kernel `r10` installed (`#11`): `landlock: Up and running`.
11. **Game mode working** (`update-phone.sh --sync`): autologin → gamescope 3.17 (Turnip, `DSI-1`
    1080×2340@120, Synaptics touchscreen bound to the panel, `--force-orientation left`) → Steam arm64. Problems
    of the first boot and fixes (`steam-session-r9q 1-2`/`1-3`):
    - Steam starts at 10 s, before the Wi-Fi: it cannot update and the attempt fails (the
      following ones do update, 3.3 GB).
    - `steamui.so` needs `libgtk-x11-2.0.so.0` (GTK 2 is no longer in Arch): it is linked from Valve's
      `steamrt3c` runtime in `~/.local/share/Steam/lib/aarch64-linux-gnu` (as ArmadaOS does with `libibus`),
      refreshed at every start by `/usr/bin/steam`.
    - `vgui2_s.so`/`steamclient.so` need `libopenal.so.1` → dependency `openal`.
    - **Black screen** with Steam and gamescope running: `gamescopectl focus_info` → "Global focus
      window: none" (there is no window to show). Steam checks with `lsof` who connects to its UI's
      websocket; without `lsof` it rejects the connection (`WebUITransport: Connection rejected`, "lsof is
      required to run steam") and the Big Picture window is never created → dependency `lsof` (`1-3`).
      To debug remotely: `gamescopectl focus_info` (it goes to the session's journal).
    - With `1-3`: window "Steam Big Picture Mode" (appID 769) focused and on screen; screenshot with
      `gamescopectl screenshot /tmp/x.png` (2340×1080): Steam's first-run assistant, network screen
      (Steam uses NetworkManager over D-Bus). The touchscreen responds.
    - Orientation: `ORIENTATION=right` (with `left` it was upside down for the user), `steam-session-r9q 1-4`.
      To test without sudo: `~/.config/gamescope-session-plus/sessions.d/steam` (read after the one in
      `/etc`) and restart the session with `systemctl --user stop gamescope-session-plus@steam` (the login
      manager comes back in; `steam -shutdown` did not close the client).
    - Steam's `libav*` ask for `libavutil.so.59` (ffmpeg 7; Arch has 61): only recording/streaming.
    Result: web UI loaded (`FirstPaint`), GPU-accelerated (ANGLE on freedreno FD660, GL 4.6),
    0 failed sessions. After 5 short sessions in a row gamescope-session-plus goes back to Plasma by itself.
12. **Bluetooth controller (DualShock 4) with the ROM firmware**: it pairs and the kernel registers it
    (`hid-playstation`), but (capture `scripts/diagnostics/bt-gamepad-diag.sh`, btmon):
    - when reconnecting, the controller opens the HID channel (`PSM 17`) before the link is encrypted and the kernel
      rejects it (`Connection refused - security block`, normal in Linux with SSP); encryption arrives 230 ms
      later (slow) and the controller does not retry: "connected" without data and BlueZ cuts it after ~35 s;
    - when the channel does open, the chip crashes 2 s later (`hardware error 0x8c`, memory dump).
    With Samsung's patch + NVM **unmodified** (`hpbtfw21.tlv` BTFW.HSP_C.2.1.1-00382 +
    `hpnv21g.baa`, a reversible test with `scripts/diagnostics/bt-fw-switch.sh patch|rom`) the DualShock 4 works.
    Packaging: `firmware-samsung-r9q 1-6` installs them in `/usr/lib/firmware/updates/qca/` (outside the
    `NoExtract` of `qca/*`); with them the chip starts without an address ("unconfigured") and
    `device-samsung-r9q 1-9` (`r9q-bt-power`) gives it a fixed one derived from the machine-id (`02:…`, local bit).
    **Pending**: with the patch LE connections dropped (`0x3e`, row 20); they have to be tested again.
13. **Real Wi-Fi MAC and Bluetooth address** (`device-samsung-r9q 1-10`): with no address in OTP, ath11k's
    firmware makes up a different `00:03:7f:12:xx:xx` on every boot, and Steam ties each saved network
    to the MAC of the moment (`client_networkmanager.txt`: "Upgrading connection … to mac-address"):
    after a reboot it does not match and NetworkManager does not connect by itself (each connection from Steam creates another
    saved network). Also, Bluetooth with the patch starts without an address and `r9q-bt-power` ran before
    the NVM finished loading (a race, `Invalid Index`). Fix: `r9q-macs` reads Samsung's addresses
    from the `efs` partition (mounted `ro,noload`: `/wifi/.mac.info`, `/bluetooth/bt_addr`) into
    `/etc/r9q/macs` and `r9q-bootimg` writes them into the device tree (`local-mac-address` in
    `wifi@0`, `local-bd-address` in `bluetooth`, least significant byte first; ath11k and btqca
    use them: `device_get_mac_address`, `HCI_QUIRK_USE_BDADDR_PROPERTY`). The install script unties
    Steam's networks from the `00:03:7f:12:*` MACs. `r9q-bt-power` waits for the chip to report its
    configuration.
    Checked: permanent Wi-Fi MAC `XX:XX:XX:XX:XX:XX`, automatic connection at 14.9 s;
    Bluetooth configured directly with `XX:XX:XX:XX:XX:XX`; DualShock 4 paired again and connected.
14. **First game**: Hollow Knight: Silksong (Windows x86) starts with **Proton 11.0-2 (ARM64)** + Steam
    Linux Runtime 4.0 arm64 (Steam downloads them itself) and reaches its language menu; it looked hung
    because the controller did not reach the game: Steam could not open `/dev/uinput` ("Couldn't initialize virtual
    gamepad") nor the controller's `hidraw` (root, no ACL). Fix (`steam-session-r9q 1-5`): Valve's udev rules
    `60-steam-input.rules` (repository `ValveSoftware/steam-devices`, pinned commit, SHA-256),
    which the `steam` package brings on Arch x86: `uaccess` for `uinput` and the controllers' `hidraw`.
    Pending: Steam/gamescope without `CAP_SYS_NICE` ("failed to set thread priority").
15. **Performance overlay**: in game mode it is drawn by MangoHud's `mangoapp` (`STEAM_USE_MANGOAPP=1`),
    which Arch Linux ARM does not package. `packaging/mangohud`: Arch's PKGBUILD (0.8.4, b2sum of the
    official tarball with subprojects) for aarch64, without XNVCtrl or tests; `steam-session-r9q 1-6` depends
    on it. Careful: `build-packages.sh` builds with `makepkg -d`, so the libraries a package builds against
    must also be in `makedepends` (it failed with "wayland-client not found").
    **GPU always at 0 %**: the kernel does measure the load (the game's fdinfo, `drm-engine-gpu`: ~70 % with
    Silksong), but MangoHud names the GPU by the platform driver (`msm_dpu`) and fdinfo says
    `drm-driver: msm`, so it dropped every descriptor. Patch
    `packaging/mangohud/0001-fdinfo-match-msm-driver-name.patch` (`mangohud 0.8.4-2`). Upstream
    rewrote that part in July 2026 ("mangohud-next").
16. **Controller that does not reconnect after pairing it from Steam**: Steam leaves it `Bonded: yes` but
    `Trusted: no`, and BlueZ does not accept without authorization the reconnection the controller starts (PS button).
    One-off fix: `bluetoothctl trust <MAC>` (no root needed). Pending: automatically marking controllers
    paired from Steam as trusted.
17. **The game slows down until it closes: lack of memory** (`scripts/diagnostics/perf-monitor.sh`, every 5 s):
    with Silksong the available memory drops from 2.5 GB to 50–150 MB in 1.5 min, `kswapd0` shows up, the CPU
    pressure (PSI) rises from 4 to 20–42 and at 07:49:50 the OOM killer kills the game (`Killed process … (Hollow
    Knight S)`, 1.4 GB anonymous). The kernel sees ~5 GB and **there was no swap**: the only thing it could drop was the
    cache and the programs' code (which it read from disk again and again). pmOS uses zram
    (`postmarketos-zram`) and in Arch it had not been set up. Fix (`device-samsung-r9q 1-11`): `zram-generator`
    with 150 % of the RAM in zstd and priority 300, and `sysctl.d` as in pmOS (`vm.swappiness=180`,
    `vm.page-cluster=0`, `vm.min_free_kbytes=100000`). Along the way: the GPU reached 86 °C and the kernel throttled it
    (`devfreq-3d00000.gpu` cooling 2–4), and `mangoapp` uses ~40 % of a core drawing the overlay at 120 Hz.
    **Tested**: with zram (~7.5 GB, 150 % of the ~5 GB the kernel sees) the game no longer closes.
18. **Two editions installable from TWRP without a PC** (`artifacts/`, 2026-11-07): `EDITION=kde` (Plasma with its
    login screen, no Steam) and `EDITION=steam` (the same + autologin into the game mode, Steam already
    downloaded). `setup.sh` installs the game packages and the autologin only in `steam` and stores the edition
    in `/etc/r9q/edition`; `check-image.sh` checks what is specific to each one (and that KDE carries nothing of
    Steam). `make-twrp-zip.sh` packages the image as a TWRP ZIP: `rootfs.img.gz` (gzip, because TWRP
    has `unpigz` but neither zstd nor xz; the entries are stored uncompressed in the ZIP), `boot.img`,
    `vendor_boot.img`, `manifest.txt` (sizes and SHA-256) and `update-binary` (a `mksh` script). The installer
    does the same as `flash-twrp-adb.sh` but checks everything **before** writing: model
    (`ro.boot.em.model`), that the ZIP is not in internal storage (that is `userdata`, what gets erased),
    sizes and SHA-256 of each piece; then it streams `userdata` (`unzip -p | unpigz | dd`), verifies
    it with the image's SHA-256 and writes `boot`/`vendor_boot`/`dtbo`/`param`/`misc`. The ZIP
    must stay under 4 GiB (TWRP's USB drives are FAT32). `twrp/test-installer.sh` tests it
    on the PC with fake partitions (normal install, wrong model and damaged ZIP; in
    the last two nothing is written). The **real MACs** no longer need `update-phone.sh`
    (`device-samsung-r9q 1-12`): `r9q-macs.service` reads them from `efs` on the first boot, before the
    login, rebuilds `boot.img` and reboots once.
19. **Public images and repository** (2026-11-08): `PUBLIC=1` in `build-image.sh`/`check-image.sh`
    (user `alarm`/`alarm`, no SSH keys from the PC, en_US/UTC) and `build-release.sh` (both editions,
    checked and installed on the PC with `test-twrp-zip.sh`) → `artifacts/release/`. SSH: password only
    over the USB cable (`Match Address 172.16.42.0/24`), keys only from Wi-Fi; `setup.sh` validates it with
    `sshd -T` (OpenSSH 10 writes the options in CamelCase: compare case-insensitively). The scripts'
    paths are in `scripts/paths.sh`; `port/publish/export-repo.sh` exports the public repository
    (RaikaShinohara/alarm-r9qb2, with the layout of agcarbajo/ubuntu-galaxy-tab-s9-ultra), removing private
    data and checking it.

### 2026-11-08 — Android + Linux dual boot, Xiaomi Pad 5 style (`dualboot/`)

The mechanism of the Pad 5 projects (Project-Aloha's DualBootKernelPatcher, the "boot manager" variant of
rodriguezst/nabu-dualboot-img): **Android's** `boot.img` carries in its kernel a selector of a few
instructions and a UEFI; Samsung's ABL keeps booting Android as always (its `vendor_boot`, its
`dtbo`) and the selector decides what to run. Tested end to end on the phone (with Arch playing
"Android", because Android was not installed):

| Step | What happens |
|---|---|
| Power-on | no mark → the selector copies the UEFI to `0x9FC00000` and jumps → systemd-boot menu → Arch through UEFI |
| Menu "Android" | `Reboot2Android.efi` fills the page at `0x17FE00000` (4 KiB) with a pseudo-random pattern (xorshift64), with the MMU off, and resets with PSCI `SYSTEM_RESET` (before: a single `0xC0DEADDED`, see point 15) |
| Next boot | the selector compares the page bit by bit; if fewer than 3/8 of the bits differ it clears it and jumps to the kernel with the registers the ABL left (Android) |
| The reboot after | no mark any more → menu again |

1. **UEFI**: the **official Mu-Silicium v3.0.1** (`Mu-r9q.tar`, October 2024) boots on the bit F
   bootloader (`G990B2XXSFHYI1`). The one built from the current `main` (`r9qb2`, "Inactive", asks for BIT-18) gets stuck in
   UFS (the DEBUG build showed it) and the XBL logs *Warm Reset by Watchdog Bite*: **use the
   official files**. The FD is taken from the official image (gzip of a 144-byte BootShim + a 3 MiB FD,
   base `0x9FC00000`, `_FVH` at `0x28`): `work/R9Q_UEFI-v3.0.1.fd`.
2. **Linux through UEFI works**: systemd-boot + kernel 7.2.13 uncompressed (the EFI stub needs a PE;
   `EFI_ZBOOT` is disabled) + initramfs + `devicetree` + `acpi=off`. Display, GPU, Wi-Fi, BT,
   audio, DSPs and battery fine. Pending: the MAC comes out random (the test DTB does not carry the real ones)
   and Linux sees **4.2 GiB instead of ~5 GiB**: the official UEFI's memory map does not declare
   `0xA0000000–0xBA800000` nor several holes above `0xC0000000` that the ABL does hand the kernel.
   Mu creates boot options from any FAT with `\EFI\BOOT\BOOTAA64.EFI` (no ESP type needed);
   with 4 KiB sectors, `mkfs.fat -F 32 -s 1` (otherwise there are few clusters and EDK2 reads it as FAT16).
   Volume up = Mu's boot manager.
3. **Own selector** (`configs/dualboot/shellcode-r9q.S`) and **own patcher**
   (`scripts/dualboot-patch.py`): the permission system does not allow building/running the
   downloaded DualBootKernelPatcher, so they were rewritten with the same header format
   (`b 0x40` in instruction 0, the original branch in 1, FD base/size and kernel size at
   `0x20/0x28/0x30`, code at `0x40`, FD appended). With Android's `boot.img` (header v3, an uncompressed
   `MZ` kernel of 52 MB) 127 bytes change; it fits in `boot` (96 MiB); re-patching gives the same.
   When jumping to the UEFI it leaves `x1` = FD and `x0` intact, as the official BootShim does.
4. **The mark** (`Reboot2Android.efi`, `configs/dualboot/reboot2android.c`, an AArch64 PE without libraries):
   - Project Mu **does not map free memory**: writing without `AllocatePages(AllocateAddress)` raises an
     exception with no message.
   - The official UEFI's `ResetSystem(EfiResetWarm)` **is not implemented** (it returns and stops at
     `ASSERT` in `ResetSystem.c(334)`); its cold reset wipes the RAM. PSCI is called directly:
     `SYSTEM_RESET` (`0x84000009`, Linux's `reboot`) keeps the RAM and leaves the hardware clean;
     a warm `SYSTEM_RESET2` also keeps the RAM but only resets the CPUs, and whatever boots
     next (the UEFI, our kernel) hangs.
   - The first address tried, the end of ramoops (`0xF0BFFFF0`): the firmware and TWRP write there
     (`pmsg` area) and the mark was lost. **`0x17FE00000`** (the Pad 5's; no DT reserves it, Samsung's only
     reservation above 4 GiB is `0x100000000–0x10AD00000`) works: the diagnosis
     (`MarkDiag.efi` + the selector with `--defsym DIAG=1`) showed the mark seen and cleared and a witness value intact.
5. What is missing: a ZIP that splits `userdata` 50/50 (GPT entry 34, 105 GiB, 4 KiB sectors; TWRP
   has `sgdisk`, `make_f2fs`, `mke2fs` and `mkfs.fat`) with an ESP + a Linux partition; reinstalling Android;
   patching its `boot` from TWRP (without Python: a static patcher); Arch in its partition with the kernel/DTB
   (real MACs) in the ESP; fixing the UEFI's memory map (it would touch the UEFI: ask).

6. **ZIP to split the storage** (`dualboot/split/`, not flashed yet):
   `make-split-zip.sh` → `artifacts/r9q-dualboot-dividir-50.zip`. A single `sgdisk` call
   (`--set-alignment=1`: otherwise it may round the start of `userdata`) rewrites 34 and creates
   35 `esp` (512 MiB, FAT32 `-s 1`) and 36 `linux` (ext4); a copy of the GPT next to the ZIP; it formats
   `userdata` as f2fs and empties `metadata` (like Format Data) only in the same pass that splits; if it is already
   split it touches nothing (except giving 35/36 a filesystem if they have none). On this phone:
   Android 52.5 GiB, ESP 0.5 GiB, Linux 52 GiB (4 KiB sectors, everything aligned to 2 MiB).
   `test-split.sh` tests it on the PC (split, repeat, another disk, a foreign entry 35) and
   `R9Q_SPLIT_DRYRUN=1` runs it on the phone without writing (it passes). Notes: the disk GUID
   (`98101B32-…-2BB33D000C20`) is the same as on the Tab S9, so it does not identify the phone (the
   model and the exact position of `userdata` are checked too); TWRP's `sgdisk` prints
   `Sector size (logical/physical): 4096/4096`; through `adb shell` `/proc/self/fd/1` cannot be
   reopened (use `9>>file` as OUTFD).
7. **Android after splitting**: its `system` stays in `super` (untouched); the original `boot`, `vendor_boot`
   and `dtbo` (`dump/`) are enough, with `boot` patched by `dualboot-patch.py`. Odin with stock
   firmware works too, but only with **HOME_CSC** and without *Re-Partition* (the normal CSC carries a PIT and
   would undo the split) and it overwrites TWRP.

8. **Installed** (2026-11-08, `dualboot/install-android-dual.sh --yes-erase-userdata`): the original GPT in
   `dualboot/backup/gpt-sda-before-split.bin`; split 52.5 / 0.5 / 52 GiB. TWRP's kernel did not reread
   the table in the first pass (the ZIP detects it and stops): `adb reboot recovery`; TWRP puts a
   device-mapper on top of `userdata` (`dm-4`) and `make_f2fs` says *In use by the system*, so the Format
   Data goes with its own command, `twrp format data` (it undoes the dm, f2fs + `metadata`). Then:
   `cache` restored, ESP (35) with systemd-boot and the **Android** entry (default, 10 s),
   `vendor_boot`/`dtbo` from the ROM (`dump/`) and the dual `boot`. **Android (the S23 port ROM) boots from
   the menu.** Arch is missing in `linux` (36) with the kernel/DTB/initramfs in the ESP.
   After an `adb reboot recovery` the phone always stayed in TWRP: `param[0]=02` and the `boot-recovery`
   BCB in `misc` (row 1 of the table); clear both before leaving TWRP.
9. **Arch in the dual boot** (`device-samsung-r9q 1-13`, `DUAL=1`): `BOOT_MODE=uefi` in
   `/etc/r9q/bootimg.conf`; `r9q-bootimg` no longer writes `boot`/`vendor_boot` (they are Android's) but
   `/efi/arch/{Image,initramfs.img,r9q.dtb}` (uncompressed kernel, DTB with the real MACs) and the entry
   `/efi/loader/entries/arch.conf` (`root=PARTLABEL=linux … acpi=off`), and renews systemd-boot in the
   ESP when it changes (the hook also fires on `systemd-bootaa64.efi`); `fstab`: root
   `PARTLABEL=linux`, ESP in `/efi`. `build-image.sh DUAL=1` → `out/$EDITION-dual/{arch-r9q.img,esp/}`;
   `check-image.sh DUAL=1` checks it (Image an AArch64 PE, the r9q's DTB, an entry without `userdata`);
   `make-twrp-zip.sh DUAL=1` packages it with `twrp/update-binary-dual`, which only writes `linux` and
   Arch's files in the ESP (it checks the split and the dual kernel in `boot` first; it never touches
   `userdata`, `boot`, `vendor_boot`, `dtbo` or the Android entry). `test-twrp-dual.sh` tests it
   (install, no dual kernel, not split, damaged ZIP).
   **Installed and tested** (KDE, `artifacts/r9q-arch-kde-dual-20261111.zip`, run from TWRP with the ZIP
   in `/tmp`): menu with Arch (default, 5 s) and Android; Arch boots through UEFI with the root on `sda36`
   and the ESP in `/efi`, without failed services; on the first boot `r9q-macs` put the real MACs into
   the ESP's DTB and rebooted once (the MAC NetworkManager shows without a connection is the random scanning
   one; the permanent one is Samsung's). Fix for the following images: the pacman hook
   built `boot.img`/`vendor_boot.img` in `abl` mode while packages were installed; `setup.sh`
   deletes them in `uefi` mode.
10. **RAM with the UEFI** (2026-11-11): Linux saw 4.2 GiB through UEFI against ~5 GiB with the ABL. The
    official UEFI's memory table (the SEC module's DeviceMemoryMapLib, uncompressed in the FD at
    `0xC160`, 72 bytes per entry) does not declare ~870 MiB below 4 GiB that the ABL does hand over
    (`0xA0000000–0xBA800000`, the `Kernel` area of Qualcomm's `uefiplat.cfg`, among others).
    `scripts/fix-uefi-memmap.py` reuses 4 entries the UEFI does not need (`Hyperisor`,
    `Axon DMA`, `SOD Test`, `Guest VM`) for the 4 largest free ranges (the ABL's RAM minus all
    of our DT's reservations, including TrustZone's `tima`/`kaslr`/`hdm`): 742 MiB, 68 bytes
    changed, the SEC file has no data checksum (0xAA). Result: **4.92 GiB**
    (5 158 988 kB), UEFI boot without failed services; zram becomes 7.4 GB. Current dual
    `boot`: `dualboot/out/boot-android-dual-ram.img` (to go back: `boot-android-dual.img`).
11. **The UEFI hung after a software restart** (from Linux, Android or TWRP, with the USB cable
    connected; after a forced restart with the buttons it was fine). A photo of the screen:
    `ReplaceTableEntry: splitting block entry with MMU disabled` and a synchronous exception in `ArmCpuDxe`
    +0x4C58 (and another one while dumping the state). The disassembly: ArmMmuLib splits a live 2 MiB block that
    holds its own code or its table by turning the MMU off for the change, and when it comes back the CPU can no longer
    execute (the exception is exactly on the return address). First, zeroing the UEFI's own
    regions from the selector was tried (in case they were RAM leftovers from the previous boot): it does not
    fix it (it is kept, it does no harm). Fix, `scripts/fix-uefi-mmu.py`: one instruction in
    `ArmCpuDxe` (`0x4c24`) and another in `DynamicRamDxe` (`0x2ff0`, the same ArmMmuLib): the "MMU
    off" branch jumps to the next iteration of the loop, that is, that block is not split and keeps its
    attributes. They are in the LZMA-compressed volume (FFS at `0x10108`): it is decompressed, patched
    (8 bytes), recompressed with the LZMA "alone" header EDK2 expects and the file's header is rebuilt
    with its checksum. **Tested**: restart from TWRP with USB connected → menu → Arch (4.92 GiB,
    without failed services). Current dual `boot`: `dualboot/out/boot-android-dual-mmu.img` (FD
    `R9Q_UEFI-v3.0.1-ram-mmu.fd`).
12. **Fixed TWRP** (2026-11-11, `scripts/make-twrp-fix.sh work/recovery.img OUT`). Two bugs
    of TWRP 3.7.1_12-Edward0181-test:
    - *Leaving TWRP always came back to TWRP*: the ABL's log says `PARAM Flag is PARAM_BOOT_RECOVERY_ENTER`
      with no keys pressed; the ABL sets `param[0]=02` every time it enters recovery and only Samsung's
      recovery clears it (TWRP also leaves `boot-recovery` in `misc`). Service `r9q_clearflags`
      (`init.recovery.r9q.rc`, imported from `init.recovery.qcom.rc`) that clears both every 3 s
      while TWRP runs (it only writes if they are set).
    - *It stayed at TWRP's logo*: with Android encrypted it tries to decrypt user 0 with the `weaver`
      HAL, which its `vendor/etc/vintf/manifest.xml` declares but does not exist in that TWRP, and
      `getService` waits for it forever (logcat: `Waited one second for …IWeaver/default` in a loop).
      Removing `fileencryption`/`keydirectory` from `recovery.fstab` is not enough: TWRP copies the fstab from
      `/vendor` to `/etc/additional.fstab` and uses it to decrypt. The `weaver` entry is removed from the
      manifest: TWRP fails at once (`Unable to decrypt with default password`) and shows the menu.
      `/data` (Android) stays encrypted and unmounted; the Arch install does not use it.
    Only files are added (a second cpio at the end of the ramdisk; kernel, dtb, recovery_dtbo and header
    the same byte for byte); the script is reproducible. **Installed and tested**: `adb reboot recovery` →
    TWRP's menu, `param` zeroed, service running. To go back: write `work/recovery.img` (the original,
    `8d4557d1…`) to `recovery`. The five files are in the
    [TWRP device tree fork](https://github.com/RaikaShinohara/twrp_device_samsung_r9q/tree/r9q-dualboot).
13. **Dual boot release in a single ZIP** (2026-11-11, `configs/twrp/dualboot-update-binary`, `scripts/make-dualboot-release.sh`): Arch KDE (public image
    `alarm`/`alarm`, `PUBLIC=1 DUAL=1`) next to the installed Android, on 128 and 256 GB.
    `update-binary` (TWRP runs it): a menu on the volume keys and Power (Keep if it is already
    split, Linux 25/50/75 %, Cancel) and a second confirmation; it checks the model, the GPT
    (34 = userdata, 35/36 = esp/linux or nothing), Android's `boot` (v3/v4, uncompressed arm64 Image,
    not Linux's 7.x kernel) and the SHA-256 of everything before writing. Split: a single `sgdisk`
    (the rest of the GPT intact) and TWRP's kernel learns about it through **BLKPG** (`del`/`resize`/`add` of one
    partition; `--rereadpt` fails with any `sda` partition open), without a reboot. An own Format Data
    (empty ext4 metadata + `make_f2fs -g android`). If BLKPG fails, the GPT stays written, userdata
    zeroed and the user is asked to reboot to recovery and repeat with "Keep", which formats userdata if it is zeroed
    or has an f2fs larger than the partition (an encrypted Android looks like noise and is not touched), and the ESP if it is not
    FAT32. The `boot` patch is done in TWRP itself with `dd`/`od`/`printf` (mksh has
    32-bit arithmetic: sectors and bytes go through `awk`) and gives the same, byte for byte, as `dualboot-patch.py`;
    the original `boot` is kept in the ESP (`r9q/boot-android-original.img`). `r9q-tool.c`: a
    static AArch64 binary without libc (direct syscalls) with `keys` (EVIOCGRAB of the devices with
    Vol+/Vol−/Power so TWRP does not turn the screen off with Power; it ignores presses with the brightness at 0)
    and `blkpg`. `make-release-zip.sh` rebuilds each piece from its source (official FD + `fix-uefi-
    memmap.py` + `fix-uefi-mmu.py` = `3331906e…`, TWRP with `make-twrp-fix.sh`) and puts it into Arch's
    ZIP. `test-release.sh`: the installer in a sandbox (`bwrap`) whose `/` is TWRP's ramdisk
    (its mksh, toybox, sgdisk, make_f2fs under qemu-user), with fake 128 and 256 GB phones (a GPT like
    the r9q's, partitions as files): **148/148** (A 256 GB 50 %, B 128 GB 25 %, C 128 GB 75 %,
    D keep: Android's data and GPT intact and `boot` re-patched the same, E split again, F an interrupted
    split, G cancel/"No"/dry run/model/Linux kernel/damaged ZIP without writing anything).
    Under qemu-user `dd` fails with blocks > 64 KiB (`Bad address`): the test uses `R9Q_DDBS=65536`; on the
    phone 4 MiB (tested with the earlier installer). `od` collapses repeated lines with `*`: zeros
    are counted with `tr -d '\000' | wc -c`.
    **On the phone (128 GB, fixed TWRP)**: dry run (`R9Q_DRYRUN=1`, through `twrp install`): menu on
    screen, Vol± move, Power selects and the screen does not turn off (EVIOCGRAB of `qpnp_pon` = Power/Vol− and
    `gpio-keys` = Vol+); the `boot` it would write is identical byte for byte to `dualboot-patch.py`'s and to the
    installed one; GPT and `param` unchanged. There are two backlights: `panel` always reads 0 and `panel0-backlight`
    is the real one: the one that is lit when the menu starts is used. BLKPG on the real kernel: `resize` of
    `sda36` to its own size → 0, with a wrong start → EINVAL (structure and semantics correct).
14. **"Android" in the menu went back to the UEFI after the MMU fix** (2026-11-11, installing the release
    with "Keep"; the `boot` written was identical byte for byte to the one that worked). Android booted
    from the menu on the 8th and the 11th with the RAM-fixed UEFI; it stopped with the MMU one. Cause:
    `Reboot2Android.efi` reserved the mark's page with `AllocatePages`, and Project Mu maps it with
    SetMemoryAttributes, which has to split a live block: exactly what `fix-uefi-mmu.py` skips.
    The page stays unmapped and writing the mark fails, the selector does not see it and boots the UEFI.
    Fix (`reboot2android.c`, `mark_and_reset`): the mark is written with the MMU and the data cache
    off (SCTLR_EL1/EL2 M and C to 0, depending on CurrentEL; the UEFI is identity-mapped, so it keeps
    executing at the same address), in assembly without a stack (with the MMU off memory is
    Device memory and an unaligned access from the compiler would fault): `dc civac`, witness, mark, `dsb`, PSCI
    SYSTEM_RESET (and SYSTEM_RESET2 if it returned). **Tested**: menu → Android boots.
    Before switching the MMU off that code must be cleaned to the point of coherency (`dc civac`
    by `CTR_EL0` lines) and the instruction cache invalidated: the UEFI only cleans images
    to the point of unification and, without the MMU, instructions are read from DRAM (otherwise, an exception).
15. **"Android" needed 2 or 3 presses** (2026-11-12): from TWRP one was enough; from Android or
    after power-on, the selector did not see the mark once or twice (measured with `adb`: the PC's time minus
    Android's `/proc/uptime`; each round through the menu is ~31 s: 25.7 s for stock, 52 s with one round,
    88–181 s with 2–5). Cause, in the XBL log Samsung keeps in `/proc/last_kmsg` (TWRP): all
    resets are `PM: Reset by PSHOLD` / `Reset Type: Hard Reset`, also the PSCI
    `SYSTEM_RESET` of `Reboot2Android`. In a hard reset DRAM goes without refresh for a moment and
    some bits change (more with the phone warm after Android), so a 64-bit mark
    compared whole often failed. Setting the PMIC's reset type to "warm" over SPMI first
    (PMK8350 PON_HLOS `0x135A/0x135B`, like Linux's reboot notifier) changed nothing: the
    XBL still said `Hard Reset` (TrustZone sets it again). Fix: the mark is the whole page
    (4 KiB) filled with an xorshift64 pattern (seed `0x9E3779B97F4A7C15`), written with the MMU
    off; the selector counts the differing bits (SWAR popcount, without NEON) and accepts if they are fewer than
    12288 (3/8); any other content differs in ~16384 ± 90. Tested on the PC with the real binary
    of the selector under qemu-user (exact pattern, 100–12287 flipped bits → Android and page cleared;
    12288, zeros, ones, random and the old mark → UEFI) and on the phone: 2/2 from TWRP and 11/11
    from Android at the first press (~57 s). Full sequence with the ZIP (`R9Q_KEYS="power down power"`,
    "Keep"): stock `boot` → install → `boot` = `dualboot-patch.py`'s output (`cf917a1d…`) and
    the original kept; reinstall over it ("already dual boot, updated") → the same `boot` byte for
    byte; then Android at the first press and Arch boots. `test-release.sh`: 148/148. The debugging variants were removed (`MarkDiag`,
    `WarmResetTest`, selector `LOG`/`DIAG`): writing to the ESP from the UEFI did not reach the disk
    (`mark.log` never appeared and the logging variant hung).

16. **Linux 100 % and "Remove Linux" in the installer** (2026-11-13, release v1.2.0). New menu:
    Keep / Linux 25-50-75 % / **Linux 100 %** / **Remove Linux: Android 100 %** / Cancel.
    - Linux 100 %: `userdata` keeps an unused 256 MiB (the table is still 34/35/36, so
      splitting again or removing Linux uses the same code) and `boot` holds **only the selector and the UEFI**:
      header and ramdisk of the `boot` that was there, "kernel" = the selector in one page (branch from `0x04` to
      `0x40`: if it ever saw the mark, it clears it and goes back to itself) + the FD; Image header
      `text_offset 0x80000`, `image_size 4 MiB`, `flags 0xA`. `dualboot-patch.py patch-uefi` does the same
      on the PC. No "Android" entry in the ESP.
    - The stock `boot` is kept in the ESP and **moves to the new ESP** when it is formatted again (before,
      it was lost when re-splitting). From Linux 100 % you can split again (Android's kernel comes from that
      copy) or remove Linux.
    - Remove Linux: first writes the stock `boot` (whatever happens next, Android boots), deletes
      35/36, `userdata` takes everything again, BLKPG and Format Data. The fixed TWRP stays.
    - Two bugs that only showed on the phone: `r9q-tool blkpg del` got an empty start/length
      (now 0 0, and `kpart` checks the numbers in the PC test too); and TWRP keeps a
      device-mapper `userdata` on top of `sda34` even unmounted (`make_f2fs`: *In use by the system*) and
      has no `dmctl`/`dmsetup`: `r9q-tool dmremove NAME` (ioctl `DM_DEV_REMOVE`, a 312-byte `struct dm_ioctl`)
      and the installer removes it after unmounting. In TWRP the `by-name/esp|linux` links of
      partitions added with BLKPG do not appear: use `sdaN`.
    - Tested on the phone: dual 50 % → Linux 100 % (`boot` = `patch-uefi`, `61993da7…`, the copy of the stock
      `boot` in the new ESP) and an end-to-end boot with no one at the phone: a systemd-boot test entry with
      `systemd.run="sh -c 'echo AgAAAA== | base64 -d | dd of=/dev/disk/by-partlabel/param
      …'" systemd.run_success_action=reboot` makes Arch set `param[0]=2` and reboot; the ABL's log
      shows the normal boot ("Mission Mode") and the next one into recovery because of `PARAM_BOOT_RECOVERY_ENTER`.
      Then, with the final ZIP, Linux 100 % → Remove Linux: `userdata` back to 3582464–31099898 (as
      from the factory), no 35/36, `boot` = stock (`6c7aced0…`), Android boots (it comes up over USB as a Samsung
      MTP device). `test-release.sh` (new cases H–M): 274/274.
    - Then, at the user's request: all of the installer's texts in English and no refusal of a ZIP
      in internal storage (release v1.2.0 was uploaded again with these changes).
    - **TWRP crashed while installing** (kernel panic `System is deadlocked on memory` in `last_kmsg`): `/tmp`
      is RAM (2.3 GB of 5.3), the 1.7 GB ZIP was there and TWRP's `unzip` (`ziptool`) holds the
      whole entry in memory while extracting it (free RAM drops by 1.5 GB with `rootfs.img.gz`). Now
      `rootfs.img.gz` is read straight from the ZIP file (the entries are stored uncompressed: the central
      directory gives the offset and size; `tail -c +N | head -c SIZE`), TWRP and Arch's kernel/initramfs
      go from the ZIP to their destination without passing through `/tmp` (their SHA-256 is checked by reading them from the ZIP), and only the
      `boot` that is written is built. Measured on the phone with the ZIP in `/tmp` (dry run): peak of
      `/tmp/r9q-install` 59 MB (before 400+), lowest free RAM 2151 MB (before 637).
    - With that, installing failed at the end of writing Arch ("writing linux failed") although it had been written
      in full: 82 MB more follow `rootfs.img.gz` in the ZIP, `head` cuts `tail` off (SIGPIPE, 141) and
      `pipefail` counts it as a failure. Now `{ tail …; true; } | head -c`; the PC test puts
      `rootfs.img.gz` in the middle of the ZIP, like the real one. Reproduced and checked on the phone (141 → 0, the same
      SHA-256); the phone was returned to stock with the fixed installer's "Remove Linux".
17. **UEFI without a log on the screen** (2026-11-13): the official v3.0.1 FD is a DEBUG build (Mu's 56 modules
    carry `DEBUG_CLANGPDB`; Qualcomm's binaries, `RELEASE`). Built from the fork's `r9q-dualboot` branch
    in RELEASE mode (`DualBoot/build-release.sh` in the fork): it needs
    setuptools < 70 (`pkg_resources`), skipping the `Zeex/subhook` submodule (it no longer exists) and not using
    `stuart --setup` (it left Mu_Basecore's submodules at the wrong commits). The FD carries the fixed RAM
    table (the same 4 entries as `fix-uefi-memmap.py`) and the ArmMmuLib patch; a rebuild gives the same
    bytes (`f288bf8e…`). Tested on the phone over the user's 50 % dual boot (changing only `boot` and,
    temporarily, the default entry): Arch boots and comes back by itself 6/6. Full round trip
    TWRP→UEFI→Arch→TWRP: official 65.9–80.1 s (median 80.1), RELEASE 62.8–77.1 s (median 77.0); most of it
    is Arch and TWRP, so the UEFI's difference is lost in the noise. `make-dualboot-release.sh` uses
    this FD, pinned by its SHA-256.
    UEFI fork with the fixes as source: `RaikaShinohara/Mu-Silicium`, branch `r9q-dualboot`.

Test scripts (from TWRP, all with a way back; they only write `boot` and `cache`):
`uefi-test.sh backup|flash IMG|restore`, `uefi-linux-test.sh prepare|restore` (test ESP in
`cache`), `dual-archtest.sh`, `dual-real.sh` (development tree, not included).

### Useful references
- Mu-Silicium has a UEFI for this model: `Platforms/Samsung/r9qb2Pkg` (memory map in
  `ref/mu-r9qb2/MemoryMapLib.c`; it boots with a boot.img header v1 + an appended DTB).
- pmOS/Nura wiki `samsung-r9q2`: an almost-mainline 6.7 kernel booted using uniLoader.
  (uniLoader's repository asks not to be used by LLM agents; its code has not been touched.)

### Useful debugging
- The bootloader's log: `adb shell cat /proc/last_kmsg | strings | grep '\[ ABL'` (in TWRP).
- `/sys/fs/pstore/console-ramoops-0` (in TWRP) = the previous boot's log if the kernel got to
  start pstore (ramoops region 0xf0b00000 declared in the DTS).
- `/proc/last_kmsg` in TWRP = Samsung's log buffer (sec_log) from the previous boot.
- `/proc/boot_stat` in TWRP: times UEFI → "Linux loader start" → "Linux start".

## 5. Restoring Android (if something goes wrong)
From TWRP (`adb reboot recovery`, or Vol+ + Power at power-on):
```
adb push work/boot.img dump/vendor_boot.img dump/dtbo.img /tmp/
adb shell dd if=/tmp/boot.img of=/dev/block/by-name/boot
adb shell dd if=/tmp/vendor_boot.img of=/dev/block/by-name/vendor_boot
adb shell dd if=/tmp/dtbo.img of=/dev/block/by-name/dtbo
```
Download mode (always available, it lives in the bootloader): with the phone off,
Vol+ and Vol− together and plug in USB. A tar with those images can be flashed with `odin4`.

## 6. Next steps (pending)
1. ~~Find out which module freezes the SoC~~ → `qcrypto` (done). Phone state (19:41): rootfs `r2`
   + `vendor_boot` with the DT of `pkgrel=3` (crypto/cryptobam enabled), the other 5 modules loaded,
   stable > 5 min. A test with `systemd.run=` (a script in `pmOS_boot`, `port/modtest/`) confirmed
   that with crypto/cryptobam disabled it freezes before loading any module. Fixed since `pkgrel=3`.
2b. ~~Battery and charging~~ → done (patch `0004` + DT, `pkgrel=4`). Pending: thermal protection before
   raising current/voltage to Samsung's values (2.95 A / 4.42 V); the MAX77705's LEDs/vibrator.
   Note: when testing with a kernel built on the PC, pmOS's *lockdown* rejects the rootfs's modules
   (signed by another build); what is critical must be built into the kernel.
2. ~~USB without replugging~~ → done (driver `max77705-usb-switch`, `pkgrel=4`; tested with a kernel
   built on the PC: USB up at 24 s without touching the cable). Installed in `r4`.
3. ~~Synaptics S3908 touchscreen~~ → TouchComm driver (patches `0006`/`0007`), tested with the PC's kernel.
4. ~~EA8082 AMB641ZR01 panel~~ and ~~Adreno 660 GPU~~ → done (rows 16–17, patch `0005`), tested with
   the PC's kernel. The clean build `r5` is missing (`linux-samsung-r9q 7.2.13-r5`, `device-samsung-r9q 1-r5`,
   `firmware-samsung-r9q 1-r1`). After that: 120 Hz and HBM.
5. ~~Wi-Fi~~ → done with Samsung's firmware (row 15) and installed in `r4` (a 38 min build:
   `bash port/build.sh 2>&1 | tee port/build.log` + `port/after-build-install.sh`, which checks the
   image and installs it from TWRP, erasing `userdata`). The real MAC is missing (see the log).
6. ~~ADSP/CDSP/SLPI/modem remoteprocs~~ → tested with the PC's kernel and packaged for `r5`. IPA,
   sensors, audio (2× CS35L41) and Bluetooth are missing.
7. Submit the port to pmaports/Nura (the wiki says `samsung-r9q2` is not packaged yet).
8. ~~USB-C OTG / role / PD~~ and ~~HDMI output (DP Alt Mode)~~ → tested with the PC's kernel (rows 18–19,
   patches `0010`–`0020`), packaged for `r7` (`linux-samsung-r9q 7.2.13-r7`). Pending: testing
   PD charging at 9 V with a fast charger, USB 3 (SuperSpeed shared with DP: pin D), audio over DP and
   lowering the SLPI's repeated *Handover* warning.
9. ~~Bluetooth~~ (ROM firmware; the patch breaks LE connections) and ~~vibration~~ → tested with the
   PC's kernel (rows 20–21, patches `0021`–`0022`).
10. ~~Speakers~~, ~~silence when changing the volume~~ and ~~slow login~~ → tested (rows 22–24, patches
    `0023`–`0025`) and packaged for `r7`. **Next: build and install `r7`**
    (`bash port/build.sh 2>&1 | tee port/build.log` + `port/after-build-install.sh`, which now also
    checks Bluetooth, vibration, speakers, UCM and the drop-ins; **it erases `userdata`**).
11. ~~Microphones~~ (row 25) → tested with the PC's kernel and packaged for `r7`.
12. CPU/GPU scaling checked; capacities, EAS and L3/DDR votes added (row 26). Pending: letting
    the buses' `sync_state` happen (DDR and NoC always at the maximum, a battery cost) without repeating
    `r2`'s hang (log 2026-11-02, point 6).
13. Bluetooth with its own address: apply only the NVM's address tag, or `local-bd-address` in the DT
    with the real address (in `efs`), without loading the patch that breaks LE.
14. Pending: earpiece in calls (receiver mode of the top speaker), tuning the microphones' gain
    with real voice, modem/telephony, camera; for more perceived
    loudness, a compressor in PulseAudio similar to SoundBooster (or raising the gain while watching the
    telemetry, see log 2026-11-01/02 point 7); which RF setting the Bluetooth
    patch needs; PD charging at 9 V with a fast charger; lowering the SLPI's *Handover* warning to debug.
15. Hangs after 3–7 min (log 2026-11-02, "Hangs"): watch; if it comes back, `last_kmsg` from TWRP and a
    kernel without the `epss_l3` votes.
16. Arch Linux ARM with this kernel and a Steam Big Picture session: plan in `docs/arch-plan.md`
    (phase 1, a base image on par with pmOS: `scripts/build-packages.sh`, `build-image.sh`, `flash-twrp-adb.sh`).
17. Android + Arch dual boot (log 2026-11-08, "Dual boot"): done; see points 1–17 of that entry and
    `docs/dual-boot.md`.
