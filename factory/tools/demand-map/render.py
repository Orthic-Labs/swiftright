"""Render generated tables and inject them between <!-- generated:NAME --> markers."""
import re
from collections import Counter, defaultdict
from pathlib import Path

NOTCH = "mac/Notch/"


def esc(s):
    return str(s).replace("|", "\\|")


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join("---" for _ in headers) + "|"]
    for r in rows:
        out.append("| " + " | ".join(esc(c) for c in r) + " |")
    return "\n".join(out)


def ex(r):
    return f"`{NOTCH}{r['example']}`" if r.get("example") else ""


def jlist(js):
    return f"{len(js)}"


def meta(d):
    m = d["meta"]
    rows = [
        ("Pulse checkout (read-only)", f"`/Volumes/D/claude/pulse` at `{m['pulse_head'][:9]}`; uncommitted changes under `mac/Notch`: {m['pulse_notch_dirty_files']}"),
        ("SwiftRight checkout", f"`{m['swiftright_head'][:9]}` (manifest `{m['manifest_id']}`, {m['manifest_blocks']} blocks)"),
        ("Swift files / lines scanned", f"{m['swift_files']} files, {m['swift_lines']:,} lines under `mac/Notch` (all targets: notch, Helper, Elevate, FinderExtension, Shared)"),
        ("Files that `import SwiftUI`", f"{m['swiftui_files']} files, {m['swiftui_lines']:,} lines"),
        ("SwiftUI index", f"public declarations of `SwiftUI` and `SwiftUICore` in the pinned SDK (`{m['sdk'].split('Developer/')[-1]}`, `arm64e-apple-macos.swiftinterface`)"),
        ("Witness sources read for coverage", f"{m['witness_files']} `Witness.swift` files of delivered cases under `factory/pipeline`"),
    ]
    return table(["Input", "Value"], rows)


def comparison(d):
    rows = []
    tot = Counter()
    for g, c in sorted(d["comparison"].items()):
        rows.append((g.replace("Notch: ", ""), c.get("match", 0), c.get("differs", 0), c.get("windows-missing", 0), c.get("mac-missing", 0)))
        tot.update(c)
    rows.append(("**all notch groups**", tot["match"], tot["differs"], tot["windows-missing"], tot["mac-missing"]))
    return table(["Notch group (docs/comparison/README.md)", "match", "differs", "windows-missing", "mac-missing"], rows)


def journeys(d):
    rows = []
    st = d["journey_stats"]
    for j in d["journeys"]:
        s = st[j["id"]]
        files = ", ".join(f"`{f.replace('Sources/', '')}`" for f in j["own_files"])
        rows.append((j["id"], f"**{j['name']}**", j["summary"], files,
                     f"{s['swiftui_files']} own, {s['all_swiftui_files']} with shared", f"{s['apis']}", f"{s['missing']}"))
    return table(["ID", "Journey", "What the user does", "Source files (under `mac/Notch`)", "SwiftUI files", "APIs", "Missing APIs"], rows)


def windows_status(d):
    rows = []
    for j in d["journeys"]:
        label = {"has": "has", "lacks": "lacks", "differs": "differs"}[j["windows"]]
        wf = ", ".join(f"`{f.replace('windows/src/', '')}`" for f in j["windows_files"]) or "none"
        rows.append((j["id"], j["name"], label, j["windows_note"], wf))
    return table(["ID", "Journey", "Windows notch", "Evidence (Pulse docs)", "Windows files (`windows/src`)"], rows)


ST = ("delivered", "partly", "ungated", "missing", "excluded", "platform")


def summary(d):
    c = Counter((r["kind"], r["status"]) for r in d["api"])
    kinds = [("type", "Types"), ("modifier", "View modifiers"), ("member-call", "Builder and receiver calls (Path, GraphicsContext, Shape, Image, Gesture ...)"),
             ("static", "Explicit static members (`Type.member`)"), ("implicit", "Implicit members (`.leading`, `.semibold` ...)"),
             ("wrapper", "Property wrappers"), ("env-key", "Environment keys"), ("combine", "Combine / ObservableObject pieces")]
    rows = []
    tot = Counter()
    for k, label in kinds:
        row = [label] + [c[(k, s)] for s in ST]
        n = sum(row[1:])
        rows.append(row + [n])
        for i, s in enumerate(ST):
            tot[s] += row[1 + i]
    rows.append(["**total distinct APIs**"] + [f"**{tot[s]}**" for s in ST] + [f"**{sum(tot.values())}**"])
    return table(["Kind", "Delivered block", "Partly covered", "Runtime only, ungated", "Missing", "Excluded by architecture", "AppKit escape", "Distinct"], rows)


