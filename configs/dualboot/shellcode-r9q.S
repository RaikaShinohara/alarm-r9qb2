/*
 * Dual boot selector for the Samsung Galaxy S21 FE (SM-G990B2, r9q).
 * Written for this port; same idea and header layout as Project-Aloha's
 * DualBootKernelPatcher ("boot manager"/PStore flavour of the Xiaomi Pad 5).
 *
 * dualboot-patch.py puts this code into Android's kernel Image:
 *   0x00  b 0x40              (was the kernel's first instruction)
 *   0x04  b <kernel entry>    (the original first branch, moved here)
 *   0x20  FD_BASE  (u64)      where the UEFI runs (0x9FC00000)
 *   0x28  FD_SIZE  (u64)      its size (0x300000)
 *   0x30  KERNEL_SIZE (u64)   the UEFI FD is appended at Image + KERNEL_SIZE
 *   0x40  this code
 *
 * On every cold boot there is no mark: the UEFI is copied to FD_BASE and run
 * (its menu: Arch Linux, Android). "Android" in that menu runs
 * Reboot2Android.efi, which fills the 4 KiB page at MARK_ADDR with a fixed
 * pseudo-random pattern (xorshift64 from SEED) and resets; the ABL then boots
 * this same kernel, this code finds the pattern, clears the page (so the next
 * boot shows the menu again) and jumps to the Android kernel with x0..x3
 * exactly as the ABL left them.
 *
 * The pattern is compared bit by bit, not as one word: Samsung's kernel and
 * TrustZone's PSCI SYSTEM_RESET always make the PMIC do a hard reset (the
 * XBL log in /proc/last_kmsg says "Reset Type: Hard Reset"), DRAM goes
 * without refresh for a moment and some bits flip, more after Android has
 * warmed the phone up. A single 64-bit mark then failed one or two times out
 * of three. Here the boot goes to Android when fewer than 3/8 of the 32768
 * bits differ: decayed bits settle at random values, so even a page that lost
 * half of them still matches, while any other content differs in about half
 * of its bits (random data: 16384 +- 90).
 *
 * MARK_ADDR is 0x17FE00000, high DRAM that no DT reserves and that XBL/ABL
 * do not touch (the Xiaomi Pad 5 uses the same address). The end of
 * Samsung's ramoops region was tried first: TWRP and the firmware write
 * their logs there and overwrote the mark.
 * At this point the MMU and the data cache are off.
 */
	.text
	.globl	_start
_start:
_KernelHead:
	b	_Code			// 0x00
_LinuxStart:
	b	.			// 0x04, filled in by the patcher
	.quad	0			// 0x08 text_offset (kept from the kernel)
	.quad	0			// 0x10 image_size (kept)
	.quad	0			// 0x18 flags (kept)
_FdBase:
	.quad	0			// 0x20
_FdSize:
	.quad	0			// 0x28
_KernelSize:
	.quad	0			// 0x30
	.ascii	"ARM\x64"		// 0x38 (kept)
	.long	0			// 0x3c (kept)

_Code:					// 0x40
	movz	x9, #0x7FE0, lsl #16
	movk	x9, #0x1, lsl #32	// x9  = MARK_ADDR 0x17FE00000
	movz	x10, #0x7C15
	movk	x10, #0x7F4A, lsl #16
	movk	x10, #0x79B9, lsl #32
	movk	x10, #0x9E37, lsl #48	// x10 = SEED 0x9E3779B97F4A7C15
	mov	x12, xzr		// offset in the page
	mov	x13, xzr		// bits that differ from the pattern
1:	eor	x10, x10, x10, lsl #13	// xorshift64: next pattern word
	eor	x10, x10, x10, lsr #7
	eor	x10, x10, x10, lsl #17
	ldr	x11, [x9, x12]
	eor	x11, x11, x10
	lsr	x14, x11, #1		// x11 = number of bits set (SWAR popcount)
	and	x14, x14, #0x5555555555555555
	sub	x11, x11, x14
	and	x14, x11, #0x3333333333333333
	lsr	x11, x11, #2
	and	x11, x11, #0x3333333333333333
	add	x11, x11, x14
	add	x11, x11, x11, lsr #4
	and	x11, x11, #0x0F0F0F0F0F0F0F0F
	add	x11, x11, x11, lsr #8
	add	x11, x11, x11, lsr #16
	add	x11, x11, x11, lsr #32
	and	x11, x11, #0x7F
	add	x13, x13, x11
	add	x12, x12, #8
	cmp	x12, #0x1000
	b.lo	1b
	cmp	x13, #3, lsl #12	// 12288 = 3/8 of the page's bits
	b.hs	_Uefi
	add	x14, x9, #0x1000	// consume the mark: clear the page
2:	stp	xzr, xzr, [x9], #16
	cmp	x9, x14
	b.lo	2b
	dsb	sy
	b	_LinuxStart		// Android, registers untouched

_Uefi:
	/*
	 * A software restart (Linux, Android, TWRP) keeps DRAM, and the UEFI then
	 * finds the leftovers of its previous run in its own regions; its memory
	 * layout changes and ArmCpuDxe dies splitting the block it runs in
	 * ("splitting block entry with MMU disabled", exception on return).
	 * Zero the UEFI's own regions so every boot looks like a power-on:
	 * 0x9B800000-0x9FA00000 (DXE/Sched heaps, FV region) and
	 * 0x9FF00000-0xA0000000 (SEC heap, vectors, page tables, stack, log,
	 * info block). Not touched: the ABOOT FV (0x9FA00000), the UEFI FD
	 * (copied below) and the ABL's kernel area (0xA0000000+, where this
	 * code runs). Skipped if this image was not loaded above 0xA0000000.
	 */
	adr	x12, _KernelHead
	movz	x13, #0xA000, lsl #16
	cmp	x12, x13
	b.lo	3f
	movz	x12, #0x9B80, lsl #16
	movz	x14, #0x9FA0, lsl #16
1:	stp	xzr, xzr, [x12], #16
	cmp	x12, x14
	b.lo	1b
	movz	x12, #0x9FF0, lsl #16
2:	stp	xzr, xzr, [x12], #16
	cmp	x12, x13
	b.lo	2b
	dsb	sy
3:
	adr	x12, _KernelHead
	ldr	x13, _KernelSize
	add	x12, x12, x13		// source: the FD after the kernel
	mov	x1, x12			// as Mu's BootShim: x1 = payload, x0 untouched
	ldr	x13, _FdBase		// destination
	ldr	x14, _FdSize
1:	ldp	x15, x16, [x12], #16
	stp	x15, x16, [x13], #16
	subs	x14, x14, #16
	b.ne	1b
	dsb	sy
	ic	iallu			// the copied FD is code
	dsb	sy
	isb
	ldr	x13, _FdBase
	br	x13

	.ascii	"R9QDUALB"		// marker: lets the patcher spot a patched kernel
_End:
