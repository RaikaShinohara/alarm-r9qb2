#!/usr/bin/env python3
"""Print the physical span of the loadable segments of Qualcomm .mdt/.mbn files.

Usage: mdt-span.py <file.mdt|file.mbn>...
Relocatable images (p_flags bit 27) can be loaded anywhere; the size of the
span must still fit in the reserved-memory region.
"""
import struct
import sys

for path in sys.argv[1:]:
    hdr = open(path, "rb").read(65536)
    is64 = hdr[4] == 2
    if is64:
        phoff, = struct.unpack_from("<Q", hdr, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", hdr, 0x36)
    else:
        phoff, = struct.unpack_from("<I", hdr, 0x1c)
        phentsize, phnum = struct.unpack_from("<HH", hdr, 0x2a)
    lo, hi, reloc = None, 0, False
    for i in range(phnum):
        o = phoff + i * phentsize
        if is64:
            p_type, p_flags, _, _, p_paddr, _, p_memsz, _ = struct.unpack_from("<IIQQQQQQ", hdr, o)
        else:
            p_type, _, _, p_paddr, _, p_memsz, p_flags, _ = struct.unpack_from("<IIIIIIII", hdr, o)
        seg_type = (p_flags >> 24) & 7
        if p_type != 1 or seg_type == 2 or p_memsz == 0:  # PT_LOAD, skip hash
            continue
        reloc |= bool(p_flags & (1 << 27))
        lo = p_paddr if lo is None else min(lo, p_paddr)
        hi = max(hi, p_paddr + p_memsz)
    print("%-12s 0x%08x-0x%08x size 0x%08x (%.1f MiB) %s" % (
        path.split("/")[-1], lo, hi, hi - lo, (hi - lo) / 2**20,
        "relocatable" if reloc else "fixed"))
