import csv, sys

rows = list(csv.DictReader(open(sys.argv[1], newline='')))
print("columns:", list(rows[0].keys()) if rows else "none", "rows:", len(rows))
by = {}
for r in rows:
    by.setdefault(r['ProcessID'], []).append(r)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def pct(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(round(p / 100 * (len(a) - 1))))] if a else float('nan')


order = sorted(by, key=lambda k: float(by[k][0]['TimeInSeconds']))
for i, pid in enumerate(order, 1):
    rs = by[pid]
    disp = [x for x in (num(r.get('msBetweenDisplayChange')) for r in rs) if x and x > 0]
    pres = [x for x in (num(r.get('msBetweenPresents')) for r in rs) if x is not None]
    lat = [x for x in (num(r.get('msUntilDisplayed')) for r in rs) if x and x > 0]
    dropped = sum(1 for r in rs if r.get('Dropped') == '1')
    t0, t1 = float(rs[0]['TimeInSeconds']), float(rs[-1]['TimeInSeconds'])
    print(f"#{i} pid={pid} presents={len(rs)} span={t1 - t0:.2f}s dropped={dropped} "
          f"modes={sorted({r.get('PresentMode') for r in rs})} sync={sorted({r.get('SyncInterval') for r in rs})}")
    print(f"   display_change_ms n={len(disp)} p50={pct(disp, 50):.3f} p95={pct(disp, 95):.3f} "
          f"p99={pct(disp, 99):.3f} max={max(disp) if disp else float('nan'):.3f} "
          f"over16.7={sum(d > 16.7 for d in disp)} over20={sum(d > 20 for d in disp)} over34={sum(d > 34 for d in disp)}")
    print(f"   between_presents_ms p50={pct(pres, 50):.3f} p95={pct(pres, 95):.3f} p99={pct(pres, 99):.3f} "
          f"| until_displayed_ms p50={pct(lat, 50):.2f} p95={pct(lat, 95):.2f}")
