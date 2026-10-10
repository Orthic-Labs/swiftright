"""SR0 Mac workload resource sampler (R10 / U2). Standard library only; run with -I.

Once a second until the WorkloadMac process has appeared and exited (or SIGTERM): machine CPU (HOST_CPU_LOAD_INFO deltas), load
average, the workload process (CPU in % of one core, phys_footprint, resident size, thread count), the sum and top-3 of every
other process this user can read (proc_pid_rusage), and this sampler's own CPU. Timestamps are CLOCK_UPTIME_RAW ns, the domain of
the app's and the recorder's samples.

Usage: mac_sampler.py --out <resources.csv> [--proc WorkloadMac] [--interval 1.0] [--max-s 200]
"""
import csv
import ctypes
import os
import signal
import sys
import time

opts = {}
a = sys.argv[1:]
i = 0
while i < len(a):
    if a[i].startswith('--'):
        opts[a[i][2:]] = a[i + 1] if i + 1 < len(a) else '1'
        i += 1
    i += 1
out_path = opts['out']
proc_name = opts.get('proc', 'WorkloadMac')
interval = float(opts.get('interval', '1.0'))
max_s = float(opts.get('max-s', '240'))

libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
libc.mach_host_self.restype = ctypes.c_uint32
libc.host_statistics.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
libc.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
libc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
libc.proc_name.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]

class TimebaseInfo(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]

tb = TimebaseInfo()
libc.mach_timebase_info(ctypes.byref(tb))
TICK_NS = tb.numer / tb.denom
host = libc.mach_host_self()
NCPU = os.cpu_count() or 1


def uptime_ns():
    return time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)


def cpu_ticks():
    buf = (ctypes.c_uint32 * 4)()
    cnt = ctypes.c_uint32(4)
    libc.host_statistics(host, 3, buf, ctypes.byref(cnt))   # HOST_CPU_LOAD_INFO: user, system, idle, nice
    return tuple(buf)


def pids():
    n = libc.proc_listallpids(None, 0)
    buf = (ctypes.c_int * (n + 64))()
    n = libc.proc_listallpids(buf, ctypes.sizeof(buf))
    return list(buf[:max(0, n)])


def rusage(pid):
    buf = (ctypes.c_uint64 * 80)()
    if libc.proc_pid_rusage(pid, 4, buf) != 0:     # RUSAGE_INFO_V4; the 16-byte uuid is the first two words
        return None
    return {'cpu_ticks': buf[2] + buf[3], 'resident': buf[8], 'footprint': buf[9]}


def threads(pid):
    buf = (ctypes.c_uint8 * 128)()
    if libc.proc_pidinfo(pid, 4, 0, buf, 128) <= 0:    # PROC_PIDTASKINFO
        return 0
    return ctypes.c_int32.from_buffer(buf, 48 + 9 * 4).value     # pti_threadnum


def name_of(pid):
    buf = ctypes.create_string_buffer(64)
    libc.proc_name(pid, buf, 64)
    return buf.value.decode('utf-8', 'replace')


stop = [False]
signal.signal(signal.SIGTERM, lambda *_: stop.__setitem__(0, True))
signal.signal(signal.SIGINT, lambda *_: stop.__setitem__(0, True))

os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
f = open(out_path, 'w', newline='')
w = csv.writer(f)
w.writerow(['t_uptime_ns', 'machine_cpu_pct', 'load1', 'app_pid', 'app_cpu_core_pct', 'app_footprint_bytes', 'app_resident_bytes',
            'app_threads', 'others_cpu_core_pct', 'top1', 'top1_core_pct', 'top2', 'top2_core_pct', 'top3', 'top3_core_pct',
            'sampler_cpu_core_pct'])
names = {}
prev_cpu = cpu_ticks()
prev_proc = {}
prev_t = uptime_ns()
prev_self = time.process_time()
start = prev_t
seen_app = False
while not stop[0]:
    time.sleep(interval)
    now = uptime_ns()
    if (now - start) / 1e9 > max_s:
        break
    dt = (now - prev_t) / 1e9
    cur_cpu = cpu_ticks()
    d = [c - p for c, p in zip(cur_cpu, prev_cpu)]
    tot = sum(d) or 1
    machine = 100.0 * (d[0] + d[1] + d[3]) / tot
    cur_proc = {}
    app_pid = 0
    for pid in pids():
        if pid <= 0:
            continue
        ru = rusage(pid)
        if ru is None:
            continue
        cur_proc[pid] = ru
        if pid not in names:
            names[pid] = name_of(pid)
        if names[pid] == proc_name:
            app_pid = pid
    app_cpu = app_fp = app_res = app_thr = 0
    others = []
    me = os.getpid()
    for pid, ru in cur_proc.items():
        p = prev_proc.get(pid)
        pct = 0.0
        if p is not None:
            pct = 100.0 * (ru['cpu_ticks'] - p['cpu_ticks']) * TICK_NS / 1e9 / dt
        if pid == app_pid:
            app_cpu, app_fp, app_res = pct, ru['footprint'], ru['resident']
            app_thr = threads(pid)
        elif pid != me:
            others.append((pct, names[pid]))
    others.sort(reverse=True)
    top = others[:3] + [(0.0, '')] * 3
    self_cpu = 100.0 * (time.process_time() - prev_self) / dt
    w.writerow([now, f'{machine:.2f}', f'{os.getloadavg()[0]:.2f}', app_pid, f'{app_cpu:.2f}', app_fp, app_res, app_thr,
                f'{sum(o[0] for o in others):.2f}', top[0][1], f'{top[0][0]:.1f}', top[1][1], f'{top[1][0]:.1f}', top[2][1], f'{top[2][0]:.1f}',
                f'{self_cpu:.2f}'])
    f.flush()
    prev_cpu, prev_proc, prev_t, prev_self = cur_cpu, cur_proc, now, time.process_time()
    if app_pid:
        seen_app = True
    elif seen_app:
        break
f.close()
