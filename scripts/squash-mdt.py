#!/usr/bin/env python3
"""Merge a split Qualcomm firmware (foo.mdt + foo.bNN) into one foo.mbn.

Usage: squash-mdt.py <in.mdt> <out.mbn>
Every program header with data is copied from its .bNN file to p_offset
(same result as linux-msm's pil-squasher).
"""
import os
import struct
import sys

mdt, out = sys.argv[1], sys.argv[2]
hdr = open(mdt, "rb").read()
assert hdr[:4] == b"\x7fELF", "not an ELF file"
is64 = hdr[4] == 2
if is64:
    phoff, = struct.unpack_from("<Q", hdr, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", hdr, 0x36)
else:
    phoff, = struct.unpack_from("<I", hdr, 0x1c)
    phentsize, phnum = struct.unpack_from("<HH", hdr, 0x2a)

base = mdt[:-4]
segs, size = [], 0
for i in range(phnum):
    o = phoff + i * phentsize
    if is64:
        _, _, p_offset, _, _, p_filesz = struct.unpack_from("<IIQQQQ", hdr, o)
    else:
        _, p_offset, _, _, p_filesz = struct.unpack_from("<IIIII", hdr, o)
    if p_filesz == 0:
        continue
    seg = "%s.b%02d" % (base, i)
    data = open(seg, "rb").read() if os.path.exists(seg) else hdr[p_offset:p_offset + p_filesz]
    assert len(data) == p_filesz, "%s: %d != %d" % (seg, len(data), p_filesz)
    segs.append((p_offset, data))
    size = max(size, p_offset + p_filesz)

buf = bytearray(size)
for off, data in segs:
    buf[off:off + len(data)] = data
open(out, "wb").write(buf)
print("%s: %d segments, %d bytes" % (out, len(segs), size))
