"""SR0 Mac workload: count-decoded key attribution (R10 / U2). Standard library only; run with -I.

The recorder (SckRecorder) attributes visible responses first-in-first-out: each changed frame of the response region resolves the oldest
pending key. When two keystrokes land in one displayed frame (the counter jumps by 2), the change count falls one short of the key count
and every later key is attributed to the next key's frame: a permanent shift of one key period (100 ms) per merge, ended only by the 1 s
timeout. This tool removes the shift without changing what is measured: it decodes the counter value each captured frame shows from the
frame's region hash (frames_display.csv `region_hash`, FNV-1a of the response-region bytes) and gives key k the first captured frame whose
counter is >= k. The hash -> counter dictionary comes from runs in which the recorder saw exactly one change per key (no merge), and every
such run must agree with it at every counter value (cross-validation); a frame with an unknown hash makes the run unattributable.

Usage: mac_reattribute.py --out <dir> <run-root> [<run-root> ...]
  Writes <dir>/<root-name>/rN/keys.csv (count-decoded, same columns) and copies every other run file; the recorder's own keys.csv is kept
  as keys.recorder.csv. The input roots are not modified.
"""
import csv
import os
import shutil
import sys

args = sys.argv[1:]
out = args[args.index('--out') + 1]
roots = [a for i, a in enumerate(args) if not a.startswith('--') and (i == 0 or args[i - 1] != '--out')]


def load(rdir):
    keys = sorted((r for r in csv.DictReader(open(f'{rdir}/keys.csv')) if int(r['seq']) > 0), key=lambda r: int(r['seq']))
    frames = [(int(r['display_ns']), r['region_hash']) for r in csv.DictReader(open(f'{rdir}/frames_display.csv'))]
    return keys, frames


def states(keys, frames):
    """Distinct consecutive region states, as (first display_ns, hash)."""
    seq, prev = [], None
    for t, h in frames:
        if h != prev:
            seq.append((t, h))
            prev = h
    return seq


runs = {}
for root in roots:
    for i in range(1, 10):
        rdir = f'{root}/r{i}'
        if os.path.isfile(f'{rdir}/keys.csv'):
            runs[rdir] = load(rdir)

# Clean runs: the state sequence after the last pre-key state has exactly one state per key and every key resolved ok.
clean = {}
for rdir, (keys, frames) in runs.items():
    first_post = int(keys[0]['t_post_ns'])
    st = [s for s in states(keys, frames)]
    # the state shown at the first post is counter 0; later states are counters 1..n
    idx0 = max(i for i, (t, _) in enumerate(st) if t <= first_post)
    seq = [h for _, h in st[idx0:]]
    if len(seq) == len(keys) + 1 and all(k['status'] == 'ok' for k in keys):
        clean[rdir] = seq
if not clean:
    sys.exit('no clean (merge-free) run to build the hash dictionary from')
ref_dir = max(clean, key=lambda d: len(clean[d]))
ref = clean[ref_dir]
dictionary = {h: n for n, h in enumerate(ref)}
if len(dictionary) != len(ref):
    sys.exit('reference states are not distinct')
print(f'dictionary: counters 0..{len(ref) - 1} from {ref_dir}; clean runs: {len(clean)} of {len(runs)}')
for rdir, seq in sorted(clean.items()):
    ok = all(ref[n] == h for n, h in enumerate(seq) if n < len(ref))
    print(f'  cross-check {rdir.split("/")[-2]}/{rdir.split("/")[-1]}: {len(seq) - 1} counters, agrees with dictionary: {ok}')
    if not ok:
        sys.exit('clean runs disagree: rendering differs between runs, dictionary invalid')

for rdir, (keys, frames) in sorted(runs.items()):
    root = rdir.rsplit('/', 1)[0]
    dst = f'{out}/{os.path.basename(root)}/{os.path.basename(rdir)}'
    shutil.copytree(rdir, dst, dirs_exist_ok=True)
    shutil.copy(f'{root}/build-mac.json', f'{out}/{os.path.basename(root)}/build-mac.json') if os.path.isfile(f'{root}/build-mac.json') else None
    if os.path.isfile(f'{root}/incremental.json'):
        shutil.copy(f'{root}/incremental.json', f'{out}/{os.path.basename(root)}/incremental.json')
    shutil.copy(f'{rdir}/keys.csv', f'{dst}/keys.recorder.csv')
    unknown = sum(1 for _, h in frames if h not in dictionary)
    first_post = int(keys[0]['t_post_ns'])
    # frames in order with decoded counter; a counter never decreases
    decoded = [(t, dictionary.get(h)) for t, h in frames]
    rows, lat, timeouts, merges = [], [], 0, 0
    prev_count = None
    for t, c in decoded:
        if c is None:
            continue
        if prev_count is not None and c - prev_count > 1:
            merges += 1
        prev_count = c
    j = 0
    best = [(t, c) for t, c in decoded if c is not None]
    for k in keys:
        seq, tp = int(k['seq']), int(k['t_post_ns'])
        hit = next(((t, c) for t, c in best if c >= seq and t > tp), None)
        if hit is None:
            rows.append([seq, k['char'], tp, 0, '', 'timeout', 0])
            timeouts += 1
        else:
            latency = (hit[0] - tp) / 1e6
            lat.append(latency)
            rows.append([seq, k['char'], tp, hit[0], f'{latency:.6f}', 'ok', 0])
    with open(f'{dst}/keys.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['seq', 'char', 't_post_ns', 't_display_ns', 'latency_ms', 'status', 'diff_px'])
        w.writerows(rows)
    rec = [float(k['latency_ms']) for k in keys if k['status'] == 'ok']
    name = f'{os.path.basename(root)}/{os.path.basename(rdir)}'
    print(f'{name}: keys={len(keys)} unknown_frame_hashes={unknown} counter_jumps_of_2+={merges} unresolved={timeouts} '
          f'recorder p50={sorted(rec)[len(rec) // 2]:.1f} decoded p50={sorted(lat)[len(lat) // 2]:.1f} ms')