def api_table(d, kinds, limit=None, status_filter=None):
    rows = [r for r in d["api"] if r["kind"] in kinds and (not status_filter or r["status"] in status_filter)]
    rows.sort(key=lambda r: (-r["count"], r["name"]))
    out = []
    for r in rows[:limit]:
        name = f"`{r['name']}`"
        if r["kind"] == "implicit" and r["owners"]:
            name += f" ({'/'.join(r['owners'][:3])})"
        if r["kind"] == "member-call" and r["owners"]:
            name += f" ({r['owners'][0]})"
        out.append((name, r["count"], r["files"], f"{len(r['journeys'])} / {len(r['journeys_own'])}", r["status"], r["block"], ex(r)))
    return table(["API", "Uses", "Files", "Journeys (all / own files)", "Status", "Block or note", "First example"], out)


def missing(d, top=40):
    rows = [r for r in d["api"] if r["status"] == "missing"]
    rows.sort(key=lambda r: (-len(r["journeys"]), -len(r["journeys_own"]), -r["count"], r["name"]))
    out = []
    for i, r in enumerate(rows[:top], 1):
        name = f"`{r['name']}`"
        if r["kind"] in ("implicit", "member-call") and r["owners"]:
            name += f" ({'/'.join(r['owners'][:2])})"
        own = " ".join(j.replace("J", "") for j in r["journeys_own"]) or "none (shared surface only)"
        out.append((i, name, r["kind"], len(r["journeys"]), len(r["journeys_own"]), r["count"], r["files"], own, ex(r)))
    return table(["#", "Missing API", "Kind", "Journeys (with shared surface)", "Journeys (own files)", "Uses", "Files", "Own-file journeys (J-number)", "First example"], out)


def form_gaps(d):
    out = []
    for g in d["init_form_gaps"]:
        out.append((f"`{g['type']}({g['label']}:)`", g["count"], g["files"], ", ".join(b.replace("swiftui.", "") for b in g["blocks"]), "yes" if g["in_witnesses"] else "no", f"`{NOTCH}{g['example']}`"))
    return table(["Initializer form", "Uses", "Files", "Block that covers the type", "Seen in a witness", "First example"], out)


GEOMETRY = ("CGFloat", "CGPoint", "CGRect", "CGSize", "CGVector")


def interop(d):
    geo = [x for x in d["interop"] if x["name"] in GEOMETRY]
    out = [(f"`{r['name']}`", r["count"], f"`{NOTCH}{r['example']}`") for r in d["interop"] if r["name"] not in GEOMETRY][:30]
    out.append(("geometry value types (" + ", ".join(f"`{x['name']}` {x['count']}" for x in geo) + ")", sum(x["count"] for x in geo),
                "portable: delivered blocks already use `CoreFoundation.CGFloat` and `CGSize` (factory/registry/manifest.json)"))
    return table(["AppKit / Core Animation / Core Graphics name inside SwiftUI files", "Uses", "First example"], out)


def blocks(d):
    api = d["api"]
    per = defaultdict(int)
    for r in api:
        if r["status"] == "delivered":
            for b in r["block"].split(", "):
                per[b] += 1
    out = []
    for b in d["blocks"]:
        short = b["id"].replace("swiftui.", "")
        out.append((f"`{b['id']}`", b["symbols"], per.get(short, 0), d["block_caveats"].get(b["id"], "")))
    return table(["Block (`factory/registry/manifest.json`)", "Manifest symbols", "Notch APIs it covers", "Limits to read before claiming coverage"], out)


def services(d):
    out = []
    for s in d["services"]:
        ex_ = ", ".join(f"`{NOTCH}{f}:{l}`" for f, l in s["examples"][:2]) or "none found"
        out.append((s["name"], f"{s['hits']}", f"{len(s['files'])}", ex_, s["windows"], s["rightkit"], s["sr2"]))
    return table(["Mac service", "Hits", "Files", "Examples", "Windows notch today", "RightKit owner (`rightkit owns`)", "SwiftRight adapter (SR2)"], out)


def imports(d):
    rows = [(f"`import {n}`", c) for n, c in d["imports"][:22]]
    return table(["Module", "Files"], rows)


