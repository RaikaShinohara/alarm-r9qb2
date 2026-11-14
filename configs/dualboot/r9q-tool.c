/*
 * r9q-tool: four small helpers for the r9q dual boot installer, run by TWRP.
 * Static AArch64, no libc (raw syscalls), so it runs in any recovery.
 *
 *   r9q-tool keys [BRIGHTNESS_FILE]
 *       Waits for one press of Volume up / Volume down / Power and prints
 *       "up", "down" or "power". The key devices are grabbed (EVIOCGRAB) while
 *       it waits, so TWRP does not see the presses (its Power key turns the
 *       screen off). A press while BRIGHTNESS_FILE reads 0 (TWRP blanked the
 *       screen) is ignored, so nothing is chosen blind.
 *
 *   r9q-tool blkpg add|resize|del DISK PARTNO START_BYTES LENGTH_BYTES
 *       Tells the kernel about one partition (BLKPG ioctl), so a new GPT is
 *       used without re-reading the whole disk (which fails while anything on
 *       it is open). Only the kernel's view changes; the GPT is written by sgdisk.
 *
 *   r9q-tool dmremove NAME
 *       Removes the device-mapper device NAME (DM_DEV_REMOVE ioctl). TWRP maps
 *       "userdata" over sda34 for Android's metadata encryption and keeps it
 *       open, so mkfs says "In use by the system"; TWRP has no dmctl/dmsetup.
 *
 *   r9q-tool unlz4 < IN > OUT
 *       Decompresses LZ4, in the Linux kernel's "legacy" format or the frame
 *       format: Android kernels shipped as Image.lz4 (TWRP has gzip, bzip2 and
 *       xz, not LZ4). The output is kept whole in memory (a kernel is tens of
 *       MB), so linked blocks can refer back freely.
 *
 * Exit status 0 on success; messages on stderr.
 */
typedef unsigned long u64;
typedef long s64;

static s64 sys6(s64 n, s64 a, s64 b, s64 c, s64 d, s64 e)
{
	register s64 x8 __asm__("x8") = n;
	register s64 x0 __asm__("x0") = a;
	register s64 x1 __asm__("x1") = b;
	register s64 x2 __asm__("x2") = c;
	register s64 x3 __asm__("x3") = d;
	register s64 x4 __asm__("x4") = e;
	register s64 x5 __asm__("x5") = 0;	/* mmap's offset */
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
	return x0;
}
#define SYS_ioctl 29
#define SYS_openat 56
#define SYS_close 57
#define SYS_read 63
#define SYS_write 64
#define SYS_ppoll 73
#define SYS_exit_group 94
#define SYS_mmap 222
#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_CLOEXEC 02000000

static int sopen(const char *p) { return sys6(SYS_openat, AT_FDCWD, (s64)p, O_RDONLY | O_CLOEXEC, 0, 0); }
static s64 sread(int fd, void *b, u64 n) { return sys6(SYS_read, fd, (s64)b, n, 0, 0); }
static int sioctl(int fd, u64 req, void *arg) { return sys6(SYS_ioctl, fd, req, (s64)arg, 0, 0); }
static void sclose(int fd) { sys6(SYS_close, fd, 0, 0, 0, 0); }
static __attribute__((noreturn)) void sexit(int c) { sys6(SYS_exit_group, c, 0, 0, 0, 0); for (;;); }

static u64 slen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }
static void out(int fd, const char *s) { sys6(SYS_write, fd, (s64)s, slen(s), 0, 0); }
static __attribute__((noreturn)) void die(const char *m) { out(2, "r9q-tool: "); out(2, m); out(2, "\n"); sexit(1); }
static int streq(const char *a, const char *b) { while (*a && *a == *b) a++, b++; return *a == *b; }

static int parse(const char *s, s64 *v)
{
	s64 r = 0;
	if (!*s) return 0;
	for (; *s; s++) {
		if (*s < '0' || *s > '9') return 0;
		if (r > (0x7fffffffffffffffL - 9) / 10) return 0;
		r = r * 10 + (*s - '0');
	}
	*v = r;
	return 1;
}

/* ---- keys ---- */
#define EV_KEY 1
#define KEY_VOLUMEDOWN 114
#define KEY_VOLUMEUP 115
#define KEY_POWER 116
#define EVIOCGBIT_KEY(len) ((2UL << 30) | ((u64)(len) << 16) | ('E' << 8) | (0x20 + EV_KEY))
#define EVIOCGRAB ((1UL << 30) | (4UL << 16) | ('E' << 8) | 0x90)
struct input_event { s64 sec, usec; unsigned short type, code; int value; };
struct pollfd { int fd; short events, revents; };
#define POLLIN 1
#define MAXDEV 32

