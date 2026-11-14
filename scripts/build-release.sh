#!/bin/bash
# Build the public release ZIPs (user alarm/alarm, no keys from this PC) of
# both editions, one after the other to keep disk use low: image, checks,
# TWRP zip, a full install of the zip on the PC (test-twrp-zip.sh), cleanup.
# Output: $ARTIFACTS/release/archlinuxarm-{kde,steam}-sm-g990b2-v$VERSION.zip
# Usage: bash scripts/build-release.sh [kde] [steam]
set -euo pipefail
A="$(cd "$(dirname "$0")" && pwd)"
. "$A/paths.sh"
VERSION=$(tr -d ' \n' < "$VERSION_FILE")
export PUBLIC=1
[ $# -gt 0 ] || set -- kde steam
for EDITION in "$@"; do
	export EDITION
	name="archlinuxarm-$EDITION-sm-g990b2-v$VERSION"
	echo "=== $EDITION: image"
	KEEP=0 bash "$A/build-image.sh"
	echo "=== $EDITION: checks"
	bash "$A/check-image.sh" > "$OUT_BASE/check-$EDITION-public.log" || {
		grep FAIL "$OUT_BASE/check-$EDITION-public.log"; exit 1; }
	echo "=== $EDITION: zip"
	NAME=$name bash "$A/make-twrp-zip.sh" "$ARTIFACTS/release"
	echo "=== $EDITION: install test"
	bash "$A/test-twrp-zip.sh" "$ARTIFACTS/release/$name.zip" "$OUT_BASE/$EDITION-public"
	rm -rf "$OUT_BASE/$EDITION-public"
done
echo RELEASE_DONE
