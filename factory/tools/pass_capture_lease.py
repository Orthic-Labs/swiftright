#!/usr/bin/env python3
"""Make the factory's Windows capture hosts honour --factory-capture-lease-seconds (the lease the interact and capture jobs request).

A host whose main.swift compares its own lifetime with a compiled constant (`time - (started ?? time) > 10_000_000_000`) ignores the flag, so the
window closes about 10 s after its first tick whatever the job asks for (CI 38865487951, ime-composing-v1 and imet-badregion-v1 runs 1-2). The hosts
that already parse the flag keep their exact snippet; this script gives the other hosts the same snippet, copied verbatim:

    static let leaseNS: UInt64 = {
        for a in CommandLine.arguments where a.hasPrefix("--factory-capture-lease-seconds=") { ... return n * 1_000_000_000 } }
        return 10_000_000_000
    }()

and replaces the compare with `> Self.leaseNS`. The block goes in right after `    var windowClosed = false`, the same anchor blocks-17-20/new-case.py uses.

Applies to the host templates (`CaptureHost.template.swift`) and to the hosts already stamped from them (`<case>/package/Sources/FactoryProbe/main.swift`)
under factory/pipeline/blocks-*. Idempotent: a file that already parses the flag is skipped. A file where an anchor does not match exactly once is
reported and left alone.

  python3 factory/tools/pass_capture_lease.py            # apply
  python3 factory/tools/pass_capture_lease.py --check    # report only; exit 1 if any host under blocks-* still has a fixed lease

Exclusion (deliberate, as in pass_render_scale.py): archived copies are not touched. Out of scope: factory/native/windows/*,
factory/pipeline/pilot-*, factory/pipeline/sr0-display-selfjob*, and every path under a runs/ directory (frozen evidence). Only blocks-* is scanned.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARK = "leaseNS"
ANCHOR = "    var windowClosed = false\n"
PARSE_BLOCK = (
    "    static let leaseNS: UInt64 = {\n"
    '        for a in CommandLine.arguments where a.hasPrefix("--factory-capture-lease-seconds=") { if let n = UInt64(a.dropFirst("--factory-capture-lease-seconds=".count)), n > 0 { return n * 1_000_000_000 } }\n'
    "        return 10_000_000_000\n"
    "    }()\n"
)
FIXED_OLD = "if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }"
FIXED_NEW = "if time - (started ?? time) > Self.leaseNS { bridge.requestQuit() }"
# A lifetime compare: `time - <started-expression> > <rhs>`, where the started expression is `started`, `started ?? time`, `started!`, `startedAt`
# and so on, with any spacing and optional parentheses. It is fixed unless the right-hand side is the parsed lease. `>=` is a script timing
# guard, not a lifetime, and never matches. Not caught: a compare through an intermediate variable (`let e = time - started` then `e > N`),
# or a compare that names the clock something other than `time`. The 310 stamped hosts use the `time - (started ?? time)` form.
FIXED_COMPARE = re.compile(r"\btime\s*-\s*\(?\s*started\w*[^>;{}]*?>(?!=)\s*(?P<rhs>[^\s{};)]+)")


def is_fixed_compare(line):
    m = FIXED_COMPARE.search(line)
    return m is not None and m.group("rhs") != "Self.leaseNS"


def targets():
    for p in sorted((ROOT / "factory/pipeline").glob("blocks-*/**/CaptureHost.template.swift")):
        if "/runs/" not in p.as_posix():
            yield p
    for p in sorted((ROOT / "factory/pipeline").glob("blocks-*/**/package/Sources/FactoryProbe/main.swift")):
        if "/runs/" not in p.as_posix():
            yield p


def fixed_offenders(root=ROOT):
    """Return [(repo-relative path, line)] for each lifetime compare under factory/pipeline/blocks-* that does not use the parsed lease."""
    found = []
    for p in sorted((root / "factory/pipeline").glob("blocks-*/**/*.swift")):
        if not p.is_file() or "/runs/" in p.as_posix():
            continue
        for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if is_fixed_compare(line):
                found.append((p.relative_to(root).as_posix(), n))
    return found


def main():
    check = "--check" in sys.argv
    done = skipped = bad = 0
    for p in targets():
        s = p.read_text()
        if FIXED_OLD not in s:
            if MARK in s:
                skipped += 1
            continue   # no fixed compare: already parsing, or not a Windows capture host
        if s.count(FIXED_OLD) != 1 or s.count(ANCHOR) != 1 or MARK in s:
            bad += 1
            print("NOT APPLIED (an anchor does not match exactly once):", p.relative_to(ROOT))
            continue
        new = s.replace(ANCHOR, ANCHOR + PARSE_BLOCK).replace(FIXED_OLD, FIXED_NEW)
        if not check:
            p.write_text(new)
        done += 1
    print(f"{'would change' if check else 'changed'} {done}, already parsing {skipped}, not applied {bad}")
    offenders = fixed_offenders()
    for rel, line in offenders:
        print(f"FIXED LEASE: {rel}:{line}")
    print(f"lifetime compares not using the parsed lease under blocks-*: {len(offenders)}")
    return 1 if (bad or (check and (done or offenders))) else 0


if __name__ == "__main__":
    sys.exit(main())
