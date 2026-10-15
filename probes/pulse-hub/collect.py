#!/usr/bin/env python3
"""usage: collect.py <logs dir> <tag> : unique compiler errors of the four probe modules, as lines `Module File:line:col message`."""
import re, sys, glob, os
d, tag = sys.argv[1], sys.argv[2]
seen = set()
for f in sorted(glob.glob(os.path.join(d, f"{tag}-*.log"))):
    for l in open(f, errors="replace"):
        m = re.match(r"^.*\\pkg\\Sources\\(\w+)\\(.+?):(\d+):(\d+): error: (.*)$", l.rstrip())
        if m and (m[1], m[2], m[3], m[5]) not in seen:
            seen.add((m[1], m[2], m[3], m[5]))
            print(f"{m[1]} {m[2].replace(chr(92), '/')}:{m[3]}:{m[4]} {m[5]}")
