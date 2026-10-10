"""SR0 Mac workload resource summary (R10 / U2). Standard library only; run with -I.

Usage: mac_resources.py <run-root> [<run-root> ...]      (each root holds r1..rN/ with resources.csv from mac_sampler.py and app/)

Per run, over the measured window (app/meta.json measure_start_ticks..measure_end_ticks, CLOCK_UPTIME_RAW ns): machine CPU, load
average, the workload process (CPU % of one core, phys_footprint and its slope, resident, threads), the CPU of every other readable
process (sum and busiest), the sampler's own CPU. The R threshold (private-bytes slope <= 5 MB/min; the analyzer has no Mac
implementation) is the app's phys_footprint slope from app/counters.csv with the instrumentation tables' own growth subtracted
(the same app-only rule the Windows analysis uses); the raw slope is reported beside it.
"""
import csv
import json
import statistics
import sys


def slope_mb_min(points):
    """Least-squares slope of (t_seconds, MB) in MB per minute."""
    if len(points) < 3:
        return float('nan')
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    mx, my = statistics.mean(xs), statistics.mean(ys)
    den = sum((x - mx) ** 2 for x in xs)
    return 60.0 * sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else float('nan')


def summarize(rdir):
    meta = json.load(open(f'{rdir}/app/meta.json'))
    ms, me = int(meta['measure_start_ticks']), int(meta['measure_end_ticks'])
    out = {'run': rdir.rsplit('/', 1)[-1], 'instr': meta.get('instr')}
    rows = [r for r in csv.DictReader(open(f'{rdir}/resources.csv')) if ms <= int(r['t_uptime_ns']) <= me and int(r['app_pid']) > 0]
    out['samples'] = len(rows)
    if rows:
        f = lambda k: [float(r[k]) for r in rows]
        mach, load, app, oth, own = f('machine_cpu_pct'), f('load1'), f('app_cpu_core_pct'), f('others_cpu_core_pct'), f('sampler_cpu_core_pct')
        fp = [(int(r['t_uptime_ns']) / 1e9, int(r['app_footprint_bytes']) / 1048576) for r in rows]
        rs = [int(r['app_resident_bytes']) / 1048576 for r in rows]
        out.update({
            'machine_cpu_avg': statistics.mean(mach), 'machine_cpu_peak': max(mach), 'load1_avg': statistics.mean(load),
            'app_cpu_core_avg': statistics.mean(app), 'app_cpu_core_peak': max(app),
            'others_cpu_core_avg': statistics.mean(oth), 'others_cpu_core_peak': max(oth),
            'footprint_mb_avg': statistics.mean(p[1] for p in fp), 'footprint_mb_peak': max(p[1] for p in fp),
            'footprint_slope_mb_min': slope_mb_min(fp), 'resident_mb_avg': statistics.mean(rs), 'resident_mb_peak': max(rs),
            'threads_max': max(int(r['app_threads']) for r in rows), 'sampler_core_avg': statistics.mean(own),
        })
        busiest = {}
        for r in rows:
            for k in ('top1', 'top2', 'top3'):
                if r[k]:
                    busiest.setdefault(r[k], []).append(float(r[k + '_core_pct']))
        ranked = sorted(((sum(v) / len(rows), n) for n, v in busiest.items()), reverse=True)[:3]
        out['busiest_others'] = [f'{n} {a:.0f}%' for a, n in ranked]
    cs = [r for r in csv.DictReader(open(f'{rdir}/app/counters.csv')) if ms <= int(r['rx_ticks']) <= me]
    if len(cs) >= 3:
        pb = [(int(r['rx_ticks']) / 1e9, int(r['private_bytes']) / 1048576) for r in cs]
        tr = [(int(r['rx_ticks']) / 1e9, int(r['trace_used_bytes']) / 1048576) for r in cs]
        out['counters_private_slope_mb_min'] = slope_mb_min(pb)
        out['counters_trace_slope_mb_min'] = slope_mb_min(tr)
        out['counters_app_only_slope_mb_min'] = out['counters_private_slope_mb_min'] - out['counters_trace_slope_mb_min']
    return out


def fmt(v, nd=1):
    return f'{v:.{nd}f}' if isinstance(v, float) else str(v)


for root in sys.argv[1:]:
    for i in range(1, 10):
        rdir = f'{root}/r{i}'
        try:
            s = summarize(rdir)
        except (OSError, ValueError, KeyError):
            continue
        parts = [f"RESOURCES {rdir.split('/')[-2]}/{s['run']} instr={s['instr']} samples={s['samples']}"]
        for k in ('machine_cpu_avg', 'machine_cpu_peak', 'load1_avg', 'app_cpu_core_avg', 'app_cpu_core_peak', 'others_cpu_core_avg',
                  'footprint_mb_avg', 'footprint_mb_peak', 'footprint_slope_mb_min', 'resident_mb_avg', 'threads_max', 'sampler_core_avg',
                  'counters_private_slope_mb_min', 'counters_trace_slope_mb_min', 'counters_app_only_slope_mb_min'):
            if k in s:
                parts.append(f'{k}={fmt(s[k], 2)}')
        if 'busiest_others' in s:
            parts.append('busiest_others=[' + '; '.join(s['busiest_others']) + ']')
        print(' '.join(parts))