static int screen_dark(const char *path)
{
	char b[8];
	int fd;
	s64 n;
	if (!path) return 0;
	fd = sopen(path);
	if (fd < 0) return 0;
	n = sread(fd, b, sizeof b);
	sclose(fd);
	return n >= 1 && b[0] == '0' && (n == 1 || b[1] < '0' || b[1] > '9');
}

static int keys(const char *bright)
{
	struct pollfd p[MAXDEV];
	int n = 0;
	char name[] = "/dev/input/eventNN";
	for (int i = 0; i < MAXDEV; i++) {
		unsigned char bits[96] = {0};	/* KEY_MAX 0x2ff -> 96 bytes */
		int fd;
		name[16] = i < 10 ? '0' + i : '0' + i / 10;
		name[17] = i < 10 ? 0 : '0' + i % 10;
		fd = sopen(name);
		if (fd < 0) continue;
		if (sioctl(fd, EVIOCGBIT_KEY(sizeof bits), bits) < 0) { sclose(fd); continue; }
#define HAS(k) (bits[(k) / 8] & (1 << ((k) % 8)))
		if (!HAS(KEY_VOLUMEUP) && !HAS(KEY_VOLUMEDOWN) && !HAS(KEY_POWER)) { sclose(fd); continue; }
		sioctl(fd, EVIOCGRAB, (void *)1);	/* best effort: keys still work without it */
		p[n].fd = fd;
		p[n].events = POLLIN;
		n++;
	}
	if (!n) die("no volume/power key device in /dev/input");
	for (;;) {
		if (sys6(SYS_ppoll, (s64)p, n, 0, 0, 8) < 0) continue;
		for (int i = 0; i < n; i++) {
			struct input_event ev[16];
			s64 r;
			if (!(p[i].revents & POLLIN)) continue;
			r = sread(p[i].fd, ev, sizeof ev);
			for (s64 j = 0; j < r / (s64)sizeof ev[0]; j++) {
				const char *k = 0;
				if (ev[j].type != EV_KEY || ev[j].value != 1) continue;	/* presses only */
				if (ev[j].code == KEY_VOLUMEUP) k = "up\n";
				else if (ev[j].code == KEY_VOLUMEDOWN) k = "down\n";
				else if (ev[j].code == KEY_POWER) k = "power\n";
				if (!k || screen_dark(bright)) continue;
				out(1, k);
				return 0;	/* exit closes the devices: the grab ends */
			}
		}
	}
}

/* ---- blkpg ---- */
#define BLKPG 0x1269
struct blkpg_partition { s64 start, length; int pno; char devname[64], volname[64]; };
struct blkpg_ioctl_arg { int op, flags, datalen; void *data; };

static int blkpg(char **a)
{
	struct blkpg_partition bp = {0};
	struct blkpg_ioctl_arg arg = {0};
	s64 pno, start, len;
	int fd, op, r;
	if (streq(a[0], "add")) op = 1;
	else if (streq(a[0], "del")) op = 2;
	else if (streq(a[0], "resize")) op = 3;
	else die("blkpg: add, resize or del");
	if (!parse(a[2], &pno) || !parse(a[3], &start) || !parse(a[4], &len) || pno < 1 || pno > 255)
		die("blkpg: bad number");
	bp.pno = pno;
	bp.start = start;
	bp.length = len;
	arg.op = op;
	arg.datalen = sizeof bp;
	arg.data = &bp;
	fd = sopen(a[1]);
	if (fd < 0) die("blkpg: cannot open the disk");
	r = sioctl(fd, BLKPG, &arg);
	sclose(fd);
	if (r < 0) {
		char e[] = "blkpg: ioctl failed, errno 000";
		r = -r;
		e[27] = '0' + r / 100 % 10; e[28] = '0' + r / 10 % 10; e[29] = '0' + r % 10;
		die(e);
	}
	return 0;
}

/* ---- dmremove ---- */
struct dm_ioctl {
	unsigned int version[3], data_size, data_start, target_count;
	int open_count;
	unsigned int flags, event_nr, padding;
	u64 dev;
	char name[128], uuid[129], data[7];
};
#define DM_DEV_REMOVE 0xC138FD04	/* _IOWR(0xfd, 4, struct dm_ioctl): 312 bytes */
_Static_assert(sizeof(struct dm_ioctl) == 312, "struct dm_ioctl is 312 bytes");

static int dmremove(char *name)
{
	struct dm_ioctl io = {0};
	int fd, r, i;
	io.version[0] = 4;
	io.data_size = io.data_start = sizeof io;
	for (i = 0; name[i]; i++) {
		if (i == 127) die("dmremove: name too long");
		io.name[i] = name[i];
	}
	fd = sopen("/dev/device-mapper");
	if (fd < 0) die("dmremove: cannot open /dev/device-mapper");
	r = sioctl(fd, DM_DEV_REMOVE, &io);
	sclose(fd);
	if (r < 0) {
		char e[] = "dmremove: ioctl failed, errno 000";
		r = -r;
		e[30] = '0' + r / 100 % 10; e[31] = '0' + r / 10 % 10; e[32] = '0' + r % 10;
		die(e);
	}
	return 0;
}

