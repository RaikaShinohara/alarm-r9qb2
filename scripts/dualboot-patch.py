#!/usr/bin/env python3
"""Make Android's boot.img dual-boot: its kernel gets shellcode-r9q.bin in
the header and the UEFI FD appended (same layout as Project-Aloha's
DualBootKernelPatcher). The ABL keeps booting Android's boot.img with
Android's vendor_boot/dtbo; the shellcode then runs the UEFI or Android.

  dualboot-patch.py patch   ANDROID_BOOT.img UEFI.fd SHELLCODE.bin OUT.img
  dualboot-patch.py patch-uefi BOOT.img UEFI.fd SHELLCODE.bin OUT.img
                            (Linux 100 %: the selector alone + the UEFI, with
                            the header and ramdisk of BOOT.img; no Android)
  dualboot-patch.py unpatch PATCHED_BOOT.img OUT.img     (back to stock)
  dualboot-patch.py info    BOOT.img

Boot images with header v3/v4 (page 4096) and an arm64 kernel Image, raw or
compressed (gzip, LZ4, bzip2, xz: decompressed, the new boot carries it raw;
LZ4 needs the lz4 command). Anything else is refused.

When BOOT.img is a whole boot partition with an AVB footer (ROMs signed only
with AVB, LineageOS for one: the vbmeta right after the image), OUT.img is a
whole partition too: Android's vbmeta moved after the new image and the
footer pointing at it, the rest zeroed, as the TWRP installer writes it.
Without that the longer image overwrites the vbmeta and Samsung's ABL crashes
reading it (stuck at the Samsung logo).
"""
import bz2
import lzma
import struct
import subprocess
import sys
import zlib

PAGE = 4096
MARKER = b"R9QDUALB"
FD_BASE, FD_SIZE = 0x9FC00000, 0x300000


def die(msg):
    sys.exit("error: " + msg)


def pad(n):
    return (n + PAGE - 1) // PAGE * PAGE


def read_boot(path):
    b = open(path, "rb").read()
    if b[:8] != b"ANDROID!":
        die(f"{path}: not an Android boot image")
    ksize, rsize, osver, hsize = struct.unpack_from("<4I", b, 8)
    hver, = struct.unpack_from("<I", b, 40)
    if hver not in (3, 4) or hsize > PAGE:
        die(f"{path}: header v{hver} (only v3/v4 boot images)")
    kernel = b[PAGE:PAGE + ksize]
    roff = PAGE + pad(ksize)
    ramdisk = b[roff:roff + rsize]
    sig = b""
    if hver == 4:
        ssize, = struct.unpack_from("<I", b, 1580)
        soff = roff + pad(rsize)
        sig = b[soff:soff + ssize]
    return bytearray(b[:PAGE]), kernel, ramdisk, sig, hver


def avb_of(path):
    """(partition size, footer, vbmeta) of a whole boot partition with an AVB
    footer, else None"""
    b = open(path, "rb").read()
    f = b[-64:]
    if f[:4] != b"AVBf":
        return None
    _, _, _, vo, vs = struct.unpack(">IIQQQ", f[4:36])
    if not 0 < vs <= 65536 or vo + vs > len(b) - 64 or b[vo:vo + 4] != b"AVB0":
        return None
    return len(b), f, b[vo:vo + vs]


def write_boot(path, hdr, kernel, ramdisk, sig, hver, avb=None):
    struct.pack_into("<I", hdr, 8, len(kernel))
    out = bytearray(hdr)
    for blob in (kernel, ramdisk) + ((sig,) if hver == 4 else ()):
        out += blob + b"\0" * (pad(len(blob)) - len(blob))
    n = len(out)
    if avb:
        size, f, vb = avb
        vo = pad(n)
        if vo + len(vb) > size - 64:
            die("no room in the partition for Android's vbmeta")
        out += b"\0" * (size - n)
        out[vo:vo + len(vb)] = vb
        nf = bytearray(f)
        struct.pack_into(">QQ", nf, 12, n, vo)
        out[-64:] = nf
        print(f"AVB: vbmeta moved to {vo:#x}, footer updated (whole partition, {size:#x} bytes)")
    open(path, "wb").write(out)
    return n


def kernel_image(k):
    """the raw arm64 Image (the ABL takes a raw Image as well as a compressed one)"""
    fmt = None
    if k[:2] == b"\x1f\x8b":
        fmt, k = "gzip", zlib.decompressobj(31).decompress(k)   # padding after the stream ignored
    elif k[:4] in (b"\x02\x21\x4c\x18", b"\x04\x22\x4d\x18"):
        try:
            fmt, k = "LZ4", subprocess.run(["lz4", "-d", "-c"], input=k, capture_output=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError) as e:
            die(f"LZ4 kernel: cannot decompress it with the lz4 command ({e})")
    elif k[:3] == b"BZh":
        fmt, k = "bzip2", bz2.decompress(k)
    elif k[:6] == b"\xfd7zXZ\0":
        fmt, k = "xz", lzma.decompress(k)
    if fmt:
        print(f"{fmt} kernel decompressed to {len(k):#x} bytes")
    if k[0x38:0x3C] != b"ARM\x64":
        die("not an arm64 kernel Image (no ARM\\x64 magic)")
    return bytearray(k)


