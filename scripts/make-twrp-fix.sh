#!/bin/bash
# Build the fixed TWRP for the r9q dual boot from the original image
# (TWRP 3.7.1_12-Edward0181-test, sha256 8d4557d1...).
#
# Two problems of that TWRP are fixed:
#  1. Leaving TWRP always came back to TWRP: Samsung's ABL sets the sticky
#     "enter recovery" flag (word 0 of `param` = 02) every time recovery is
#     entered, and only the stock recovery clears it (TWRP also leaves
#     "boot-recovery" in `misc`). A small service (r9q-clearflags) clears both,
#     every 3 s, while TWRP runs.
#  2. TWRP hung at its splash screen when Android is encrypted: it tries to
#     decrypt user 0 with the weaver HAL, which its manifest declares but which
#     does not exist in this TWRP, so it waited for it forever. The weaver entry
#     is removed from the manifest (getService fails at once, TWRP gives up and
#     shows the menu) and the /data line of recovery.fstab loses its
#     fileencryption/keydirectory flags. /data stays encrypted (not mounted);
#     the Arch install does not need it.
#
# Only files are added: a second cpio is appended to the original ramdisk
# (the kernel unpacks both, later files win). Kernel, dtb, recovery_dtbo and
# the header are reused byte for byte.
# Usage: make-twrp-fix.sh recovery.img OUT.img
set -euo pipefail
src=${1:?original TWRP recovery.img}; out=${2:?output image}
want=8d4557d13cc0f04c95aa51eb186e4d6da199af4a3747f22b371ba80b8c68c3a1
[ "$(sha256sum "$src" | cut -c1-64)" = "$want" ] || { echo "not the expected TWRP image" >&2; exit 1; }
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
unpack_bootimg --boot_img "$src" --out "$w/unpack" --format mkbootimg > "$w/args"
mkdir "$w/rd" "$w/ov"
(cd "$w/rd" && gzip -dc ../unpack/ramdisk | cpio -idm --quiet 'init.recovery.qcom.rc' 'system/etc/recovery.fstab' 'vendor/etc/vintf/manifest.xml')
mkdir -p "$w/ov/system/bin" "$w/ov/system/etc" "$w/ov/vendor/etc/vintf"

# 1. the flag-clearing service
sed '/^import \/init.recovery.qcom_decrypt.rc$/a import /init.recovery.r9q.rc' "$w/rd/init.recovery.qcom.rc" > "$w/ov/init.recovery.qcom.rc"
grep -qx 'import /init.recovery.r9q.rc' "$w/ov/init.recovery.qcom.rc"
cat > "$w/ov/init.recovery.r9q.rc" <<'RC'
# Galaxy S21 FE (r9q) dual boot: leaving TWRP must go back to the boot menu.
# Samsung's ABL writes PARAM_BOOT_RECOVERY_ENTER (param word 0 = 2) when it
# enters recovery and only the stock recovery clears it; TWRP also leaves its
# "boot-recovery" command in misc. r9q-clearflags clears both while TWRP runs.
service r9q_clearflags /system/bin/r9q-clearflags
    user root
    group root
    disabled
    oneshot
    seclabel u:r:recovery:s0

on boot
    start r9q_clearflags
RC
cat > "$w/ov/system/bin/r9q-clearflags" <<'SH'
#!/system/bin/sh
# Clear Samsung's "boot recovery" flag (param word 0 = 2) and the misc BCB
# "boot-recovery" command whenever they are set, so that rebooting from TWRP
# always goes to the dual boot menu. Writes only when a flag is set.
P=/dev/block/by-name/param
M=/dev/block/by-name/misc
while :; do
	p=$(dd if=$P bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d " \n")
	[ "$p" = 02000000 ] && printf "\0\0\0\0" | dd of=$P bs=4 count=1 conv=notrunc 2>/dev/null
	m=$(dd if=$M bs=13 count=1 2>/dev/null)
	[ "$m" = boot-recovery ] && dd if=/dev/zero of=$M bs=4096 count=8 2>/dev/null
	sync
	sleep 3
done
SH

# 2. no decryption attempt that can hang
sed -E '/[[:space:]]\/data[[:space:]]/{s/,fileencryption=[^,[:space:]]*//;s/,keydirectory=[^,[:space:]]*//}' "$w/rd/system/etc/recovery.fstab" > "$w/ov/system/etc/recovery.fstab"
python3 -I - "$w/rd/vendor/etc/vintf/manifest.xml" "$w/ov/vendor/etc/vintf/manifest.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
new, n = re.subn(r'    <hal format="hidl">\n        <name>android\.hardware\.weaver</name>\n.*?</hal>\n', '', s, flags=re.S)
if n != 1:
    sys.exit("weaver entry not found exactly once")
open(sys.argv[2], "w").write(new)
PY

chmod 750 "$w/ov/init.recovery.qcom.rc" "$w/ov/init.recovery.r9q.rc"
chmod 755 "$w/ov/system/bin/r9q-clearflags"
chmod 644 "$w/ov/system/etc/recovery.fstab" "$w/ov/vendor/etc/vintf/manifest.xml"
find "$w/ov" -exec touch -h -d @0 {} +
(cd "$w/ov" && printf '%s\n' init.recovery.qcom.rc init.recovery.r9q.rc system/etc/recovery.fstab \
	system/bin/r9q-clearflags vendor/etc/vintf/manifest.xml | cpio -o -H newc -R 0:0 --reproducible --quiet) | gzip -9 -n > "$w/overlay.cpio.gz"
cat "$w/unpack/ramdisk" "$w/overlay.cpio.gz" > "$w/ramdisk-new"
eval mkbootimg "$(sed "s|--ramdisk [^ ]*|--ramdisk $w/ramdisk-new|" "$w/args")" -o "$out"
echo "$out: sha256 $(sha256sum "$out" | cut -c1-64)"
