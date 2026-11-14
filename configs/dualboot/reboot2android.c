/*
 * Reboot2Android for the Samsung Galaxy S21 FE (r9q) dual boot.
 * Same job as rodriguezst's Reboot2Android (Xiaomi Pad 5), written for this
 * port: write the mark the boot selector (shellcode-r9q.S) looks for, make
 * sure it reaches DRAM, and reset through PSCI (DRAM is kept, mostly: see
 * below). The ABL then boots the dual-boot kernel again, which sees the mark
 * and starts Android.
 *
 * The mark is the whole 4 KiB page at MARK_ADDR filled with a pseudo-random
 * pattern (xorshift64 from SEED, the same generator as the selector). The
 * reset is always a PMIC hard reset: Samsung's kernel sets that reset type
 * before a normal reboot and TrustZone's PSCI SYSTEM_RESET sets it as well
 * (writing a warm reset type to the PMIC over SPMI first changed nothing; the
 * XBL log still said "Reset Type: Hard Reset"). DRAM then goes without
 * refresh for a moment and some bits flip, more when Android has warmed the
 * phone up, so the selector accepts the page while fewer than 3/8 of its bits
 * differ. A single 64-bit mark failed one or two times out of three.
 *
 * The page is written with the MMU and data cache off (mark_and_reset): the
 * UEFI's page tables cannot map it since its MMU fix.
 * Every step is printed, so a hang shows where it stopped.
 *
 * Freestanding UEFI application: only the few table offsets it needs.
 * Build: see Makefile (clang, PE/COFF for AArch64, no libraries).
 */
typedef unsigned long long u64;
typedef unsigned short u16;
typedef u64 efi_status;
typedef void *efi_handle;

#define MARK_ADDR 0x17FE00000ULL
#define SEED      0x9E3779B97F4A7C15ULL	/* first xorshift64 state, as in the selector */
#define ALLOCATE_ADDRESS 2
#define EFI_RESERVED_MEMORY 0

struct text_out { void *reset; efi_status (*output_string)(struct text_out *, const u16 *); };
struct boot     { char hdr[24]; void *raise_tpl, *restore_tpl;
		  efi_status (*allocate_pages)(int type, int mem_type, u64 pages, u64 *addr);
		  void *f[25]; efi_status (*stall)(u64 us); };
struct system   { char hdr[24]; void *vendor; u64 rev; void *in_h, *in; void *out_h;
		  struct text_out *out; void *err_h, *err; void *rt; struct boot *bs; };

static struct text_out *out;

static void puts16(const char *s)
{
	u16 buf[96];
	int i = 0;

	for (; *s && i < 93; s++) {
		if (*s == '\n')
			buf[i++] = '\r';
		buf[i++] = (unsigned char)*s;
	}
	buf[i] = 0;
	out->output_string(out, buf);
}

static void puthex(const char *label, u64 v)
{
	char s[40], *p = s;
	int n;

	while (*label)
		*p++ = *label++;
	*p++ = '0';
	*p++ = 'x';
	for (n = 60; n >= 0; n -= 4)
		*p++ = "0123456789ABCDEF"[(v >> n) & 15];
	*p++ = '\n';
	*p = 0;
	puts16(s);
}

/*
 * Fill the page at addr with the pattern with the MMU and the data cache off,
 * then reset through PSCI. Never returns. Since the MMU fix of the UEFI
 * (fix-uefi-mmu.py: live block mappings are no longer split), AllocatePages
 * can no longer map the single page of the mark inside a larger block, and
 * writing it through the page tables faults. With the MMU off every access is
 * physical (the UEFI is identity-mapped, so execution continues at the same
 * address) and goes straight to DRAM. Pure assembly with no stack: with the
 * MMU off memory is Device memory, where the compiler's unaligned accesses
 * would fault.
 */