def is_patched(k):
    return struct.unpack_from("<I", k, 0)[0] == 0x14000010 and MARKER in k[0x40:0x200]


def unpatch_kernel(k):
    """Original kernel bytes are not kept in the header area we overwrite, so
    unpatching needs the stock kernel: here we only strip the FD and refuse."""
    die("cannot rebuild the stock header bytes: flash the saved stock boot.img instead")


def patch_kernel(k, fd, sc):
    if len(fd) != FD_SIZE:
        die(f"UEFI FD is {len(fd):#x} bytes, expected {FD_SIZE:#x}")
    if fd[0x28:0x2C] != b"_FVH":
        die("UEFI FD has no firmware volume header")
    if sc[:4] != struct.pack("<I", 0x14000010) or MARKER not in sc:
        die("shellcode is not shellcode-r9q.bin")
    if is_patched(k):
        ksize, = struct.unpack_from("<Q", k, 0x30)
        print(f"kernel already patched: re-patching (stock size {ksize:#x})")
        k = k[:ksize]
        code1 = struct.unpack_from("<I", k, 4)[0]
    else:
        code0, code1 = struct.unpack_from("<2I", k, 0)
        if k[:2] == b"MZ" and code1 >> 26 == 0b000101:
            pass                                    # EFI stub kernel: branch already at 0x04
        elif code0 >> 26 == 0b000101 and code1 >> 26 != 0b000101:
            imm = (code0 & 0x3FFFFFF) - 1           # move the branch one instruction later
            code1 = 0x14000000 | (imm & 0x3FFFFFF)
        else:
            die("no branch in the first two instructions: unknown kernel layout")
        k = bytearray(k)
        k += b"\0" * (-len(k) % 16)                 # the copy loop moves 16 bytes at a time
    if len(sc) - 0x40 > 0x200 - 0x40:
        die("shellcode too big")
    ksize = len(k)
    out = bytearray(k) + fd
    struct.pack_into("<I", out, 0, 0x14000010)      # b 0x40
    struct.pack_into("<I", out, 4, code1)
    struct.pack_into("<3Q", out, 0x20, FD_BASE, FD_SIZE, ksize)
    out[0x40:len(sc)] = sc[0x40:]
    return out


UEFI_KN = 0x1000


def uefi_kernel(fd, sc):
    """The kernel of a Linux 100 % boot: the selector padded to one page, then
    the FD. Its Android branch (0x04) goes back to the selector, which then
    finds no mark and runs the UEFI. Header as a Linux arm64 Image would have
    (text_offset 0x80000, image_size 4 MiB, flags LE/4K/anywhere)."""
    if len(fd) != FD_SIZE or fd[0x28:0x2C] != b"_FVH":
        die("not the UEFI FD")
    if sc[:4] != struct.pack("<I", 0x14000010) or MARKER not in sc or len(sc) > UEFI_KN:
        die("shellcode is not shellcode-r9q.bin")
    k = bytearray(sc) + b"\0" * (UEFI_KN - len(sc)) + fd
    struct.pack_into("<I", k, 4, 0x1400000F)        # b 0x40
    struct.pack_into("<3Q", k, 0x08, 0x80000, 0x400000, 0xA)
    struct.pack_into("<3Q", k, 0x20, FD_BASE, FD_SIZE, UEFI_KN)
    return k


def main(argv):
    if len(argv) >= 2 and argv[1] == "info":
        hdr, k, r, s, v = read_boot(argv[2])
        state = ("UEFI only" if struct.unpack_from("<Q", k, 0x30)[0] <= 0x10000 else "dual-boot") if is_patched(k) else "stock"
        print(f"header v{v}, kernel {len(k):#x} ({state}), ramdisk {len(r):#x}")
        if is_patched(k):
            base, size, ksize = struct.unpack_from("<3Q", k, 0x20)
            print(f"  FD base {base:#x} size {size:#x}, Android kernel {ksize:#x}, FD _FVH: {k[ksize+0x28:ksize+0x2c]}")
        return
    if len(argv) == 6 and argv[1] == "patch":
        hdr, k, r, s, v = read_boot(argv[2])
        fd = open(argv[3], "rb").read()
        sc = open(argv[4], "rb").read()
        nk = patch_kernel(kernel_image(k), fd, sc)
        n = write_boot(argv[5], hdr, nk, r, s, v, avb_of(argv[2]))
        print(f"{argv[5]}: {n:#x} bytes, kernel {len(k):#x} -> {len(nk):#x}")
        return
    if len(argv) == 6 and argv[1] == "patch-uefi":
        hdr, k, r, s, v = read_boot(argv[2])
        nk = uefi_kernel(open(argv[3], "rb").read(), open(argv[4], "rb").read())
        n = write_boot(argv[5], hdr, nk, r, s, v, avb_of(argv[2]))
        print(f"{argv[5]}: {n:#x} bytes, kernel {len(nk):#x} (selector + UEFI, no Android)")
        return
    sys.exit(__doc__)


main(sys.argv)
