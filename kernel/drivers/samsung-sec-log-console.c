// SPDX-License-Identifier: GPL-2.0-only
/*
 * Persistent bring-up console for Samsung Qualcomm phones (Galaxy S21 FE r9q).
 *
 * Samsung's XBL/ABL and downstream kernels share a ring buffer called
 * sec_log_buf (cmdline "sec_log=0x200000@0xF0200000" on r9q). After a reset
 * the next downstream kernel (e.g. TWRP) exposes the previous contents as
 * /proc/last_kmsg, and the ring survives watchdog bites that wipe pstore.
 * Writing the mainline printk stream there makes early hangs debuggable.
 *
 * Adapted from the SM-X910 (Galaxy Tab S9 Ultra) postmarketOS bring-up
 * driver "samsung-gts9uwifi-sec-log.c" (GPL-2.0-only). Differences: it is
 * registered from early_initcall, maps the ring write-combined so data reaches
 * DRAM before a watchdog bite, and keeps previous_index in sync on each write.
 */

#include <linux/console.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/of_reserved_mem.h>
#include <linux/printk.h>

#define SEC_LOG_MAGIC	0x4d474f4c /* "LOGM" */

struct sec_log_header {
	u32 boot_count;
	u32 magic;
	u32 index;
	u32 previous_index;
	u8 data[];
};

static struct sec_log_header *sec_log_hdr;
static size_t sec_log_size;

static void notrace sec_log_console_write(struct console *con,
					  const char *text, unsigned int count)
{
	struct sec_log_header *hdr = sec_log_hdr;
	size_t first;
	u32 index;

	if (!hdr || !count)
		return;

	if (count > sec_log_size) {
		text += count - sec_log_size;
		count = sec_log_size;
	}

	index = READ_ONCE(hdr->index);
	first = min_t(size_t, count, sec_log_size - index % sec_log_size);
	memcpy(&hdr->data[index % sec_log_size], text, first);
	if (first != count)
		memcpy(hdr->data, text + first, count - first);

	/* The downstream ring index grows monotonically */
	WRITE_ONCE(hdr->index, index + count);
	WRITE_ONCE(hdr->previous_index, index + count);
}

static struct console sec_log_console = {
	.name	= "sec_log",
	.write	= sec_log_console_write,
	.flags	= CON_ENABLED | CON_ANYTIME | CON_PRINTBUFFER,
	.index	= -1,
};

static int __init sec_log_console_init(void)
{
	struct reserved_mem *rmem;
	struct device_node *np;
	void *mem;

	np = of_find_compatible_node(NULL, NULL, "samsung,sec-log-buf");
	if (!np)
		return 0;

	rmem = of_reserved_mem_lookup(np);
	of_node_put(np);
	if (!rmem || rmem->size <= sizeof(struct sec_log_header)) {
		pr_err("sec_log: invalid reservation\n");
		return -EINVAL;
	}

	mem = memremap(rmem->base, rmem->size, MEMREMAP_WC);
	if (!mem) {
		pr_err("sec_log: cannot map %pa\n", &rmem->base);
		return -ENOMEM;
	}

	sec_log_hdr = mem;
	sec_log_size = rmem->size - sizeof(struct sec_log_header);

	if (READ_ONCE(sec_log_hdr->magic) != SEC_LOG_MAGIC) {
		WRITE_ONCE(sec_log_hdr->boot_count, 0);
		WRITE_ONCE(sec_log_hdr->magic, SEC_LOG_MAGIC);
	}
	WRITE_ONCE(sec_log_hdr->boot_count,
		   READ_ONCE(sec_log_hdr->boot_count) + 1);
	WRITE_ONCE(sec_log_hdr->index, 0);
	WRITE_ONCE(sec_log_hdr->previous_index, 0);

	register_console(&sec_log_console);
	pr_info("sec_log: persistent console at %pa (%pa bytes)\n",
		&rmem->base, &rmem->size);
	return 0;
}
early_initcall(sec_log_console_init);