static void __attribute__((noreturn)) mark_and_reset(u64 addr, u64 seed)
{
	register u64 x0 __asm__("x0") = addr;
	register u64 x1 __asm__("x1") = seed;

	__asm__ volatile(
		"msr	daifset, #0xf\n\t"	/* no interrupts from here on */
		/* the code below runs with the MMU off: instruction fetches then go
		 * straight to DRAM, which may not yet hold what the UEFI loaded
		 * (it only cleans to the point of unification). Clean this whole
		 * block to the point of coherency and drop the instruction cache. */
		"mrs	x12, ctr_el0\n\t"
		"ubfx	x12, x12, #16, #4\n\t"	/* DminLine: log2(words) */
		"mov	x13, #4\n\t"
		"lsl	x12, x13, x12\n\t"		/* smallest data cache line, bytes */
		"adr	x13, 8f\n\t"
		"adr	x14, 9f\n\t"
		"sub	x15, x12, #1\n\t"
		"bic	x13, x13, x15\n"
		"7:\n\t"
		"dc	civac, x13\n\t"
		"add	x13, x13, x12\n\t"
		"cmp	x13, x14\n\t"
		"b.lo	7b\n\t"
		"dsb	sy\n\t"
		"ic	iallu\n\t"
		"dsb	sy\n\t"
		"isb\n"
		"8:\n\t"
		"mov	x9, x0\n\t"
		"mov	x10, x1\n\t"
		"mov	x11, x12\n\t"		/* keep the line size */
		"mrs	x12, CurrentEL\n\t"
		"ubfx	x12, x12, #2, #2\n\t"
		"cmp	x12, #2\n\t"
		"b.eq	1f\n\t"
		"mrs	x13, sctlr_el1\n\t"
		"bic	x13, x13, #1\n\t"	/* M: MMU off */
		"bic	x13, x13, #4\n\t"	/* C: data cache off */
		"msr	sctlr_el1, x13\n\t"
		"b	2f\n"
		"1:\n\t"
		"mrs	x13, sctlr_el2\n\t"
		"bic	x13, x13, #1\n\t"
		"bic	x13, x13, #4\n\t"
		"msr	sctlr_el2, x13\n"
		"2:\n\t"
		"isb\n\t"
		"dsb	sy\n\t"
		/* no stale cache line may later be written back over the page */
		"mov	x12, x9\n\t"
		"add	x14, x9, #0x1000\n"
		"3:\n\t"
		"dc	civac, x12\n\t"
		"add	x12, x12, x11\n\t"
		"cmp	x12, x14\n\t"
		"b.lo	3b\n\t"
		"dsb	sy\n\t"
		"mov	x12, xzr\n"
		"4:\n\t"
		"eor	x10, x10, x10, lsl #13\n\t"	/* xorshift64 */
		"eor	x10, x10, x10, lsr #7\n\t"
		"eor	x10, x10, x10, lsl #17\n\t"
		"str	x10, [x9, x12]\n\t"
		"add	x12, x12, #8\n\t"
		"cmp	x12, #0x1000\n\t"
		"b.lo	4b\n\t"
		"dsb	sy\n\t"
		"isb\n\t"
		"movz	x0, #0x0009\n\t"	/* PSCI SYSTEM_RESET 0x84000009 */
		"movk	x0, #0x8400, lsl #16\n\t"
		"mov	x1, xzr\n\t"
		"mov	x2, xzr\n\t"
		"mov	x3, xzr\n\t"
		"smc	#0\n\t"
		"movz	x0, #0x0012\n\t"	/* PSCI SYSTEM_RESET2 0xC4000012 (warm) */
		"movk	x0, #0xC400, lsl #16\n\t"
		"mov	x1, xzr\n\t"
		"mov	x2, xzr\n\t"
		"mov	x3, xzr\n\t"
		"smc	#0\n"
		"5:\n\t"
		"wfi\n\t"
		"b	5b\n"
		"9:\n"
		: : "r"(x0), "r"(x1)
		: "x2", "x3", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "memory");
	__builtin_unreachable();
}

efi_status efi_main(efi_handle image, struct system *st)
{
	u64 page = MARK_ADDR;
	efi_status s;

	(void)image;
	out = st->out;
	puts16("Reiniciando a Android...\n");
	/* reserve the page so nothing else in the UEFI uses it (the status is
	 * only informative: the writes below do not go through its mapping) */
	s = st->bs->allocate_pages(ALLOCATE_ADDRESS, EFI_RESERVED_MEMORY, 1, &page);
	puthex("  pagina de la marca: ", s);
	/*
	 * Mu's r9q ResetSystem has no warm reset (it returns and hits
	 * ASSERT (FALSE)) and its cold reset clears DRAM, so mark_and_reset calls
	 * TrustZone's PSCI directly: SYSTEM_RESET, as Linux's and TWRP's reboot.
	 * SYSTEM_RESET2 (architectural warm reset) keeps DRAM too, but resets only
	 * the CPUs: whatever boots next (the UEFI, a test kernel) then crashed on
	 * half-used hardware. It is only tried if SYSTEM_RESET ever returns.
	 */
	puts16("  marca con la MMU apagada y reinicio (PSCI SYSTEM_RESET)...\n");
	st->bs->stall(300000);
	mark_and_reset(MARK_ADDR, SEED);
}
