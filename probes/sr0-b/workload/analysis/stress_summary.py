"""SR0 stress-series summary (R10): one table over the Rows x KeyRate runs of scripts/run-stress.ps1.

Usage:
  stress_summary.py --root <runs dir> --series <series prefix> [--manifest <series.json>] [--out <path prefix>]
  stress_summary.py --selftest

Reads <root>/<series>-r<rows>-k<rate>/report/report.json (written by analyze_workload.py for each combination) and writes <out>.md and <out>.json.
Every combination is an ordinary gated run, so the thresholds are the section 11 ones; this only lines the numbers up.
Aggregation over the valid runs of a combination: medians/averages are the mean over runs, tails and peaks the worst run, missed vblanks the sum.
  fps p50   = 1000 / median presented interval          fps p95 = 1000 / 95th-percentile presented interval (the slow tail), lowest run
  CPU       = process in % of ONE core (100 = a core fully busy) and machine total %        GPU = our process on the adapter it rendered on
Standard library only (python 3.11, run with -I).
"""
import glob
import json
import math
import os
import re
import sys
import tempfile


def clean(v):
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else v


def vals(xs):
    return [x for x in (clean(v) for v in xs) if x is not None]


def mean(xs):
    xs = vals(xs)
    return sum(xs) / len(xs) if xs else None


def worst_hi(xs):
    xs = vals(xs)
    return max(xs) if xs else None


def worst_lo(xs):
    xs = vals(xs)
    return min(xs) if xs else None


def total(xs):
    xs = vals(xs)
    return sum(xs) if xs else None


def f(v, nd=1):
    return '-' if v is None else (f'{v:.{nd}f}' if isinstance(v, float) else str(v))


def dig(d, *path):
    for p in path:
        if not isinstance(d, dict):
            return None
        d = d.get(p)
    return d


def used_adapter_stats(res):
    """(adapter name, summed engine avg %, 3D avg %, 3D peak %, dedicated MB peak, shared MB peak) of the adapter the process rendered on."""
    gpu = (res or {}).get('gpu') or {}
    used = gpu.get('adapter_used')
    if not used:
        return None
    for a in gpu.get('adapters', []):
        if a.get('index') == used.get('index'):
            u = a.get('util_pct', {})
            return (a.get('name'), a.get('busy_avg_pct'), dig(u, '3d', 'avg'), dig(u, '3d', 'peak'),
                    dig(a, 'dedicated_mb', 'peak'), dig(a, 'shared_mb', 'peak'))
    return (used.get('name'), None, None, None, None, None)


