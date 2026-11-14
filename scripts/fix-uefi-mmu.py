#!/usr/bin/env python3
"""Stop the official Mu-Silicium r9q UEFI (v3.0.1) from crashing in ArmCpuDxe.

After a software restart (from Linux, Android or TWRP, with the USB cable
connected) the UEFI died at boot with "ReplaceTableEntry: splitting block
entry with MMU disabled" and a synchronous exception in ArmCpuDxe at +0x4C58:
ArmMmuLib splits a live 2 MiB block that holds its own code or page table by
turning the MMU off for the update, and on this SoC the CPU cannot execute
again when it comes back (the exception is on the return address, and even
the exception handler faults).

Both copies of ArmMmuLib (ArmCpuDxe and DynamicRamDxe) get one instruction
changed: the "MMU off" branch of ReplaceTableEntry jumps straight to the next
iteration of its loop, so such a block is simply left as a block, with the
attributes it already had (a few pages keep their old protections; the OS
builds its own tables anyway). Splits that need no MMU-off still happen.

The drivers live in the LZMA-compressed volume (FFS at 0x10108): it is
decompressed, patched, recompressed (LZMA "alone" header as EDK2 expects) and
the file header rebuilt with its checksum. Every original instruction is
checked first, and the result is decompressed again and compared.
Usage: fix-uefi-mmu.py IN.fd OUT.fd     (IN: the official or the -ram FD)
"""
import hashlib
import lzma
import struct
import sys

FFS_OFF = 0x10108
LZMA_GUID = bytes.fromhex("98584eee143959429d6edc7bd79403cf")
# driver, PE offset in the decompressed volume, VMA of the MMU-off branch,
# its first instruction (adrp x1, ...), VMA of the loop's next iteration
PATCHES = [
    ("ArmCpuDxe", 0x397C0, 0x4C24, 0x90000021, 0x49FC),
    ("DynamicRamDxe", 0x24EF6C, 0x2FF0, 0xF0000001, 0x2D7C),
]
TEXT_VMA, TEXT_RAW = 0x1000, 0x220
KNOWN = {  # sha256 of the input FDs this was made for
    "bb30658b27b44c82d99f56f9aee542ee70bbf86e7310127451f8e19bd54d9520": "official v3.0.1",
    "440e4d7c8684eecf60ef8b898cd6a7c1d1a8ac06bfbb71e8b213239e5c20d2bc": "v3.0.1 + RAM fix",
}


def die(m):
    sys.exit("error: " + m)


def b_insn(at, to):
    return 0x14000000 | (((to - at) >> 2) & 0x3FFFFFF)


def main(src, dst):
    fd = bytearray(open(src, "rb").read())
    kind = KNOWN.get(hashlib.sha256(fd).hexdigest()) or die("not a known r9q v3.0.1 FD")
    if fd[FFS_OFF + 18] != 0x0B:
        die("no compressed volume file at 0x10108")
    fsize = int.from_bytes(fd[FFS_OFF + 20:FFS_OFF + 23], "little")
    sec = FFS_OFF + 24
    ssize = int.from_bytes(fd[sec:sec + 3], "little")
    if fd[sec + 3] != 0x02 or fd[sec + 4:sec + 20] != LZMA_GUID:
        die("the volume is not an LZMA GUID-defined section")
    doff, gattr = struct.unpack_from("<HH", fd, sec + 20)
    comp = bytes(fd[sec + doff:sec + ssize])
    props = comp[:5]
    raw = bytearray(lzma.decompress(comp, format=lzma.FORMAT_ALONE))

    for name, pe, vma, first, nxt in PATCHES:
        if raw[pe:pe + 2] != b"MZ":
            die(f"{name}: no PE image at {pe:#x}")
        o = pe + vma - TEXT_VMA + TEXT_RAW
        got = struct.unpack_from("<I", raw, o)[0]
        if got != first:
            die(f"{name}: unexpected instruction {got:#010x} at {vma:#x}")
        # the instruction before is the non-live path's "b <next iteration>"
        prev = struct.unpack_from("<I", raw, o - 4)[0]
        if prev != b_insn(vma - 4, nxt):
            die(f"{name}: unexpected code before {vma:#x}")
        struct.pack_into("<I", raw, o, b_insn(vma, nxt))
        print(f"{name}: {vma:#x} {got:#010x} -> b {nxt:#x}")

    # recompress: raw LZMA1 stream + the 13-byte "alone" header with the real size
    lc_lp_pb = props[0]
    pb, rest = divmod(lc_lp_pb, 45)
    lp, lc = divmod(rest, 9)
    dict_size = struct.unpack_from("<I", props, 1)[0]
    filt = [{"id": lzma.FILTER_LZMA1, "dict_size": dict_size, "lc": lc, "lp": lp, "pb": pb}]
    body = lzma.compress(bytes(raw), format=lzma.FORMAT_RAW, filters=filt)
    newcomp = props + struct.pack("<Q", len(raw)) + body
    if lzma.decompress(newcomp, format=lzma.FORMAT_ALONE) != bytes(raw):
        die("recompressed volume does not decompress to the patched one")

    newsec = bytearray(fd[sec:sec + doff]) + newcomp
    newsec[0:3] = len(newsec).to_bytes(3, "little")
    newffs = bytearray(fd[FFS_OFF:FFS_OFF + 24]) + newsec
    newffs[20:23] = len(newffs).to_bytes(3, "little")
    # header checksum: header bytes sum to 0 with State (23) and the file checksum (17) excluded
    newffs[16] = 0
    s = (sum(newffs[0:16]) + sum(newffs[18:23])) & 0xFF
    newffs[16] = (0x100 - s) & 0xFF
    fvlen = struct.unpack_from("<Q", fd, 0x20)[0]
    if FFS_OFF + len(newffs) > fvlen:
        die("patched volume does not fit")
    out = bytearray(fd)
    out[FFS_OFF:FFS_OFF + max(fsize, len(newffs))] = newffs + b"\xff" * max(0, fsize - len(newffs))
    open(dst, "wb").write(out)
    print(f"{kind}: volume {len(comp):#x} -> {len(newcomp):#x} bytes; {dst}: sha256 {hashlib.sha256(out).hexdigest()}")


if len(sys.argv) != 3:
    sys.exit(__doc__)
main(sys.argv[1], sys.argv[2])
