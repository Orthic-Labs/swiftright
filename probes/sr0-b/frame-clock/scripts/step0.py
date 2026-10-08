# step0.py  (run with py -3.11 -I or python3 -I)
# Offline re-analysis of existing PresentMon v1 CSV rows for given ProcessIDs.
# Usage: step0.py <pm.csv> <pid> [<pid> ...]
import csv, sys


def pct(sorted_vals, p):
    if not sorted_vals:
        return float('nan')
    return sorted_vals[min(len(sorted_vals) - 1, int(p * (len(sorted_vals) - 1) + 0.5))]


def analyse(rows, pid):
    rs = [r for r in rows if r['ProcessID'] == pid]
    print('=== pid=%s rows=%d' % (pid, len(rs)))
    if not rs:
        print('no rows for pid')
        return
    t0 = float(rs[0]['TimeInSeconds'])
    tl = float(rs[-1]['TimeInSeconds'])
    # issue 1: Dropped=1 timeline relative to first present of this process
    drops = [(float(r['TimeInSeconds']) - t0, r['PresentMode']) for r in rs if r.get('Dropped') == '1']
    modes = {}
    for _, m in drops:
        modes[m] = modes.get(m, 0) + 1
    print('first present t0=%.3f s abs; last present +%.3f s; span %.3f s' % (t0, tl - t0, tl - t0))
    print('dropped n=%d first=%s last=%s modes=%s' % (
        len(drops),
        ('+%.3f s' % drops[0][0]) if drops else 'n/a',
        ('+%.3f s' % drops[-1][0]) if drops else 'n/a',
        modes))
    # issue 2: displayed intervals inside the workload (gaps > 100 ms are idle, excluded)
    seq = []
    for r in rs:
        v = r['msBetweenDisplayChange']
        if v in ('', 'NA'):
            continue
        x = float(v)
        if 0 < x < 100:
            seq.append(x)
    if not seq:
        print('no displayed intervals')
        return
    s = sorted(seq)
    n = len(s)
    print('displayed n=%d min=%.3f p1=%.3f p5=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f' % (
        n, s[0], pct(s, .01), pct(s, .05), pct(s, .5), pct(s, .95), pct(s, .99), s[-1]))
    long_idx = [i for i, x in enumerate(seq) if x > 16.8]
    pair_sums = []
    for i in long_idx:
        if i + 1 < len(seq):
            pair_sums.append(seq[i] + seq[i + 1])
    near_T = sum(1 for p in pair_sums if abs(p - 2 * 16.664) < 0.3)
    print('long(>16.8 ms) intervals=%d; of those followed by a short one with pair sum within 0.3 ms of 33.328: %d' % (
        len(long_idx), near_T))
    print('next interval after long (first 20):', [round(seq[i + 1], 3) for i in long_idx if i + 1 < len(seq)][:20])
    # lag-1 autocorrelation of deviation from 16.664
    dev = [x - 16.664 for x in seq]
    mu = sum(dev) / len(dev)
    den = sum((d - mu) ** 2 for d in dev) or 1.0
    ac1 = sum((dev[i] - mu) * (dev[i + 1] - mu) for i in range(len(dev) - 1)) / den
    print('lag-1 autocorr of deviation=%.3f' % ac1)
    # steps of one refresh period would show as >24.996 ms intervals (missed vblank)
    missed = sum(1 for x in seq if x > 24.996)
    print('intervals > 24.996 ms (missed vblank candidates)=%d' % missed)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    with open(path, newline='', encoding='utf-8-sig') as f:
        rows = list(csv.DictReader(f))
    for pid in sys.argv[2:]:
        analyse(rows, pid)


if __name__ == '__main__':
    main()
