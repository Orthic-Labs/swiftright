#!/usr/bin/env python3
"""usage: status.py <interact out dir> : per section and scheme, picture or the host's first render error."""
import sys, os, re
W = sys.argv[1]
secs = "overview activity storage cleanup monitor apps chat permissions accounts appearance notifications general".split()
for i in range(1, 25):
    k = i - 1; s = secs[k // 2]; sch = 'light' if k % 2 == 0 else 'dark'
    try: t = open(f"{W}/host-{i:02d}.stdout.txt", errors='replace').read()
    except OSError: t = ''
    m = re.search(r"HOST_RENDER_ERROR (.*)", t); e = m[1][:170] if m else ''
    ex = re.search(r"HOST_EXCEPTION code=(\w+)", t)
    print(f"{s:14}{sch:6}{'PNG' if os.path.exists(f'{W}/native-{i:02d}-hub.png') else '---'} {e}{' EXC '+ex[1] if ex else ''}")
