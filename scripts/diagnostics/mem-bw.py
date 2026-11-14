#!/usr/bin/env python3
# Copy bandwidth per buffer size on one core: L1/L2 (64-256 KB), L3 (2 MB,
# the shared 4 MB L3) and RAM (64 MB). Copies into a preallocated buffer, so
# only memcpy is timed. Usage: mem-bw.py [cpu ...]
import os, sys, time

SIZES = [(64, 'K'), (256, 'K'), (2048, 'K'), (65536, 'K')]


def run(cpu):
    os.sched_setaffinity(0, {cpu})
    out = []
    for kb, _ in SIZES:
        n = kb << 10
        src = bytearray(b'\1') * n
        dst = bytearray(n)
        mv = memoryview(dst)
        reps = max(4, (512 << 20) // n)
        best = 0.0
        for _ in range(3):
            t = time.perf_counter()
            for _ in range(reps):
                mv[:] = src
            dt = time.perf_counter() - t
            best = max(best, 2 * n * reps / dt / 1e9)  # read + write
        out.append('%5s %5.1f' % ('%dK' % kb if kb < 1024 else '%dM' % (kb >> 10), best))
    print('cpu%d GB/s: %s' % (cpu, ' | '.join(out)), flush=True)


for c in [int(x) for x in sys.argv[1:]] or [7, 4, 0]:
    run(c)
