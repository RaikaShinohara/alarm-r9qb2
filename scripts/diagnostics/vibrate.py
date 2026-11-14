#!/usr/bin/env python3
# Vibrate through the kernel force-feedback interface (FF_RUMBLE) of the
# MAX77705 haptic input device. Usage: vibrate.py [ms] [strength 0-65535]
import fcntl, glob, os, struct, sys, time

ms = int(sys.argv[1]) if len(sys.argv) > 1 else 800
strength = int(sys.argv[2]) if len(sys.argv) > 2 else 0xC000

dev = None
for p in glob.glob('/sys/class/input/event*/device/name'):
    if 'haptic' in open(p).read():
        dev = '/dev/input/' + p.split('/')[4]
if not dev:
    sys.exit('no haptic input device')

EV_FF, FF_RUMBLE = 0x15, 0x50
# struct ff_effect on 64-bit: type, id, direction, trigger(2x u16),
# replay(length, delay), pad to 8, then the union (32 bytes); 48 in all
effect = struct.pack('<HhHHHHH2x', FF_RUMBLE, -1, 0, 0, 0, ms, 0)
effect += struct.pack('<HH', strength, strength) + b'\0' * 28
EVIOCSFF = 0x40000000 | (len(effect) << 16) | (ord('E') << 8) | 0x80

fd = os.open(dev, os.O_RDWR)
buf = bytearray(effect)
fcntl.ioctl(fd, EVIOCSFF, buf)
eid = struct.unpack_from('<h', buf, 2)[0]
os.write(fd, struct.pack('<qqHHi', 0, 0, EV_FF, eid, 1))
print(f'{dev}: vibrating {ms} ms (effect {eid}, strength {strength})')
time.sleep(ms / 1000 + 0.2)
os.close(fd)
