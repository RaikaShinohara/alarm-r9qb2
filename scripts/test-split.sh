#!/bin/bash
# Test the split ZIP on the PC: a sparse disk image with a GPT shaped like the
# phone's (34 entries, userdata = entry 34 from sector 3582464 to the end,
# Samsung's userdata GUIDs), the real ZIP from make-split-zip.sh, and
# update-binary in R9Q_SPLIT_TEST mode (no model check, no formatting).
# Usage: bash scripts/test-split.sh
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d "$H/../work/.split-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
GUID=11111111-2222-3333-4444-555555555555
UD=1B81E7E6-F50D-419B-A739-2AEEF8DA3335
fail() { echo "FAIL: $*"; exit 1; }
mkdisk() { # 40 GiB sparse, 512-byte sectors
	rm -f "$T/disk.img"; truncate -s 40G "$T/disk.img"
	args=(-o -a 1 -U "$GUID")
	for i in $(seq 1 33); do s=$((2048 + (i - 1) * 4096)); args+=(-n "$i:$s:$((s + 4095))" -c "$i:part$i" -t "$i:8300"); done
	args+=(-n "34:3582464:0" -c 34:userdata -t "34:$UD" -u "34:$UD")
	sgdisk "${args[@]}" "$T/disk.img" >/dev/null
}
run() { # run ZIP -> output; rc kept
	R9Q_SPLIT_TEST=1 R9Q_SPLIT_DISK="$T/disk.img" R9Q_SPLIT_DISK_GUID="${2:-$GUID}" \
		bash "$H/../configs/twrp/split-update-binary" 3 1 "$1" > "$T/out" 2>&1
}
show() { sed 's/^ui_print */   /' "$T/out" | grep -v '^ *$'; }
table() { sgdisk -p "$T/disk.img" | sed -n '/^Number/,$p'; }

mkdir -p "$T/usb"
DISK_GUID=$GUID bash "$H/make-split-zip.sh" "$T/usb" >/dev/null
ZIP=$(ls "$T"/usb/*.zip)
mkdir -p "$T/x" && (cd "$T/x" && unzip -q "$ZIP") && grep -q "$GUID" "$T/x/META-INF/com/google/android/update-binary" || fail "GUID not in the ZIP"
cp "$T/x/META-INF/com/google/android/update-binary" "$T/ub"

echo "== 1. normal split"
mkdisk
before=$(table | awk '$1 <= 33')
ud_end=$(sgdisk -i 34 "$T/disk.img" | sed -n 's/^Last sector: \([0-9]*\).*/\1/p')
R9Q_SPLIT_TEST=1 R9Q_SPLIT_DISK="$T/disk.img" bash "$T/ub" 3 1 "$ZIP" > "$T/out" 2>&1 || { show; fail "split failed"; }
show
[ "$(table | awk '$1 <= 33')" = "$before" ] || fail "entries 1-33 changed"
i34=$(sgdisk -i 34 "$T/disk.img"); i35=$(sgdisk -i 35 "$T/disk.img"); i36=$(sgdisk -i 36 "$T/disk.img")
grep -q "Partition name: 'userdata'" <<< "$i34" && grep -q "unique GUID: $UD" <<< "$i34" || fail "userdata identity"
grep -q "Partition name: 'esp'" <<< "$i35" && grep -q 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B' <<< "$i35" || fail "esp"
grep -q "Partition name: 'linux'" <<< "$i36" || fail "linux"
s35=$(sed -n 's/^Partition size: \([0-9]*\).*/\1/p' <<< "$i35")
[ $((s35 * 512)) = 536870912 ] || fail "esp is not 512 MiB"
[ "$(sed -n 's/^Last sector: \([0-9]*\).*/\1/p' <<< "$i36")" = "$ud_end" ] || fail "linux does not end where userdata ended"
a=$(sed -n 's/^Partition size: \([0-9]*\).*/\1/p' <<< "$i34"); l=$(sed -n 's/^Partition size: \([0-9]*\).*/\1/p' <<< "$i36")
echo "   userdata $((a / 2048)) MiB, linux $((l / 2048)) MiB"
[ -s "$T/usb/gpt-sda-antes-de-dividir.bin" ] || fail "no GPT backup next to the ZIP"
echo "   OK: 1-33 unchanged, userdata keeps its GUIDs, esp 512 MiB, linux to the end, backup next to the ZIP"

echo "== 2. run again: must not touch anything"
h=$(sha256sum "$T/disk.img" | cut -d' ' -f1)
run "$ZIP" || fail "rerun failed"
grep -q 'already split' "$T/out" || fail "rerun message"
[ "$(sha256sum "$T/disk.img" | cut -d' ' -f1)" = "$h" ] || fail "rerun changed the disk"
echo "   OK: already split, disk unchanged"

echo "== 3. another disk (GUID): must refuse"
mkdisk; h=$(sha256sum "$T/disk.img" | cut -d' ' -f1)
run "$ZIP" 99999999-0000-0000-0000-000000000000 && fail "accepted another disk"
[ "$(sha256sum "$T/disk.img" | cut -d' ' -f1)" = "$h" ] || fail "disk touched"
echo "   OK: refused, unchanged"

echo "== 4. unknown partition 35: must refuse"
mkdisk; sgdisk -a 1 -d 34 -n "34:3582464:+1G" -c 34:userdata -t "34:$UD" -u "34:$UD" -n 35:0:+1G -c 35:something "$T/disk.img" >/dev/null
h=$(sha256sum "$T/disk.img" | cut -d' ' -f1)
run "$ZIP" && fail "accepted a foreign entry 35"
grep -q "something" "$T/out" || fail "message"
[ "$(sha256sum "$T/disk.img" | cut -d' ' -f1)" = "$h" ] || fail "disk touched"
echo "   OK: refused, unchanged"
echo SPLIT_TESTS_OK