def summarize(entry, report):
    """One table row (dict) for a combination from its report.json (None report = the gates aborted the combination)."""
    row = {'rows': entry['rows'], 'key_rate': entry['key_rate'], 'tag': entry['tag'], 'exit_code': entry.get('exit_code')}
    if report is None:
        row['overall'] = 'GATE'
        return row
    runs = report.get('runs', {})
    summ = [r.get('summary', {}) for r in runs.values()]
    valid = [r for r in runs.values() if not r.get('invalid')]
    failed = sorted({c['id'] + ' ' + c['name'] for r in runs.values() for c in r.get('checks', []) if c.get('status') == 'FAIL'})
    row.update({
        'overall': report.get('overall'), 'runs': len(runs), 'runs_valid': len(valid),
        'refusals': report.get('refusal_reasons', [])[:4], 'failed': failed,
        'fps_p50': mean([dig(s, 'fps', 'p50') for s in summ]), 'fps_p95': worst_lo([dig(s, 'fps', 'p95_tail') for s in summ]),
        'fps_mean': mean([dig(s, 'fps', 'mean') for s in summ]),
        'missed_vblanks': total([s.get('missed_vblanks') for s in summ]),
        'visible_p50_ms': mean([dig(s, 'visible_ms', 'p50') for s in summ]), 'visible_p95_ms': worst_hi([dig(s, 'visible_ms', 'p95') for s in summ]),
        'bridge_frame_p95_ms': worst_hi([dig(s, 'bridge_frame_ms', 'p95') for s in summ]),
        'mainactor_p99_ms': worst_hi([dig(s, 'mainactor_ms', 'p99') for s in summ]),
        'keys_typed': mean([dig(s, 'keys', 'typed') for s in summ]),
    })
    res = [s.get('resources') for s in summ if (s.get('resources') or {}).get('present') and (s.get('resources') or {}).get('samples')]
    row['resources_runs'] = len(res)
    if res:
        row.update({
            'cpu_total_avg': mean([dig(r, 'total_cpu_pct', 'avg') for r in res]), 'cpu_total_peak': worst_hi([dig(r, 'total_cpu_pct', 'peak') for r in res]),
            'cpu_proc_avg': mean([dig(r, 'proc_cpu_core_pct', 'avg') for r in res]), 'cpu_proc_peak': worst_hi([dig(r, 'proc_cpu_core_pct', 'peak') for r in res]),
            'pinned_samples': total([r.get('pinned_samples') for r in res]),
            'busiest_thread': next(iter(sorted(((dig(r, 'top_threads') or [{}])[0] for r in res), key=lambda t: -(t.get('avg_pct_of_core') or 0))), {}),
            'private_peak_mb': worst_hi([dig(r, 'private_mb', 'peak') for r in res]), 'private_slope_mb_min': worst_hi([dig(r, 'private_mb', 'slope_mb_per_min') for r in res]),
            'ws_peak_mb': worst_hi([dig(r, 'working_set_mb', 'peak') for r in res]),
            'handles_max': worst_hi([dig(r, 'handles', 'max') for r in res]), 'threads_max': worst_hi([dig(r, 'threads', 'max') for r in res]),
            'sampler_overhead_core_pct': mean([dig(r, 'sampler_cpu_core_pct', 'avg') for r in res]),
        })
        stats = [used_adapter_stats(r) for r in res]
        stats = [s for s in stats if s]
        if stats:
            names = [s[0] for s in stats]
            row['gpu_adapter'] = max(set(names), key=names.count)
            row['gpu_adapters_seen'] = sorted(set(names))
            row['gpu_busy_avg_pct'] = mean([s[1] for s in stats])
            row['gpu_3d_avg_pct'] = mean([s[2] for s in stats])
            row['gpu_3d_peak_pct'] = worst_hi([s[3] for s in stats])
            row['gpu_ded_peak_mb'] = worst_hi([s[4] for s in stats])
            row['gpu_shared_peak_mb'] = worst_hi([s[5] for s in stats])
        row['flags'] = sorted({fl for r in runs.values() for fl in r.get('flags', [])})
    return row


def find_entries(root, series, manifest):
    entries = []
    if manifest and os.path.isfile(manifest):
        try:
            data = json.load(open(manifest, encoding='utf-8-sig'))
            entries = data if isinstance(data, list) else [data]
        except (OSError, ValueError):
            entries = []
    seen = {e['tag'] for e in entries}
    for d in sorted(glob.glob(os.path.join(root, f'{series}-r*-k*'))):
        m = re.match(re.escape(series) + r'-r(\d+)-k([\d.]+)$', os.path.basename(d))
        if m and os.path.basename(d) not in seen:
            entries.append({'rows': int(m.group(1)), 'key_rate': float(m.group(2)), 'tag': os.path.basename(d), 'run_root': d})
    return sorted(entries, key=lambda e: (int(e['rows']), float(e['key_rate'])))


def build(root, series, manifest):
    rows = []
    for e in find_entries(root, series, manifest):
        rp = os.path.join(root, e['tag'], 'report', 'report.json')
        report = None
        if os.path.isfile(rp):
            try:
                report = json.load(open(rp, encoding='utf-8-sig'))
            except (OSError, ValueError):
                report = None
        rows.append(summarize(e, report))
    return rows


