#!/bin/bash
# Package update-binary as a TWRP ZIP that splits userdata for the dual boot.
# The ZIP checks the disk GUID of the phone's UFS (read it in TWRP with
# `sgdisk --print /dev/block/sda`), so it only ever runs on that phone.
# Usage: DISK_GUID=XXXXXXXX-... [PCT=50] bash scripts/make-split-zip.sh [destination=artifacts/]
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$H/../.." && pwd)"
: "${DISK_GUID:?DISK_GUID of the phone UFS (sgdisk --print /dev/block/sda in TWRP)}"
PCT=${PCT:-50}
DEST=$(realpath -m "${1:-$R/builds}")
[[ "$DISK_GUID" =~ ^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$ ]] || { echo "bad DISK_GUID"; exit 1; }
[ "$PCT" -ge 10 ] && [ "$PCT" -le 90 ] || { echo "PCT must be 10..90"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/META-INF/com/google/android" "$DEST"
sed "s/@DISK_GUID@/$DISK_GUID/" "$H/../configs/twrp/split-update-binary" > "$W/META-INF/com/google/android/update-binary"
echo '# dummy: the installer is update-binary (a shell script)' > "$W/META-INF/com/google/android/updater-script"
echo "$PCT" > "$W/ANDROID-PERCENT"
sh -n "$W/META-INF/com/google/android/update-binary"
name="r9q-dualboot-dividir-$PCT.zip"
rm -f "$DEST/$name"
(cd "$W" && zip -X -q -r "$DEST/$name" META-INF ANDROID-PERCENT)
(cd "$DEST" && sha256sum "$name" > "$name.sha256")
echo "$DEST/$name"
