#!/usr/bin/env python3
"""Give Linux the RAM the official Mu-Silicium r9q UEFI (v3.0.1) leaves out.

The UEFI's memory table (the DeviceMemoryMapLib array in its SEC module, 72
bytes per entry, uncompressed in the FD at 0xC160) does not declare about
870 MiB below 4 GiB that Samsung's ABL does give the kernel, so Linux booted
through the UEFI saw 4.2 GiB instead of ~5. Four entries the UEFI does not
need are pointed at the four largest free ranges, as conventional memory
("RAM Partition"); nothing else in the FD changes (68 bytes). The SEC file
has no data checksum (FFS checksum 0xAA) and the FV header checksum only
covers the header, so the result loads like the original.

Free = ABL's RAM ranges minus every reserved-memory region of our DT
(TrustZone's tima/kaslr/hdm, PIL, removed_mem, ...), minus what the UEFI
already maps:
  Hyperisor  (reserved, also in our DT)  -> 0xB0200000-0xBA800000 (166 MiB)
  Axon DMA   (1 MiB "do not use" marker) -> 0x81200000-0x85200000 (64 MiB)
  SOD Test   (reserved, RAM under ABL)   -> 0xC0000000-0xD0000000 (256 MiB)
  Guest VM   (reserved, also in our DT)  -> 0xA0002000-0xB0100000 (256 MiB)

Usage: fix-uefi-memmap.py R9Q_UEFI-v3.0.1.fd R9Q_UEFI-v3.0.1-ram.fd
"""
import hashlib
import struct
import sys

BASE, STRIDE, ENTRIES = 0xC160, 72, 40
OFFICIAL_SHA256 = "bb30658b27b44c82d99f56f9aee542ee70bbf86e7310127451f8e19bd54d9520"
PLAN = {  # slot: (name it must have, new base, new length)
    0: ("Hyperisor", 0x0B0200000, 0x0A600000),
    1: ("Axon DMA", 0x081200000, 0x04000000),
    19: ("SOD Test", 0x0C0000000, 0x10000000),
    20: ("Guest VM", 0x0A0002000, 0x100FE000),
}


def entry(fd, i):
    o = BASE + i * STRIDE
    return o, fd[o:o + 32].split(b"\0")[0].decode(), struct.unpack_from("<QQIIIII", fd, o + 32)


def main(src, dst):
    fd = bytearray(open(src, "rb").read())
    if hashlib.sha256(fd).hexdigest() != OFFICIAL_SHA256:
        sys.exit("error: not the official Mu-Silicium v3.0.1 r9q FD")
    _, ref, vals = entry(fd, 24)
    if ref != "RAM Partition":
        sys.exit("error: unexpected table layout")
    hob, rt, ra, mt, aa = vals[2:]
    for i, (old, a, l) in PLAN.items():
        o, name, _ = entry(fd, i)
        if name != old:
            sys.exit(f"error: slot {i} is '{name}', expected '{old}'")
        fd[o:o + 32] = b"RAM Partition".ljust(32, b"\0")
        struct.pack_into("<QQIIIII", fd, o + 32, a, l, hob, rt, ra, mt, aa)
    mem = sorted((v[0], v[0] + v[1], name) for o, name, v in (entry(fd, i) for i in range(ENTRIES)) if v[2] in (1, 3))
    for (a1, b1, n1), (a2, b2, n2) in zip(mem, mem[1:]):
        if b1 > a2:
            sys.exit(f"error: {n1} overlaps {n2}")
    open(dst, "wb").write(fd)
    print(f"{dst}: sha256 {hashlib.sha256(fd).hexdigest()}")


if len(sys.argv) != 3:
    sys.exit(__doc__)
main(sys.argv[1], sys.argv[2])