def render(series, rows):
    md = [f'# SR0 stress series {series}', '',
          'Each row is a normal gated run set (same section 11 thresholds). Means over runs for medians/averages, worst run for tails and peaks, sum for missed vblanks. '
          'fps p95 is the rate at the 95th-percentile presented interval (the slow tail). CPU in % of one core (100 = a core fully busy).', '',
          '| rows | keys/s | overall | runs ok | fps p50 | fps p95 | missed vblanks | input->visible p50 / p95 ms | bridge frame p95 ms | main-actor p99 ms | failed thresholds |',
          '|---|---|---|---|---|---|---|---|---|---|---|']
    for r in rows:
        if r['overall'] == 'GATE':
            md.append(f"| {r['rows']} | {r['key_rate']:g} | GATE (run-workload exit {r.get('exit_code')}) | - | - | - | - | - | - | - | - |")
            continue
        fails = '; '.join(x.split(' ')[0] for x in r['failed']) if r['failed'] else 'none'
        md.append(f"| {r['rows']} | {r['key_rate']:g} | {r['overall']} | {r['runs_valid']}/{r['runs']} | {f(r['fps_p50'])} | {f(r['fps_p95'])} | {f(r['missed_vblanks'], 0)} | "
                  f"{f(r['visible_p50_ms'], 2)} / {f(r['visible_p95_ms'], 2)} | {f(r['bridge_frame_p95_ms'], 2)} | {f(r['mainactor_p99_ms'], 2)} | {fails} |")
    md += ['', '| rows | keys/s | CPU total avg/peak % | process avg/peak (core %) | busiest thread | pinned samples | private peak MB (slope MB/min) | working set peak MB | '
           'handles / threads max | GPU adapter | GPU engines avg % (3D avg/peak) | GPU mem dedicated / shared peak MB | sampler overhead (core %) |',
           '|---|---|---|---|---|---|---|---|---|---|---|---|---|']
    for r in rows:
        if r['overall'] == 'GATE' or not r.get('resources_runs'):
            md.append(f"| {r['rows']} | {r['key_rate']:g} | not sampled | | | | | | | | | | |")
            continue
        t = r.get('busiest_thread') or {}
        md.append(f"| {r['rows']} | {r['key_rate']:g} | {f(r.get('cpu_total_avg'))}/{f(r.get('cpu_total_peak'))} | {f(r.get('cpu_proc_avg'))}/{f(r.get('cpu_proc_peak'))} | "
                  f"{t.get('tid', '-')}{('[' + t['name'] + ']') if t.get('name') else ''} {f(t.get('avg_pct_of_core'))}% | {f(r.get('pinned_samples'), 0)} | "
                  f"{f(r.get('private_peak_mb'))} ({f(r.get('private_slope_mb_min'), 2)}) | {f(r.get('ws_peak_mb'))} | {f(r.get('handles_max'), 0)} / {f(r.get('threads_max'), 0)} | "
                  f"{r.get('gpu_adapter', 'unknown')} | {f(r.get('gpu_busy_avg_pct'), 2)} ({f(r.get('gpu_3d_avg_pct'), 2)}/{f(r.get('gpu_3d_peak_pct'), 1)}) | "
                  f"{f(r.get('gpu_ded_peak_mb'))} / {f(r.get('gpu_shared_peak_mb'))} | {f(r.get('sampler_overhead_core_pct'))} |")
    notes = []
    for r in rows:
        for fl in r.get('flags', []) or []:
            notes.append(f"- rows={r['rows']} keys/s={r['key_rate']:g}: {fl}")
        for x in r.get('refusals', []) or []:
            notes.append(f"- rows={r['rows']} keys/s={r['key_rate']:g} refused: {x}")
    md += [''] + (['Flags and refusals:'] + notes if notes else ['Flags and refusals: none']) + ['']
    return '\n'.join(md)


