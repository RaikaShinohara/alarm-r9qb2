#!/bin/bash
# Test the all-in-one installer (configs/twrp/dualboot-update-binary) on the PC, in
# a sandbox whose / is the fixed TWRP's own ramdisk (its mksh, toybox, sgdisk,
# make_f2fs, mkfs.fat, ... under qemu-user), against fake phones: a sparse GPT
# image like the r9q's (33 entries + userdata to the end; 512-byte sectors on
# the PC) at 128 GB and 256 GB, partitions as files, the ESP a directory and
# the key presses from a file. Uses a small root filesystem instead of Arch.
# Checks per case: GPT (34/35/36 where the plan says, 1..33 untouched), boot =
# what dualboot-patch.py makes, the stock boot saved in the ESP, the ESP files,
# linux = the image, recovery = the fixed TWRP, recovery flags cleared,
# userdata/metadata/esp formatted only when they must be.
# Usage: bash scripts/test-dualboot-release.sh
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$H/.." && pwd)"
A=$R/scripts/	# scripts/ in the repository
. "$A/paths.sh"
BASE=${TMPDIR_TEST:-$WORK_DIR}/release-test
RD=$BASE/rd	# the fixed TWRP's ramdisk, extracted below
FD=$BASE/R9Q_UEFI.fd
ESPSRC=${ESPSRC:-$OUT_BASE/kde-public-dual/esp}	# any DUAL=1 image's ESP
UD_GUID=1B81E7E6-F50D-419B-A739-2AEEF8DA3335
rm -rf "$BASE"; mkdir -p "$BASE/zipdir"
[ -n "${KEEP_TEST:-}" ] || trap 'rm -rf "$BASE"' EXIT
PASS=0 FAIL=0
ok() { echo "  ok   $*"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
nogrep() { ! grep -q "$@"; }

echo "== payload and test zip"
Z=$BASE/zip; mkdir -p "$Z/dualboot" "$Z/META-INF/com/google/android"
make -s -C "$R/dualboot/dbkp" >/dev/null
clang --target=aarch64-linux-gnu -O2 -Wall -Wextra -Werror -ffreestanding -fno-stack-protector -fno-builtin \
	-nostdlib -static -fno-pic -fuse-ld=lld -Wl,--build-id=none -o "$Z/dualboot/r9q-tool" "$R/configs/dualboot/r9q-tool.c"
cp "$R/configs/dualboot/shellcode-r9q.bin" "$R/configs/dualboot/Reboot2Android.efi" "$Z/dualboot/"
cp "$R/dualboot/out/R9Q_UEFI-v3.0.1-release-r9qfix.fd" "$FD"	# the release's UEFI (make-release-zip.sh)
cp "$FD" "$Z/dualboot/R9Q_UEFI.fd"
bash "$R/scripts/make-twrp-fix.sh" "$R/work/recovery.img" "$Z/dualboot/twrp-r9q.img" >/dev/null
# the sandbox's / : both cpio archives of the fixed TWRP's ramdisk, as its kernel unpacks them
unpack_bootimg --boot_img "$Z/dualboot/twrp-r9q.img" --out "$BASE/twrp-unpack" >/dev/null
mkdir -p "$RD"
python3 -I - "$BASE/twrp-unpack/ramdisk" "$BASE/twrp-unpack" <<'PYEOF2'
import gzip, sys, zlib
data, out = open(sys.argv[1], "rb").read(), sys.argv[2]
n = 0
while data:
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    open(f"{out}/cpio{n}", "wb").write(d.decompress(data))
    data = d.unused_data.lstrip(b"\0"); n += 1
PYEOF2
for c in "$BASE"/twrp-unpack/cpio*; do (cd "$RD" && cpio -idm --quiet --no-absolute-filenames < "$c" 2>/dev/null) || true; done
[ -x "$RD/system/bin/sh" ] && [ -f "$RD/init.recovery.r9q.rc" ] || { echo "could not extract the TWRP ramdisk"; exit 1; }
(cd "$Z/dualboot" && sha256sum r9q-tool shellcode-r9q.bin R9Q_UEFI.fd Reboot2Android.efi twrp-r9q.img > SHA256SUMS)
cp "$R/configs/twrp/dualboot-update-binary" "$Z/META-INF/com/google/android/update-binary"
truncate -s 64M "$BASE/rootfs.img"; mke2fs -q -t ext4 -L testroot "$BASE/rootfs.img"
gzip -1 -n -c "$BASE/rootfs.img" > "$Z/rootfs.img.gz"
for f in arch/Image arch/initramfs.img arch/r9q.dtb loader/entries/arch.conf EFI/BOOT/BOOTAA64.EFI; do
	install -Dm644 "$ESPSRC/$f" "$Z/esp/$f"
done
(cd "$Z" && sha256sum esp/arch/Image esp/arch/initramfs.img esp/arch/r9q.dtb esp/loader/entries/arch.conf esp/EFI/BOOT/BOOTAA64.EFI > esp.sha256)
cat > "$Z/manifest.txt" <<EOF
MODE='dual'
EDITION='kde'
BUILD='test'
KERNEL='7.2.13-test'
SYSTEM_SIZE='test'
IMG_SIZE=$(stat -c %s "$BASE/rootfs.img")
IMG_SHA256=$(sha256sum "$BASE/rootfs.img" | cut -d' ' -f1)
GZ_SHA256=$(sha256sum "$Z/rootfs.img.gz" | cut -d' ' -f1)
EOF
# rootfs.img.gz before the dual boot files, as in the release ZIP: the
# installer reads it at its offset and must cope with data after it
(cd "$Z" && zip -0 -X -q -r "$BASE/zipdir/test.zip" META-INF manifest.txt rootfs.img.gz esp esp.sha256 dualboot)
TWSHA=$(sha256sum "$Z/dualboot/twrp-r9q.img" | cut -d' ' -f1)
BOOT_LEN=$(python3 -I -c '
import struct, sys
b = open(sys.argv[1], "rb").read(4096)
k, r = struct.unpack_from("<II", b, 8)
pg = lambda n: (n + 4095) // 4096 * 4096
print(4096 + pg(k) + pg(r))' "$R/work/boot.img")
# the expected boots: what dualboot-patch.py makes of the stock image alone
# (the AVB vbmeta and footer after it are checked apart, by avbok)
head -c "$BOOT_LEN" "$R/work/boot.img" > "$BASE/stock-image.img"
python3 -I "$R/scripts/dualboot-patch.py" patch "$BASE/stock-image.img" "$FD" "$R/configs/dualboot/shellcode-r9q.bin" "$BASE/boot-expected.img" >/dev/null
python3 -I "$R/scripts/dualboot-patch.py" patch-uefi "$BASE/stock-image.img" "$FD" "$R/configs/dualboot/shellcode-r9q.bin" "$BASE/boot-uefi-expected.img" >/dev/null

# phone NAME DISK_BYTES: a fresh fake phone in $BASE/NAME
phone() {
	local T=$BASE/$1 bytes=$2 last
	rm -rf "$T"; mkdir -p "$T/p" "$T/esp"
	truncate -s "$bytes" "$T/disk.img"
	local args=() s=2048 i
	for i in $(seq 1 33); do args+=(--new="$i:$s:$((s + 799999))" --change-name="$i:part$i"); s=$((s + 800000)); done
	sgdisk --clear "${args[@]}" "$T/disk.img" >/dev/null
	sgdisk --set-alignment=1 --new=34:28659712:0 --typecode=34:$UD_GUID --partition-guid=34:$UD_GUID --change-name=34:userdata "$T/disk.img" >/dev/null
	last=$(sgdisk --info=34 "$T/disk.img" | sed -n 's/^Last sector: \([0-9]*\).*/\1/p')
	truncate -s $(((last - 28659712 + 1) * 512)) "$T/p/sda34"
	head -c 4194304 /dev/urandom | dd of="$T/p/sda34" conv=notrunc status=none	# "encrypted Android data"
	cp "$R/work/boot.img" "$T/p/boot"
	cp "$R/work/recovery.img" "$T/p/recovery"
	truncate -s 16M "$T/p/metadata"
	printf '\002\000\000\000' > "$T/p/param"; truncate -s 1M "$T/p/param"
	printf 'boot-recovery' > "$T/p/misc"; truncate -s 1M "$T/p/misc"
	echo SM-G990B2 > "$T/model"
	for i in $(seq 1 33); do sgdisk --info=$i "$T/disk.img"; done > "$T/gpt-1-33.txt"
}
# run NAME KEYS...: the installer in the TWRP sandbox; output in NAME/out.txt, status in RC
run() {
	local T=$BASE/$1; shift
	printf '%s\n' "$@" > "$T/keys"
	set +e
	bwrap --ro-bind "$RD" / --bind "$T" /mnt --ro-bind "$BASE/zipdir" /postinstall --tmpfs /tmp --dev /dev --proc /proc \
		--setenv PATH /system/bin --setenv R9Q_T /mnt --setenv R9Q_DDBS 65536 --setenv R9Q_DRYRUN "${DRY:-}" --unshare-all \
		/system/bin/sh -c '/system/bin/sh /mnt/ub 3 9 /postinstall/test.zip 9>>/mnt/out.txt' 2>"$T/err.txt"
	RC=$?
	set -e
}
prep() { cp "$R/configs/twrp/dualboot-update-binary" "$BASE/$1/ub"; : > "$BASE/$1/out.txt"; }
say() { sed -n 's/^ui_print //p' "$BASE/$1/out.txt" | grep -v '^ *$'; }
info() { sgdisk --info="$2" "$BASE/$1/disk.img" | sed -n "s/^$3: *\\([^ ]*\\).*/\\1/p"; }
expect_split() { # expect_split NAME LINUX_PCT: GPT and partitions as the plan says
	local T=$BASE/$1 L=$2 first=28659712 ss=512
	read -r ud esf esl lxf lxl < <(python3 -I - "$T/disk.img" "$L" <<'PYEOF'
import subprocess, sys, re
disk, L = sys.argv[1], int(sys.argv[2])
def info(n):
    t = subprocess.run(["sgdisk", f"--info={n}", disk], capture_output=True, text=True).stdout
    return t
first = 28659712
# the region ends where userdata or linux ends
last = None
for n in (36, 34):
    m = re.search(r"Last sector: (\d+)", info(n))
    if m and "linux" in info(n) or (m and n == 34):
        last = int(m.group(1)); break
ss, align, esp = 512, 2097152 // 512, 536870912 // 512
total = last - first + 1
android = (268435456 // ss // align * align) if L == 100 else (total * (100 - L) // 100) // align * align
ud = first + android - 1
esf = -(-(ud + 1) // align) * align
esl = esf + esp - 1
lxf = -(-(esl + 1) // align) * align
print(ud, esf, esl, lxf, last)
PYEOF
)
	check "34 userdata ends at $ud" [ "$(info "$1" 34 'Last sector')" = "$ud" ]
	check "34 keeps its GUID" [ "$(info "$1" 34 'Partition unique GUID')" = "$UD_GUID" ]
	check "35 esp $esf-$esl" [ "$(info "$1" 35 'First sector')-$(info "$1" 35 'Last sector')" = "$esf-$esl" ]
	check "36 linux $lxf-$lxl" [ "$(info "$1" 36 'First sector')-$(info "$1" 36 'Last sector')" = "$lxf-$lxl" ]
	check "entries 1..33 untouched" cmp -s "$T/gpt-1-33.txt" <(for i in $(seq 1 33); do sgdisk --info=$i "$T/disk.img"; done)
	check "kernel view of 34/36 = the table" [ "$(stat -c %s "$T/p/sda34")-$(stat -c %s "$T/p/sda36")" = "$(((ud - first + 1) * ss))-$(((lxl - lxf + 1) * ss))" ]
	local pct; pct=$(python3 -I -c "print(round(100*$(stat -c %s "$T/p/sda36")/($(stat -c %s "$T/p/sda34")+$(stat -c %s "$T/p/sda35")+$(stat -c %s "$T/p/sda36"))))")
	check "linux is ~$L % of the area ($pct %)" [ $((pct - L)) -ge -1 ] && [ $((pct - L)) -le 1 ]
}
# avbok BOOT STOCK N: BOOT's AVB footer says image size N and points at STOCK's
# vbmeta, which is there (after the N bytes, 4 KiB aligned)
avbok() { python3 -I - "$@" <<'PYEOF'
import struct, sys
b = open(sys.argv[1], "rb").read(); st = open(sys.argv[2], "rb").read(); n = int(sys.argv[3])
f, g = b[-64:], st[-64:]
if g[:4] != b"AVBf":
    sys.exit(0 if f == g else 1)   # no AVB in the stock boot: the footer area untouched
_, _, so, sv, ss = struct.unpack(">IIQQQ", g[4:36])
_, _, o, v, s = struct.unpack(">IIQQQ", f[4:36])
ok = f[:4] == b"AVBf" and o == n and v == (n + 4095) // 4096 * 4096 and s == ss and \
    b[v:v + s] == st[sv:sv + ss] and f[36:] == g[36:] and f[4:12] == g[4:12]
sys.exit(0 if ok else 1)
PYEOF
}
# vbsaved DIR STOCK: DIR's boot-android-footer.bin/-vbmeta.bin hold STOCK's vbmeta
vbsaved() { python3 -I - "$@" <<'PYEOF'
import struct, sys
d, st = sys.argv[1], open(sys.argv[2], "rb").read()
f = open(d + "/boot-android-footer.bin", "rb").read(); vb = open(d + "/boot-android-vbmeta.bin", "rb").read()
_, _, _, sv, ss = struct.unpack(">IIQQQ", st[-64:][4:36])
sys.exit(0 if f[:4] == b"AVBf" and struct.unpack(">Q", f[28:36])[0] == len(vb) and vb == st[sv:sv + ss] else 1)
PYEOF
}
expect_installed() { # expect_installed NAME STOCK_SAVED(1/0) [uefi]: uefi = Linux 100 %
	local T=$BASE/$1 n e=$BASE/boot-expected.img
	[ "${3:-}" = uefi ] && e=$BASE/boot-uefi-expected.img
	check "exit 0" [ "$RC" = 0 ]
	n=$(stat -c %s "$e")
	check "boot = dualboot-patch.py ${3:-patch} output" cmp -s -n "$n" "$T/p/boot" "$e"
	check "boot: Android's vbmeta after the new image, footer pointing at it" avbok "$T/p/boot" "${STOCK:-$R/work/boot.img}" "$n"
	check "linux = the image" cmp -s -n "$(stat -c %s "$BASE/rootfs.img")" "$T/p/sda36" "$BASE/rootfs.img"
	check "recovery = fixed TWRP" [ "$(head -c "$(stat -c %s "$Z/dualboot/twrp-r9q.img")" "$T/p/recovery" | sha256sum | cut -d' ' -f1)" = "$TWSHA" ]
	check "param cleared" [ "$(od -An -tx1 -N4 "$T/p/param" | tr -d ' \n')" = 00000000 ]
	check "misc cleared" [ "$(od -An -tx1 -N13 "$T/p/misc" | tr -d ' \n0')" = "" ]
	for f in EFI/BOOT/BOOTAA64.EFI arch/Image arch/initramfs.img arch/r9q.dtb loader/entries/arch.conf; do
		check "esp/$f" [ -s "$T/esp/$f" ]
	done
	if [ "${3:-}" = uefi ]; then
		check "no Android entry" [ ! -e "$T/esp/loader/entries/android.conf" ] && [ ! -e "$T/esp/EFI/android" ]
	else
		check "esp/EFI/android/Reboot2Android.efi" [ -s "$T/esp/EFI/android/Reboot2Android.efi" ]
		check "android entry" grep -qx 'efi     /EFI/android/Reboot2Android.efi' "$T/esp/loader/entries/android.conf"
	fi
	check "loader.conf default arch" grep -qx 'default arch.conf' "$T/esp/loader/loader.conf"
	check "esp FAT32" [ "$(dd if="$T/p/sda35" bs=1 skip=82 count=5 status=none)" = FAT32 ]
	if [ "$2" = 1 ]; then
		check "stock boot saved in the ESP" cmp -s "$T/esp/r9q/boot-android-original.img" <(head -c "$(stat -c %s "$T/esp/r9q/boot-android-original.img")" "$R/work/boot.img")
		check "saved boot is whole (header+kernel+ramdisk)" [ "$(stat -c %s "$T/esp/r9q/boot-android-original.img")" = "$BOOT_LEN" ]
		check "Android's vbmeta saved in the ESP" vbsaved "$T/esp/r9q" "${STOCK:-$R/work/boot.img}"
	fi
	check "no work dir left" [ ! -e "$T/work" ]
}
f2fs() { [ "$(od -An -tx1 -j 1024 -N4 "$BASE/$1/p/sda34" | tr -d ' \n')" = 1020f5f2 ]; }
ext4md() { [ "$(od -An -tx1 -j 1080 -N2 "$BASE/$1/p/metadata" | tr -d ' \n')" = 53ef ]; }

G128=$((31099904 * 4096))	# the r9q's 128 GB UFS (LUN 0)
G256=$((62500000 * 4096))

echo "== A. 256 GB, not split, Linux 50 %"
phone a $G256; prep a
run a down power down power
say a | sed -n '/^Storage/,/^Volume/p' | head -6
expect_split a 50; expect_installed a 1
check "userdata formatted (f2fs)" f2fs a
check "metadata emptied (ext4)" ext4md a

echo "== B. 128 GB, not split, Linux 25 %"
phone b $G128; prep b
run b power down power
say b | sed -n '/^Storage/,/^Volume/p' | head -6
expect_split b 25; expect_installed b 1; check "userdata formatted" f2fs b

echo "== C. 128 GB, not split, Linux 75 %"
phone c $G128; prep c
run c down down power down power
expect_split c 75; expect_installed c 1

echo "== D. already split (A), keep: Android's data untouched, boot re-patched"
prep a; rm -rf "$BASE/a/esp/r9q"
head -c 4194304 /dev/urandom | dd of="$BASE/a/p/sda34" conv=notrunc status=none	# Android encrypted it
dd if="$BASE/a/p/sda34" bs=1M count=4 status=none | sha256sum > "$BASE/a/ud.sha"
printf keys | dd of="$BASE/a/p/metadata" bs=1 seek=8192 conv=notrunc status=none
md=$(sha256sum < "$BASE/a/p/metadata")
printf '\002\000\000\000' | dd of="$BASE/a/p/param" conv=notrunc status=none
cp "$BASE/a/disk.img" "$BASE/a/disk.before"
run a power down power
say a | grep -E '^(  >> |boot:|The split is kept)' | head -4
expect_installed a 0
check "GPT unchanged" cmp -s "$BASE/a/disk.img" "$BASE/a/disk.before"
check "Android data untouched" [ "$(dd if="$BASE/a/p/sda34" bs=1M count=4 status=none | sha256sum)" = "$(cat "$BASE/a/ud.sha")" ]
check "metadata untouched" [ "$(sha256sum < "$BASE/a/p/metadata")" = "$md" ]
check "said 'already dual boot'" grep -q 'already dual boot' "$BASE/a/out.txt"
check "recovery left alone (already fixed)" grep -q 'already has the fixed TWRP' "$BASE/a/out.txt"
rm -f "$BASE/a/disk.before"

echo "== E. already split (A), new split Linux 75 %"
prep a
run a down down down power down power
expect_split a 75; expect_installed a 0; check "userdata formatted" f2fs a

echo "== F. an interrupted split (userdata zeros), keep -> formats userdata"
prep b
dd if=/dev/zero of="$BASE/b/p/sda34" bs=1M count=4 conv=notrunc status=none
dd if=/dev/zero of="$BASE/b/p/sda35" bs=1M count=1 conv=notrunc status=none
run b power down power
expect_installed b 0
check "userdata formatted" f2fs b
check "said so" grep -q 'half done' "$BASE/b/out.txt"

echo "== H. 128 GB, not split, Linux 100 %: boot = selector + UEFI alone"
phone h $G128; prep h
run h down down down power down power
say h | sed -n '/^Storage/,/^Volume/p' | head -7
expect_split h 100; expect_installed h 1 uefi
check "userdata formatted" f2fs h
check "said 'Linux 100 %'" grep -q 'Linux 100 %' "$BASE/h/out.txt"

echo "== I. Linux 100 % (H), keep: boot rebuilt the same, GPT unchanged"
prep h; cp "$BASE/h/disk.img" "$BASE/h/disk.before"
run h power down power
expect_installed h 1 uefi
check "GPT unchanged" cmp -s "$BASE/h/disk.img" "$BASE/h/disk.before"
check "said 'UEFI only'" grep -q 'UEFI only' "$BASE/h/out.txt"
check "offers going back to Android" grep -q 'Remove Linux: Android' "$BASE/h/out.txt"
rm -f "$BASE/h/disk.before"

echo "== J. Linux 100 % (H) -> Linux 50 %: Android's boot comes back from the ESP copy"
prep h
run h down down power down power
expect_split h 50; expect_installed h 1
check "userdata formatted" f2fs h

echo "== K. dual (J) -> remove Linux: userdata takes everything, Android's own boot"
prep h; cp "$BASE/h/disk.img" "$BASE/h/disk.prev"
run h down down down down down power down power
check "exit 0" [ "$RC" = 0 ]
check "34 userdata spans the area again" [ "$(info h 34 'First sector')-$(info h 34 'Last sector')" = "28659712-$(sgdisk --info=36 "$BASE/h/disk.prev" | sed -n 's/^Last sector: \([0-9]*\).*/\1/p')" ]
check "34 keeps its GUID" [ "$(info h 34 'Partition unique GUID')" = "$UD_GUID" ]
check "no 35/36" [ -z "$(sgdisk --info=35 "$BASE/h/disk.img" | grep 'Partition name')$(sgdisk --info=36 "$BASE/h/disk.img" | grep 'Partition name')" ]
check "entries 1..33 untouched" cmp -s "$BASE/h/gpt-1-33.txt" <(for i in $(seq 1 33); do sgdisk --info=$i "$BASE/h/disk.img"; done)
check "kernel view: sda34 whole, no sda35/36" [ "$(stat -c %s "$BASE/h/p/sda34")" = "$((($(info h 34 'Last sector') - 28659712 + 1) * 512))" ] && [ ! -e "$BASE/h/p/sda35" ] && [ ! -e "$BASE/h/p/sda36" ]
check "boot = Android's stock boot" cmp -s -n "$BOOT_LEN" "$BASE/h/p/boot" "$R/work/boot.img"
check "boot: Android's vbmeta and footer back" avbok "$BASE/h/p/boot" "$R/work/boot.img" "$BOOT_LEN"
check "userdata formatted" f2fs h
check "metadata emptied" ext4md h
check "param cleared" [ "$(od -An -tx1 -N4 "$BASE/h/p/param" | tr -d ' \n')" = 00000000 ]
check "no work dir left" [ ! -e "$BASE/h/work" ]
rm -f "$BASE/h/disk.prev"

echo "== L. not split again (K): a new split works as on a fresh phone"
prep h
run h down power down power
expect_split h 50; expect_installed h 1

echo "== M. dual without the stock copy in the ESP: no 'remove'; Linux 100 % without it: no split"
phone m $G128; prep m
run m power down power	# Linux 25 %
rm -rf "$BASE/m/esp/r9q"
prep m; run m down down down down power down power	# keep, 25, 50, 75, 100 -> Linux 100 %
expect_installed m 0 uefi
check "said there is no copy" grep -q "no copy of Android's boot" "$BASE/m/out.txt"
check "no 'remove' offered" nogrep 'Remove Linux: Android' "$BASE/m/out.txt"
prep m; run m down power down power	# keep, 100, cancel: down = Linux 100 % again
m_only() { [ "$RC" = 0 ] && nogrep 'Linux 50 %' "$BASE/m/out.txt" && nogrep 'Remove Linux: Android' "$BASE/m/out.txt"; }
check "Linux 100 % without the copy: only keep / 100 % / cancel" m_only

echo "== N. a ROM whose boot is signed only with AVB (LineageOS): split, keep, remove"
# the vbmeta right after the image (no Samsung signature): the dual boot image
# overwrote it and the ABL crashed reading the footer (stuck at the logo)
LBOOT=$BASE/boot-lineage.img
# LINEAGE_ZIP: a LineageOS ZIP for the r9q (default: the newest one archived next to the project)
LINEAGE_ZIP=${LINEAGE_ZIP:-$(ls "$R"/../r9q2-archive/releases/lineage-*/lineage-*.zip 2>/dev/null | tail -n1)}
if [ -n "$LINEAGE_ZIP" ] && unzip -p "$LINEAGE_ZIP" boot.img > "$LBOOT" 2>/dev/null && [ -s "$LBOOT" ]; then
	python3 -I - "$LBOOT" "$BASE/lineage-image.img" <<'PYEOF'
import struct, sys
b = open(sys.argv[1], "rb").read(); _, _, o, _, _ = struct.unpack(">IIQQQ", b[-64:][4:36])
open(sys.argv[2], "wb").write(b[:o])
PYEOF
	python3 -I "$R/scripts/dualboot-patch.py" patch "$BASE/lineage-image.img" "$FD" "$R/configs/dualboot/shellcode-r9q.bin" "$BASE/boot-lineage-expected.img" >/dev/null
	# and of the whole partition: the vbmeta moved, as the installer must write it
	python3 -I "$R/scripts/dualboot-patch.py" patch "$LBOOT" "$FD" "$R/configs/dualboot/shellcode-r9q.bin" "$BASE/boot-lineage-expected-part.img" >/dev/null
	LN=$(stat -c %s "$BASE/boot-lineage-expected.img")
	phone n $G128; cp "$LBOOT" "$BASE/n/p/boot"; prep n
	run n down down power down power	# Linux 50 %
	check "exit 0" [ "$RC" = 0 ]
	check "boot = dualboot-patch.py output" cmp -s -n "$LN" "$BASE/n/p/boot" "$BASE/boot-lineage-expected.img"
	check "boot: LineageOS' vbmeta after the new image" avbok "$BASE/n/p/boot" "$LBOOT" "$LN"
	check "boot partition = dualboot-patch.py's whole-partition output" cmp -s "$BASE/n/p/boot" "$BASE/boot-lineage-expected-part.img"
	check "LineageOS' footer saved in the ESP" cmp -s "$BASE/n/esp/r9q/boot-android-footer.bin" <(tail -c 64 "$LBOOT")
	prep n; run n power down power	# keep: the vbmeta now comes from the ESP
	check "keep: exit 0" [ "$RC" = 0 ]
	check "keep: same boot" cmp -s -n "$LN" "$BASE/n/p/boot" "$BASE/boot-lineage-expected.img"
	check "keep: vbmeta still after the image" avbok "$BASE/n/p/boot" "$LBOOT" "$LN"
	prep n; run n down down down down down power down power	# remove Linux
	check "remove: exit 0" [ "$RC" = 0 ]
	check "remove: boot = LineageOS' boot partition, byte for byte" cmp -s "$BASE/n/p/boot" "$LBOOT"

	echo "== O. the same ROM with its kernel compressed (Image.gz, Image.lz4): unpacked, same boot"
	for c in gz lz4; do
		python3 -I - "$LBOOT" "$c" "$BASE/boot-lineage-$c.img" <<'PYEOF'
import gzip, struct, subprocess, sys
src, c, dst = sys.argv[1:]
b = open(src, "rb").read(); P = len(b); pg = lambda n: (n + 4095) // 4096 * 4096
ks, rs = struct.unpack("<II", b[8:16])
k = b[4096:4096 + ks]; r = b[4096 + pg(ks):4096 + pg(ks) + rs]
z = gzip.compress(k, 9, mtime=0) if c == "gz" else subprocess.run(["lz4", "-l", "-9", "-c"], input=k, capture_output=True, check=True).stdout
h = bytearray(b[:4096]); h[8:12] = struct.pack("<I", len(z))
img = bytes(h) + z + bytes(pg(len(z)) - len(z)) + r + bytes(pg(rs) - rs)
f = b[-64:]; _, _, _, vo, vs = struct.unpack(">IIQQQ", f[4:36])
out = bytearray(P); out[:len(img)] = img; nvo = pg(len(img)); out[nvo:nvo + vs] = b[vo:vo + vs]
nf = bytearray(f); nf[12:36] = struct.pack(">QQQ", len(img), nvo, vs); out[-64:] = nf
open(dst, "wb").write(out)
PYEOF
		phone o $G128; cp "$BASE/boot-lineage-$c.img" "$BASE/o/p/boot"; prep o
		run o down down power down power	# Linux 50 %
		check "$c: exit 0" [ "$RC" = 0 ]
		check "$c: boot = the uncompressed kernel's dual boot" cmp -s -n "$LN" "$BASE/o/p/boot" "$BASE/boot-lineage-expected.img"
		check "$c: vbmeta after the new image" avbok "$BASE/o/p/boot" "$BASE/boot-lineage-$c.img" "$LN"
		prep o; run o down down down down down power down power	# remove Linux
		check "$c: remove: boot = the compressed original, byte for byte" cmp -s "$BASE/o/p/boot" "$BASE/boot-lineage-$c.img"
	done
else
	echo "  (skipped: no LineageOS ZIP; LINEAGE_ZIP=...)"
fi

echo "== G. cancel and refusals write nothing"
phone g $G128
snap() { (cd "$BASE/g" && find p esp disk.img -type f -exec sha256sum {} + | sort); }
before=$(snap)
prep g; run g down down down down power
check "cancel in the first menu: exit 0, nothing written" [ "$RC" = 0 ] && [ "$(snap)" = "$before" ]
prep g; run g power power
check "'No' in the confirmation: nothing written" [ "$RC" = 0 ] && [ "$(snap)" = "$before" ]
prep g; DRY=1 run g power down power
check "dry run: exit 0, nothing written" [ "$RC" = 0 ] && [ "$(snap | grep -v ' work/')" = "$before" ]
check "dry run: boot it would write = dualboot-patch.py output" cmp -s "$BASE/g/work/boot-new.img" "$BASE/boot-expected.img"
rm -rf "$BASE/g/work"
echo SM-G990B > "$BASE/g/model"; prep g; run g power down power
check "other model refused" [ "$RC" != 0 ] && [ "$(snap)" = "$before" ] && grep -q 'only for the SM-G990B2' "$BASE/g/out.txt"
echo SM-G990B2 > "$BASE/g/model"
python3 -I - "$BASE/g/p/boot" <<'PYEOF'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
i = b.find(b"Linux version 5"); i = b.index(b"(", i); b[i:i + 6] = b"(pmos@"	# this port's own kernel
open(p, "wb").write(b)
PYEOF
before=$(snap); prep g; run g power down power
check "Linux kernel in boot refused" [ "$RC" != 0 ] && [ "$(snap)" = "$before" ] && grep -q "not Android's" "$BASE/g/out.txt"
cp "$R/work/boot.img" "$BASE/g/p/boot"
cp "$BASE/zipdir/test.zip" "$BASE/zipdir/bad.zip"
python3 -I - "$BASE/zipdir/bad.zip" <<'PYEOF'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
i = b.find(b"rootfs.img.gz")	# its local header comes first: data right after it
b[i + 100000] ^= 0xff
open(p, "wb").write(b)
PYEOF
before=$(snap); prep g
mv "$BASE/zipdir/test.zip" "$BASE/zipdir/good.zip"; mv "$BASE/zipdir/bad.zip" "$BASE/zipdir/test.zip"
run g power down power
mv "$BASE/zipdir/test.zip" "$BASE/zipdir/bad.zip"; mv "$BASE/zipdir/good.zip" "$BASE/zipdir/test.zip"
check "damaged rootfs refused before any write" [ "$RC" != 0 ] && [ "$(snap)" = "$before" ] && grep -q 'damaged' "$BASE/g/out.txt"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] && echo TEST_RELEASE_OK
