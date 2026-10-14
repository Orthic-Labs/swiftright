#!/usr/bin/env python3
"""Build docs/proven-controls.json from the SR1 consolidation sources.

Sources (read-only): factory/pipeline/consolidation/consolidation-table.json,
factory/registry/manifest.json, docs/sr1-status.md, the Witness.swift of each case, and
factory/pipeline/consolidation/results.jsonl (stage id).

  python3 factory/tools/proven-controls/generate.py          # write docs/proven-controls.json
  python3 factory/tools/proven-controls/generate.py --check  # exit 1 if the file drifted

Only the OVERRIDES below are hand-set (status the sources do not yet say); everything else is derived.
Output is deterministic (no clock, sorted keys), so --check is a byte comparison.
Use --check as the CI/pre-commit hook: it needs only python3 and the checkout.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs" / "proven-controls.json"
TABLE = ROOT / "factory/pipeline/consolidation/consolidation-table.json"
RESULTS = ROOT / "factory/pipeline/consolidation/results.jsonl"
MANIFEST = ROOT / "factory/registry/manifest.json"
STATUS = ROOT / "docs/sr1-status.md"

# status-doc block number -> manifest block id (pixel-ties has no manifest block)
NUM2ID = {1: "swiftui.shapes.fill-stroke", 2: "swiftui.image", 3: "swiftui.stack-overlay",
          4: "swiftui.text.bundled-font", 5: "swiftui.custom-layout", 6: "swiftui.scroll-view",
          7: "swiftui.toggle", 8: "swiftui.disabled", 9: "swiftui.padding-frame",
          10: "swiftui.preference-key", 11: "swiftui.button", 12: "swiftui.binding",
          13: "swiftui.textfield", 14: "swiftui.focus-state", 15: "swiftui.ime-marked-text",
          16: "swiftui.list", 17: "swiftui.alert", 18: "swiftui.animation",
          19: "swiftui.opacity-transition", 20: "swiftui.color-scheme"}

# Hand-set status. The status doc still reads "delivered" for 13-15; the TextField text-origin fix
# (docs/sr1-decisions.md decision 12, an Oracle finding) is being rerun, so none is delivered yet.
# Remove an override once docs/sr1-status.md records the rerun verdict.
_REASON_INH = "Inherits the swiftui.textfield fix: its cases drive TextField and are also gated by the text-origin gate; not delivered until blocks 13-15 are rerun."
OVERRIDES = {
    "swiftui.textfield": {"status": "in-progress",
        "statusReason": "NOT-DELIVERED pending the current fix: TextField text-origin/caret repair and text-origin gate "
                        "(docs/sr1-decisions.md decision 12, closing an Oracle finding); blocks 13-15 are being rerun. "
                        "The earlier semantic-only result (120/120) is superseded."},
    "swiftui.focus-state": {"status": "in-progress", "statusReason": _REASON_INH, "inherits": "swiftui.textfield"},
    "swiftui.ime-marked-text": {"status": "in-progress", "statusReason": _REASON_INH, "inherits": "swiftui.textfield"},
}
WIN_KEYS = re.compile(r"Windows|Segoe|Sandbox|hardware|narrower|focus ring|TSF|\bIME\b|UIA|Mac side|Mac's|\bSF\b|scale 2\.5|light only|measured in light", re.I)
NOT_SWIFTUI = set("""Int Int8 Int16 Int32 Int64 UInt Double Float CGFloat CGSize CGPoint CGRect String Bool Array Dictionary Set
Optional Character Void Any AnyObject Self Date Data URL UUID Never Result Error Task DispatchQueue Foundation TimeInterval
View Swift SwiftUI NSColor NSApplication NSView NSWindow NSImage NSHostingView NSScreen NSAppearance NSEvent
NSApp ProcessInfo Thread RunLoop Bundle""".split())


def decode_usr(usr):
    s = usr.split(":", 2)[-1]
    s = s[2:] if s.startswith("s:") else s
    out, i, n = [], 0, len(s)
    while i < n:
        j = i
        while j < n and s[j].isdigit():
            j += 1
        if j > i and j < n and (s[j].isalpha() or s[j] == "_") and j + int(s[i:j]) <= n:
            ln = int(s[i:j]); out.append(s[j:j + ln]); i = j + ln
        else:
            i += 1
    return [x for x in out if x not in ("SwiftUI", "SwiftUICore")]


def manifest_apis(block):
    names = set()
    for u in block["symbols"]:
        t = decode_usr(u)
        if t:
            names.add(t[0] if len(t) == 1 else f"{t[0]}.{t[1]}")
    return sorted(names)


def strip_code(src):
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)


def witness_apis(path):
    src = strip_code(path.read_text(errors="replace"))
    declared = set(re.findall(r"\b(?:struct|class|enum|protocol|func|var|let|case|typealias)\s+([A-Za-z_]\w*)", src))
    types = set(re.findall(r"\b([A-Z]\w*)\s*[({.<]", src))
    mods = set(re.findall(r"\.([a-z]\w*)\s*[({]", src)) | set(re.findall(r"\.([a-z]\w*)\s*$", src, flags=re.M))
    types = {t for t in types if t not in declared and t not in NOT_SWIFTUI and not t.startswith(("Witness", "Mac"))}
    mods = {m for m in mods if m not in declared}
    return types, mods


def witness_files(case):
    d = ROOT / "factory/pipeline" / case
    return sorted(p for p in d.rglob("Witness.swift") if "/runs/" not in str(p)) if d.is_dir() else []


def parse_status():
    text = STATUS.read_text()
    head = re.search(r"^# SR1 status: (\d+) (\w+) (\d{4})", text, re.M)
    months = {m: i for i, m in enumerate("January February March April May June July August September October November December".split(), 1)}
    date = f"{head.group(3)}-{months[head.group(2)]:02d}-{int(head.group(1)):02d}"
    rows = {}
    for line in text.split("\n---\n")[0].splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        m = re.match(r"(\d+|pixel-ties)\b", cells[0])
        if m and len(cells) >= 5:
            key = int(m.group(1)) if m.group(1).isdigit() else "pixel-ties"
            rows[key] = {"verdict": cells[3], "caveats": cells[4]}
    gaps = re.search(r"^Known gaps: (.*)$", text, re.M)
    return date, rows, gaps.group(1).strip() if gaps else ""


def split_caveats(cell):
    parts = [p.strip().rstrip(".") for p in re.split(r";|\. (?=[A-Z])", cell) if p.strip()]
    gen, win = [], []
    for p in parts:
        (win if WIN_KEYS.search(p) else gen).append(p)
    return gen, win


def build():
    table = json.loads(TABLE.read_text())
    manifest = json.loads(MANIFEST.read_text())
    mblocks = {b["id"]: b for b in manifest["blocks"]}
    sdate, rows, gaps = parse_status()
    stages = {}
    for line in RESULTS.read_text().splitlines():
        r = json.loads(line)
        if r.get("done"):
            stages.setdefault(r["case"], set()).add(r["stage"])
    bycase = {}
    for r in table:
        num = r["block"].split()[0]
        bycase.setdefault(int(num) if num.isdigit() else num, []).append(r)
    entries = []
    for num in sorted(bycase, key=lambda k: (isinstance(k, str), k if isinstance(k, int) else 0)):
        cases = bycase[num]
        bid = NUM2ID.get(num, "cross-cutting.pixel-ties")
        row = rows.get(num, {"verdict": "", "caveats": ""})
        gen, win = split_caveats(row["caveats"])
        types, mods = set(), set()
        for c in cases:
            for p in witness_files(c["case"]):
                t, m = witness_apis(p); types |= t; mods |= m
        stg = sorted({s for c in cases for s in stages.get(c["case"], set())})
        rundates = sorted({f"{d[:4]}-{d[4:6]}-{d[6:]}" for d in
                           (re.search(r"/runs/(\d{8})-", c["out"]).group(1) for c in cases if c.get("out"))})
        passed = sum(1 for c in cases if c["exit"] == 0)
        status = "not-delivered" if passed != len(cases) else ("delivered-with-caveats" if gen or win else "delivered")
        e = {"block": bid, "statusDocBlock": num, "status": status,
             "cases": sorted(c["case"] for c in cases), "casesPassingDecidingGate": f"{passed}/{len(cases)}",
             "apis": {"fromManifest": manifest_apis(mblocks[bid]) if bid in mblocks else [],
                      "fromCaseSources": {"types": sorted(types), "modifiersAndMembers": sorted(mods)}},
             "verdict": {"text": row["verdict"],
                         "source": "docs/sr1-status.md table + factory/pipeline/consolidation/consolidation-table.json",
                         "date": sdate, "runDates": rundates},
             "stage": stg[0] if len(stg) == 1 else stg,
             "caveats": gen, "windowsDifferences": win}
        ov = OVERRIDES.get(bid)
        if ov:
            e["statusFromSources"] = e["status"]
            e.update(ov)
            e["caveats"] = [ov["statusReason"]] + e["caveats"]
        entries.append(e)
    return {"generator": "factory/tools/proven-controls/generate.py", "schema": 1,
            "sources": ["factory/pipeline/consolidation/consolidation-table.json", "factory/registry/manifest.json",
                        "docs/sr1-status.md", "factory/pipeline/consolidation/results.jsonl", "Witness.swift of each case"],
            "statusDate": sdate,
            "statusValues": ["delivered", "delivered-with-caveats", "not-delivered", "in-progress"],
            "apisNotCovered": {"hint": "Any SwiftUI API not listed under a block is not proven. See docs/pulse-notch-demand-map.md "
                                       "for the notch's SwiftUI APIs that no delivered block covers.",
                               "see": "docs/pulse-notch-demand-map.md"},
            "knownGapsAll": gaps,
            "blocks": entries}


def main(argv):
    new = json.dumps(build(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if "--check" in argv:
        old = OUT.read_text() if OUT.exists() else ""
        if old != new:
            print("docs/proven-controls.json drifted from its sources; run generate.py", file=sys.stderr)
            return 1
        print("docs/proven-controls.json is current")
        return 0
    OUT.write_text(new)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
