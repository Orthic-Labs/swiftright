#!/usr/bin/env python3
"""Summarize SR1 repeat runs in out/sr1/: verdicts, launch attempts, raw and canonical hash agreement,
and the distinct recorded outcome values per observe phase across runs.

Usage: sr1-summary.py [out-dir]   (default out/sr1). Reads only; writes nothing.
Hashes come from normalize-hash.py (imported by path; its raw and --canonical digests).
"""
import collections
import hashlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("normalize_hash", os.path.join(HERE, "normalize-hash.py"))
nh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nh)

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(HERE), "out", "sr1")
configs = collections.defaultdict(list)
for name in sorted(os.listdir(out_dir)):
    m = re.fullmatch(r"(G\d)-run(\d+)\.jsonl", name)
    if m:
        configs[m.group(1)].append(int(m.group(2)))

def verdict(path):
    text = open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else ""
    m = re.search(r"SELFTEST \S+: (PASS|FAIL) \((\d+)/(\d+)\)", text)
    return (m.group(1), m.group(2), m.group(3)) if m else ("NONE", "0", "0")

print("| Config | Verdict x N | Raw hash distinct | Canonical distinct | Relaunched | Oracle-qualified |")
print("|---|---|---|---|---|---|")
per_config_outcomes = {}
for cfg in sorted(configs):
    runs = sorted(configs[cfg])
    verdicts = collections.Counter()
    raw, canon, relaunch = set(), set(), 0
    outcomes = collections.defaultdict(collections.Counter)
    for n in runs:
        base = os.path.join(out_dir, f"{cfg}-run{n}")
        launch_text = open(base + ".launch.txt").read() if os.path.exists(base + ".launch.txt") else ""
        if "RC=" not in launch_text:
            continue  # run still in progress
        v, _, _ = verdict(base + ".stdout")
        verdicts[v] += 1
        launch = open(base + ".launch.txt").read() if os.path.exists(base + ".launch.txt") else ""
        if re.search(r"attempt [2-9]", launch):
            relaunch += 1
        if os.path.exists(base + ".jsonl"):
            raw.add(hashlib.sha256("\n".join(nh.normalized_lines(base + ".jsonl")).encode("utf-8")).hexdigest())
            canon.add(nh.canonical_digest(base + ".jsonl"))
            events = [json.loads(l) for l in open(base + ".jsonl", encoding="utf-8") if l.strip()]
            for e in events:
                if e.get("kind") == "observe":
                    payload = {k: v for k, v in e["payload"].items() if k not in ("phase",)}
                    key = f'{e["node_id"]}|{e["payload"].get("phase")}'
                    outcomes[key][json.dumps(payload, sort_keys=True)] += 1
    complete = sum(verdicts.values())
    passed = verdicts.get("PASS", 0) == complete == 20
    qualified = "yes" if passed and len(canon) == 1 else "no"
    label_v = " ".join(f"{k}={c}" for k, c in sorted(verdicts.items()))
    print(f"| {cfg} | {label_v} (n={complete}) | {len(raw)} | {len(canon)} | {relaunch} | {qualified} |")
    per_config_outcomes[cfg] = outcomes

for cfg in sorted(per_config_outcomes):
    print(f"\n## {cfg}: recorded outcomes (observe phase: distinct payload values across runs)")
    for key, counter in per_config_outcomes[cfg].items():
        distinct = len(counter)
        node, phase = key.split("|", 1)
        print(f"- {node} / {phase}: {distinct} distinct across {sum(counter.values())} observations")
        if distinct > 0:
            for payload, count in counter.most_common(3):
                print(f"    x{count}: {payload[:240]}")
