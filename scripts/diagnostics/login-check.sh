#!/bin/sh
# Login timing after a test boot: when the session started, how long the
# Plasma splash stayed, and whether FUSE and the document portal came up.
uname -v
ls -la /dev/fuse 2>&1
J() { journalctl -b --no-pager -o short-monotonic "$@"; }
J | grep -E "greeter: Login|Started dbus-:1.1-org.kde.KSplash@0|Finished Splash screen|plasma-ksplash.service: Consumed|Reached target plasma-workspace" | head -6
J | grep -iE "fuse: device|fuse init failed|document-portal|Document portal" | head -5
echo "portal registration failures: $(J | grep -c 'Failed to register with host portal')"
