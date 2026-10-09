#!/usr/bin/env python3
"""Summarize SR0-O 20x repeatability runs in out/repeat20/.

For each configuration: verdict counts (SELFTEST line), raw and canonical distinct hashes
(normalize-hash.py logic), per-assertion outcome agreement, and OBSERVE agreement.
Usage: repeat20-summary.py [out_dir]   (default: out/repeat20 relative to this script's parent)
"""
import collections
import glob
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "out", "repeat20")
RUNS = 20

# label -> file prefix produced by run-self-test.sh (name = "<arg>[-<variant>]-run<n>")
CONFIGS = [
    ("F1", "F1"), ("F2", "F2"), ("F3-list-0s", "F3"),
    ("F3-list-1s", "F3-list-1s"), ("F3-list-3s", "F3-list-3s"),
    ("F3-vstack-1s", "F3-vstack-1s"), ("F3-vstack-3s", "F3-vstack-3s"),
    ("F3-lazy-1s", "F3-lazy-1s"), ("F3-lazy-3s", "F3-lazy-3s"),
    ("F4", "F4"), ("F5", "F5"), ("F6", "F6"), ("F6-reduced", "F6-reduced"),
    ("F7", "F7"), ("F8", "F8"), ("F9", "F9"),
]


def load_events(path):
    events = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if raw:
                event = json.loads(raw)
                event.pop("mono_ns", None)
                events.append(event)
    return events


def normalized_lines(events):
    return [json.dumps(e, sort_keys=True, separators=(",", ":")) for e in events]


def raw_digest(events):
    return hashlib.sha256("\n".join(normalized_lines(events)).encode("utf-8")).hexdigest()


def canonical_digest(events):
    groups = {}
    for e in events:
        groups.setdefault(e.get("step", ""), []).append(json.dumps(e, sort_keys=True, separators=(",", ":")))
    body = "\n".join(f"#{step}\n" + "\n".join(sorted(lines)) for step, lines in groups.items())
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def parse_stdout(path):
    asserts, observes, verdict = {}, {}, None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            m = re.match(r"ASSERT (\S+) (\S+): (PASS|FAIL)\b(.*)", line.rstrip())
            if m:
                asserts[m.group(2)] = (m.group(3), m.group(4).strip())
                continue
            m = re.match(r"OBSERVE (\S+) (\S+): (.*)", line.rstrip())
            if m:
                observes[m.group(2)] = m.group(3).strip()
                continue
            m = re.match(r"SELFTEST (.*): (PASS|FAIL) \((\d+)/(\d+)\)", line.rstrip())
            if m:
                verdict = (m.group(2), int(m.group(3)), int(m.group(4)))
    return asserts, observes, verdict


def launch_attempts(path):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        return None
    return len(re.findall(r"^attempt \d+:", text, re.M))


def main():
    rows = []
    detail = []
    for label, prefix in CONFIGS:
        names = [f"{prefix}-run{n}" for n in range(1, RUNS + 1)]
        present = [n for n in names if os.path.exists(os.path.join(OUT, n + ".jsonl"))]
        verdicts, raws, canons = [], [], []
        assert_sets = collections.defaultdict(list)
        observe_sets = collections.defaultdict(list)
        relaunched = 0
        for name in names:
            jl = os.path.join(OUT, name + ".jsonl")
            so = os.path.join(OUT, name + ".stdout")
            lc = os.path.join(OUT, name + ".launch.txt")
            if not os.path.exists(jl):
                verdicts.append(("MISSING", 0, 0))
                continue
            events = load_events(jl)
            raws.append(raw_digest(events))
            canons.append(canonical_digest(events))
            asserts, observes, verdict = parse_stdout(so)
            verdicts.append(verdict or ("NOVERDICT", 0, 0))
            for key, val in asserts.items():
                assert_sets[key].append(val[0])
            for key, val in observes.items():
                observe_sets[key].append(val)
            attempts = launch_attempts(lc)
            if attempts and attempts > 1:
                relaunched += 1
        ok = sum(1 for v in verdicts if v[0] == "PASS")
        total_runs = sum(1 for v in verdicts if v[0] not in ("MISSING",))
        raw_distinct = len(set(raws))
        canon_distinct = len(set(canons))
        assert_fail = {k: v.count("FAIL") for k, v in assert_sets.items() if "FAIL" in v}
        assert_disagree = {k: collections.Counter(v) for k, v in assert_sets.items() if len(set(v)) > 1}
        observe_distinct = {k: len(set(v)) for k, v in observe_sets.items()}
        nruns = len(names)
        qualified = (
            total_runs == RUNS and ok == RUNS and canon_distinct == 1 and not assert_fail and not assert_disagree
        )
        rows.append((label, f"{ok}/{RUNS}", str(raw_distinct), str(canon_distinct), "yes" if qualified else "no",
                     len(present), relaunched))
        detail.append(f"## {label}")
        detail.append(f"runs present: {len(present)}/{nruns}; verdicts: {collections.Counter(v[0] for v in verdicts)}")
        detail.append(f"raw distinct: {raw_distinct}; canonical distinct: {canon_distinct}; runs with launch relaunch: {relaunched}")
        if assert_fail:
            detail.append(f"assertions with FAIL outcomes: {assert_fail}")
        if assert_disagree:
            for k, c in assert_disagree.items():
                detail.append(f"assertion outcome disagreement {k}: {dict(c)}")
        for k, d in sorted(observe_distinct.items()):
            detail.append(f"observe {k}: distinct values across runs = {d}")
        detail.append("")
    print("| config | PASS/20 | raw distinct | canonical distinct | oracle-qualified? | runs present | relaunched |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} |")
    print()
    print("\n".join(detail))


if __name__ == "__main__":
    main()