def fixtures(d):
    rows = []
    for fname, f in d["fixtures"].items():
        for area, n in sorted(f["by_area"].items(), key=lambda x: (-x[1], x[0])):
            rows.append((f"`qa/{fname}`", area, n))
        rows.append((f"`qa/{fname}`", "**total**", f"**{f['total']}**"))
    return table(["File", "Area", "Entries"], rows)


def slice_summary(d):
    rows = []
    for s in d["slices"]:
        rows.append((s["id"], s["name"], ", ".join(s["journeys"]), len(s["files"]), f"{s['swiftui_lines']:,}", s["apis"],
                     s["missing"], len(s["new_missing"]), len(s["partly"]), s["excluded_uses"], s["platform_uses"]))
    return table(["Slice", "Contents", "Journeys", "SwiftUI files", "Lines", "APIs used", "Missing (all)", "Missing, new in this slice", "Partly covered", "Combine uses to rewrite", "AppKit escape uses"], rows)


def slice_gaps(d, sid="S1"):
    s = next(x for x in d["slices"] if x["id"] == sid)
    rows = sorted(s["all_missing"], key=lambda u: (-u["uses"], u["name"]))
    out = []
    for u in rows:
        nm = f"`{u['name']}`"
        if u["owners"]:
            nm += f" ({'/'.join(u['owners'][:2])})"
        out.append((nm, u["kind"], u["uses"], u["files"]))
    return table(["Missing API used by " + sid, "Kind", "Uses in slice", "Files in slice"], out)


def slice_ungated_s1(d):
    s = next(x for x in d["slices"] if x["id"] == "S1")
    out = []
    for u in sorted(s["ungated"] + s["partly"], key=lambda u: (-u["uses"], u["name"])):
        nm = f"`{u['name']}`"
        if u["owners"]:
            nm += f" ({'/'.join(u['owners'][:2])})"
        out.append((nm, u["kind"], u["uses"], u["files"], u["status"], u["block"]))
    return table(["API used by S1", "Kind", "Uses in slice", "Files in slice", "Status", "Evidence"], out)


def slice_gaps_s1(d):
    return slice_gaps(d, "S1")


def slice_new(d):
    out = []
    for s in d["slices"]:
        names = sorted(s["new_missing"], key=lambda u: (-u["uses"], u["name"]))
        txt = ", ".join(f"`{u['name']}`" + (f" ({u['uses']})" if u["uses"] > 1 else "") for u in names[:40])
        if len(names) > 40:
            txt += f", and {len(names) - 40} more"
        out.append((s["id"], len(names), txt or "none"))
    return table(["Slice", "New missing APIs", "Names (uses in the slice)"], out)


def families(d):
    out = []
    for f in d["families"]:
        out.append((f["id"], f["name"], f["apis"], f["missing"], f["ungated"], f["uses"], f["s1_uses"], f"{f['journeys']} / {f['journeys_own']}", f["plan"]))
    return table(["Family", "What it is", "APIs the notch uses", "Missing", "Runtime only", "Uses", "Uses in S1 files", "Journeys (all / own)", "Where the SR1 plan stands"], out)


SECTIONS = {
    "slice-ungated-s1": slice_ungated_s1,
    "families": families,
    "view-fixtures": fixtures, "slice-summary": slice_summary, "slice-gaps-s1": slice_gaps_s1, "slice-new": slice_new,
    "scan-meta": meta, "comparison-counts": comparison, "journey-table": journeys, "journey-windows": windows_status,
    "api-summary": summary, "missing-ranked": missing, "form-gaps": form_gaps, "interop": interop,
    "block-table": blocks, "services-table": services, "imports": imports,
    "api-types": lambda d: api_table(d, {"type"}),
    "api-modifiers": lambda d: api_table(d, {"modifier"}),
    "api-members": lambda d: api_table(d, {"member-call", "static"}),
    "api-implicit": lambda d: api_table(d, {"implicit"}),
    "api-wrappers": lambda d: api_table(d, {"wrapper", "env-key", "combine"}),
}


def inject(doc, data):
    text = doc.read_text()
    for name, fn in SECTIONS.items():
        rx = re.compile(rf"(<!-- generated:{name} -->)\n.*?\n?(<!-- /generated:{name} -->)", re.S)
        if not rx.search(text):
            continue
        text = rx.sub(lambda m: m.group(1) + "\n" + fn(data) + "\n" + m.group(2), text)
    doc.write_text(text)