def selftest():
    tmp = tempfile.mkdtemp(prefix='sr0-stress-selftest-')
    series = 'S1'

    def run(rows, rate, overall, fps, vis95, slope, adapter='NVIDIA GeForce RTX 4070 Laptop GPU'):
        d = os.path.join(tmp, f'{series}-r{rows}-k{rate}', 'report')
        os.makedirs(d)
        res = {'present': True, 'samples': 57, 'total_cpu_pct': {'avg': 12.0, 'peak': 20.0}, 'proc_cpu_core_pct': {'avg': 40.0, 'peak': 95.0}, 'pinned_samples': 1,
               'top_threads': [{'tid': 100, 'name': 'render', 'avg_pct_of_core': 38.0, 'peak_pct_of_core': 96.0}], 'private_mb': {'peak': 310.0, 'slope_mb_per_min': slope},
               'working_set_mb': {'peak': 370.0}, 'handles': {'max': 420}, 'threads': {'max': 36}, 'sampler_cpu_core_pct': {'avg': 3.0},
               'gpu': {'adapter_used': {'index': '1', 'name': adapter}, 'adapters': [{'index': '1', 'name': adapter, 'busy_avg_pct': 12.5,
                                                                                    'util_pct': {'3d': {'avg': 12.5, 'peak': 15.0}},
                                                                                    'dedicated_mb': {'peak': 775.0}, 'shared_mb': {'peak': 0.3}}]}}
        summary = {'fps': {'p50': fps, 'p95_tail': fps - 1, 'mean': fps}, 'missed_vblanks': 2, 'visible_ms': {'p50': 20.0, 'p95': vis95}, 'bridge_frame_ms': {'p95': 1.2},
                   'mainactor_ms': {'p99': 3.0}, 'keys': {'typed': 600}, 'resources': res}
        checks = [{'id': 'W4', 'name': 'input->visible p95 (ms)', 'status': 'FAIL' if vis95 > 50 else 'PASS'}]
        rep = {'overall': overall, 'refusal_reasons': [], 'runs': {'r1': {'summary': summary, 'invalid': [], 'flags': ['pinned core: x'], 'checks': checks},
                                                                 'r2': {'summary': summary, 'invalid': [], 'flags': [], 'checks': checks}}}
        json.dump(rep, open(os.path.join(d, 'report.json'), 'w'))
    run(200, 10, 'PASS', 60.0, 30.0, 0.2)
    run(5000, 30, 'FAIL', 22.0, 180.0, 6.0)
    os.makedirs(os.path.join(tmp, f'{series}-r1000-k10'))        # gate abort: directory without a report
    rows = build(tmp, series, None)
    text = render(series, rows)
    ok = [r['overall'] for r in rows] == ['PASS', 'GATE', 'FAIL'] and 'W4' in text and 'GATE' in text and 'NVIDIA' in text and '| 5000 | 30 |' in text
    ok = ok and rows[2]['private_slope_mb_min'] == 6.0 and rows[2]['fps_p50'] == 22.0
    print(text)
    print('SELFTEST ' + ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


def main(argv):
    if '--selftest' in argv:
        return selftest()
    opts = {}
    i = 0
    while i < len(argv):
        if argv[i].startswith('--') and i + 1 < len(argv):
            opts[argv[i][2:]] = argv[i + 1]
            i += 1
        i += 1
    if not opts.get('root') or not opts.get('series'):
        print(__doc__)
        return 3
    rows = build(opts['root'], opts['series'], opts.get('manifest'))
    if not rows:
        print(f"no runs found for series {opts['series']} under {opts['root']}")
        return 2
    text = render(opts['series'], rows)
    print(text)
    out = opts.get('out')
    if out:
        os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
        with open(out + '.md', 'w') as fh:
            fh.write(text + '\n')
        with open(out + '.json', 'w') as fh:
            json.dump({'series': opts['series'], 'rows': rows}, fh, indent=2, default=str)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
