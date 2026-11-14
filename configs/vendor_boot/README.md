# `vendor_boot` command line

The S21 FE's ABL takes the kernel command line from `vendor_boot` (header v3),
not from `boot.img`. `r9q-bootimg` (package `device-samsung-r9q`) reads it from
`/etc/r9q/bootimg.conf` and rebuilds `vendor_boot` whenever the kernel or the
initramfs changes; `cmdline.txt` is the reference copy.

| Parameter | Why |
|---|---|
| `root=PARTLABEL=userdata rw rootwait` | The ext4 root takes the whole `userdata` partition. UFS is not ready yet when the kernel looks for the root |
| `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` | Without them the kernel turns off clocks, power domains and regulators the bootloader left on (display, UFS) before their drivers claim them |
| `panic=10` | Reboots instead of hanging after a panic |
| `fbcon=font:TER16x32` | A readable console at 1080×2340 |
| `panel_samsung_ea8082.refresh_rate=120` | The panel driver starts at 120 Hz |
| `deferred_probe_timeout=60` | Time for the drivers that wait for the DSPs |

The ABL **replaces** any `console=` with `console=null`, so there is no serial
or text console through the command line; for debugging use Samsung's
persistent console (`/proc/last_kmsg` from TWRP, see
`docs/development-notes.md`).

The headers and addresses the ABL expects: `vendor_boot` v3, page size 4096,
board name `SRPVC21A007`, kernel at `0x8000`, ramdisk at `0x2000000`, tags at
`0x1e00000`. `scripts/check-image.sh` checks them.