/* ---- unlz4 ---- */
typedef unsigned char u8;
#define LZ4_MAX (256UL << 20)	/* biggest input and output accepted */

static u8 *smap(u64 n)	/* anonymous, private, read/write; pages come on first use */
{
	s64 p = sys6(SYS_mmap, 0, n, 3, 0x22, -1);
	return p < 0 && p > -4096 ? 0 : (u8 *)p;
}
static u64 le(const u8 *p, int n) { u64 v = 0; while (n--) v = v << 8 | p[n]; return v; }

/* one block: src[0..n) appended to dst at *o (references reach back into dst) */
static void block(const u8 *s, u64 n, u8 *d, u64 *o)
{
	const u8 *e = s + n;
	u64 p = *o;
	while (s < e) {
		u64 t = *s++, l = t >> 4, m;
		if (l == 15) do { if (s >= e) die("lz4: bad literal length"); l += *s; } while (*s++ == 255);
		if (l > (u64)(e - s) || p + l > LZ4_MAX) die("lz4: literals past the end");
		while (l--) d[p++] = *s++;
		if (s == e) break;	/* the last sequence has literals only */
		if (e - s < 2) die("lz4: bad offset");
		u64 off = le(s, 2); s += 2;
		if (!off || off > p) die("lz4: offset out of range");
		m = (t & 15) + 4;
		if ((t & 15) == 15) do { if (s >= e) die("lz4: bad match length"); m += *s; } while (*s++ == 255);
		if (p + m > LZ4_MAX) die("lz4: output too big");
		while (m--) { d[p] = d[p - off]; p++; }
	}
	*o = p;
}

static int unlz4(void)
{
	u8 *in = smap(LZ4_MAX), *d = smap(LZ4_MAX);
	u64 n = 0, o = 0, i;
	s64 r;
	if (!in || !d) die("lz4: out of memory");
	while ((r = sread(0, in + n, LZ4_MAX - n)) > 0) n += r;
	if (r < 0) die("lz4: cannot read");
	if (n >= LZ4_MAX) die("lz4: input too big");
	if (n >= 4 && le(in, 4) == 0x184C2102) {	/* legacy: [u32 size][block]... */
		for (i = 4; i + 4 <= n; ) {
			u64 b = le(in + i, 4);
			if (b == 0x184C2102) { i += 4; continue; }	/* concatenated stream */
			i += 4;
			if (b > n - i) {
				/* the kernel's zImage padding: anything after the last block */
				if (o) break;
				die("lz4: truncated block");
			}
			block(in + i, b, d, &o);
			i += b;
		}
	} else if (n >= 7 && le(in, 4) == 0x184D2204) {	/* frame */
		u8 flg = in[4];
		if ((flg >> 6) != 1) die("lz4: unknown frame version");
		i = 6 + ((flg & 8) ? 8 : 0) + ((flg & 1) ? 4 : 0) + 1;	/* FLG BD [size] [dict] HC */
		for (;;) {
			if (i + 4 > n) die("lz4: truncated frame");
			u64 b = le(in + i, 4), sz = b & 0x7fffffff;
			i += 4;
			if (!b) break;	/* end mark */
			if (sz > n - i) die("lz4: truncated block");
			if (b >> 31) {	/* stored */
				if (o + sz > LZ4_MAX) die("lz4: output too big");
				for (u64 k = 0; k < sz; k++) d[o++] = in[i + k];
			} else block(in + i, sz, d, &o);
			i += sz + ((flg & 16) ? 4 : 0);	/* block checksum */
		}
	} else die("lz4: not LZ4 data");
	for (i = 0; i < o; ) {
		r = sys6(SYS_write, 1, (s64)(d + i), o - i, 0, 0);
		if (r <= 0) die("lz4: cannot write");
		i += r;
	}
	return 0;
}

int main(long argc, char **argv)
{
	if (argc >= 2 && streq(argv[1], "keys") && argc <= 3) return keys(argc == 3 ? argv[2] : 0);
	if (argc == 7 && streq(argv[1], "blkpg")) return blkpg(argv + 2);
	if (argc == 3 && streq(argv[1], "dmremove")) return dmremove(argv[2]);
	if (argc == 2 && streq(argv[1], "unlz4")) return unlz4();
	die("usage: r9q-tool keys [BRIGHTNESS_FILE] | blkpg add|resize|del DISK PARTNO START LENGTH | dmremove NAME | unlz4");
}

/* entry point: the kernel leaves argc at [sp], argv right after it */
__attribute__((naked, noreturn)) void _start(void)
{
	__asm__ volatile(
		"ldr x0, [sp]\n"
		"add x1, sp, #8\n"
		"bl main\n"
		"mov x8, #94\n"
		"svc #0\n");
}
