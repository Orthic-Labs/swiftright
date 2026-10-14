#!/usr/bin/env python3
"""SwiftRight porting demand map for the Pulse notch (plan step F12).

Reads the Pulse Mac notch source READ-ONLY, indexes the pinned SDK's SwiftUI interface, parses the SR1
manifest, and writes:
  * a JSON data file (every count, example and classification), and
  * generated tables injected between <!-- generated:NAME --> markers in docs/pulse-notch-demand-map.md.

    python3 factory/tools/demand-map/demand_map.py \
        --pulse /Volumes/D/claude/pulse --json factory/tools/demand-map/pulse-notch-demand-data.json \
        --doc docs/pulse-notch-demand-map.md

Nothing is written under --pulse.  The scan is lexical (comments and strings blanked); precision limits
are listed in the report's "Method and limits" section.
"""
import argparse
import fnmatch
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import coverage            # noqa: E402
import scan_api            # noqa: E402
import scan_services       # noqa: E402
import swiftui_index       # noqa: E402

REPO = HERE.parents[2]


def git(path, *args):
    try:
        return subprocess.check_output(["git", "-C", str(path), *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def expand(root, patterns):
    out = []
    for pat in patterns:
        hits = sorted(str(p.relative_to(root)) for p in root.glob(pat))
        out.extend(hits)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pulse", default="/Volumes/D/claude/pulse")
    ap.add_argument("--json", default=str(HERE / "pulse-notch-demand-data.json"))
    ap.add_argument("--doc", default=str(REPO / "docs/pulse-notch-demand-map.md"))
    ap.add_argument("--no-inject", action="store_true")
    a = ap.parse_args()

    pulse = Path(a.pulse)
    notch = pulse / "mac/Notch"
    ix = swiftui_index.build()
    files, swiftui_files, results, own = scan_api.scan_tree(notch, ix)
    ext_inits = scan_api.extension_inits(files)
    manifest = coverage.load(REPO / "factory/registry/manifest.json")
    notes = json.loads((HERE / "coverage-notes.json").read_text())
    jspec = json.loads((HERE / "journeys.json").read_text())

    # ---- journeys: file -> journeys ----
    group_files = {g: set(expand(notch, pats)) for g, pats in jspec["groups"].items()}
    journeys = []
    file_j = defaultdict(set)
    file_own = defaultdict(set)
    warnings = []
    for j in jspec["journeys"]:
        own_files = set()
        for pat in j["files"]:
            hit = expand(notch, [pat])
            if not hit:
                warnings.append(f'{j["id"]}: no file matches {pat}')
            own_files.update(hit)
        for f in own_files:
            file_own[f].add(j["id"])
        allf = set(own_files)
        for g in j["uses"]:
            allf |= group_files[g]
        for f in allf:
            file_j[f].add(j["id"])
        journeys.append({**j, "own_files": sorted(own_files), "all_files": sorted(allf)})
    unassigned = [f for f in swiftui_files if f not in file_j]

    # ---- witness evidence ----
    wit_paths = coverage.witness_files(REPO / "factory/pipeline", notes["witness_roots"])
    wit_seen = defaultdict(set)         # (kind,name) -> block groups
    wit_forms = defaultdict(set)
    for p in wit_paths:
        rel = p.relative_to(REPO / "factory/pipeline")
        parts = rel.parts
        group = next((x for x in parts if x.startswith("swiftui.")), None) or (parts[1] if len(parts) > 2 else parts[0])
        for k, n, ln, ex in scan_api.scan_file(str(p), p.read_text(errors="replace"), ix, set()):
            wit_seen[(k, n)].add(group)
            if k == "form":
                wit_forms[n].add(ex)

    # ---- aggregate API items ----
    items = {}
    form_items = {}
    for f, res in results.items():
        for kind, name, line, extra in res:
            if kind == "form":
                key = (name, extra)
                it = form_items.setdefault(key, {"count": 0, "files": set(), "example": None})
                it["count"] += 1
                it["files"].add(f)
                it["example"] = it["example"] or f"{f}:{line}"
                continue
            key = (kind, name)
            it = items.setdefault(key, {"kind": kind, "name": name, "count": 0, "files": set(), "example": None,
                                        "extra": set(), "by": Counter()})
            it["count"] += 1
            it["by"][f] += 1
            it["files"].add(f)
            if extra:
                it["extra"].add(extra)
            if it["example"] is None:
                it["example"] = f"{f}:{line}"

    # ---- what the SR0 runtime source implements (public declarations), gated or not ----
    rt_root = REPO / "probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime"
    rt_text = "\n".join(p.read_text(errors="replace") for p in sorted(rt_root.glob("*.swift")))
    rt_types = set(re.findall(r"public (?:final )?(?:struct|class|enum|protocol|typealias|actor) (\w+)", rt_text))
    rt_members = set()          # (context type, member name) declared public in the runtime
    ctx_stack = []              # (indent, name)
    for line in rt_text.splitlines():
        ind = len(line) - len(line.lstrip())
        while ctx_stack and ctx_stack[-1][0] >= ind and line.strip() and not line.strip().startswith(("}", "//")):
            ctx_stack.pop()
        m = re.match(r"\s*(?:public |open )?(?:final )?(?:extension|struct|class|enum|protocol|actor)\s+(\w+)", line)
        if m:
            ctx_stack.append((ind, m.group(1)))
            continue
        if not ctx_stack:
            continue
        f = re.match(r"\s*(?:@\w+(?:\([^)]*\))?\s+)*public (?:static |mutating )*(?:func|var|let) (\w+)", line)
        if f:
            rt_members.add((ctx_stack[-1][1], f.group(1)))
        c = re.match(r"\s*case (\w+(?:\s*,\s*\w+)*)", line)
        if c:
            for nm in re.split(r"\s*,\s*", c.group(1)):
                rt_members.add((ctx_stack[-1][1], nm))
    ungated = "implemented in the SR0 runtime (probes/sr0-s/fresh-runtime), no gated case"
    excl = set(notes["excluded_by_architecture"]["names"])
    cov_types, cov_members = manifest["types"], manifest["members"]

    def wl(groups):
        g = sorted(x.replace("swiftui.", "") for x in groups)
        return ", ".join(g[:3]) + (f" and {len(g) - 3} more" if len(g) > 3 else "")

    def blocks_short(bs):
        return ", ".join(sorted(b.replace("swiftui.", "") for b in bs))

    overrides = notes["partial_overrides"]

    def classify(it):
        kind, name = it["kind"], it["name"]
        ov = overrides.get(f"{kind}:{name}")
        if ov:
            return "partly", ov
        if kind == "combine" or name in excl or ("@" + name) in excl:
            return "excluded", "outside inventory (architecture section 5)"
        if kind == "wrapper":
            if name in cov_types:
                return "delivered", blocks_short(cov_types[name])
            if (kind, name) in wit_seen:
                return "partly", "used in witnesses of " + wl(wit_seen[(kind, name)])
            if name == "Environment":
                return "partly", "EnvironmentValues.colorScheme only (color-scheme); custom EnvironmentKey not covered"
            if name == "NSApplicationDelegateAdaptor":
                return "platform", "Mac app entry (architecture section 5: Windows uses an SDK-owned entry)"
            return "missing", ""
        if kind == "type":
            if name in ("NSHostingView", "NSViewRepresentable"):
                return "platform", "AppKit escape hatch (Mac only)"
            if name in cov_types:
                return "delivered", blocks_short(cov_types[name])
            if (kind, name) in wit_seen:
                return "partly", "exercised in witnesses of " + wl(wit_seen[(kind, name)]) + "; no block of its own"
            return "missing", ""
        if kind == "modifier":
            hits = set()
            for (ctx, mem), bs in cov_members.items():
                if mem == name and ctx in ("View", "DynamicViewContent"):
                    hits |= bs
            if hits:
                return "delivered", blocks_short(hits)
            if (kind, name) in wit_seen:
                return "partly", "exercised in witnesses of " + wl(wit_seen[(kind, name)]) + "; no block of its own"
            return "missing", ""
        if kind == "member-call":
            hits = set()
            for o in {x for e in it["extra"] for x in e.split("/")}:
                hits |= cov_members.get((o, name), set())
            if hits:
                return "delivered", blocks_short(hits)
            if (kind, name) in wit_seen:
                return "partly", "exercised in witnesses of " + wl(wit_seen[(kind, name)])
            return "missing", ""
        if kind == "static":
            ctx, mem = name.split(".", 1)
            bs = cov_members.get((ctx, mem))
            if bs:
                return "delivered", blocks_short(bs)
            if (kind, name) in wit_seen:
                return "partly", "exercised in witnesses"
            return "missing", ""
        if kind == "implicit":
            owners = sorted({o for e in it["extra"] for o in e.split(",")})
            hits = set()
            for o in owners:
                hits |= cov_members.get((o, name), set())
            if hits:
                return "delivered", blocks_short(hits)
            if ("implicit", name) in wit_seen:
                return "partly", "exercised in witnesses of " + wl(wit_seen[("implicit", name)]) + "; no manifest symbol"
            return "missing", ""
        if kind == "env-key":
            bs = cov_members.get(("EnvironmentValues", name))
            if bs:
                return "delivered", blocks_short(bs)
            return "missing", ""
        return "missing", ""

    def classify_all(it):
        status, note = classify(it)
        if status == "missing":
            kind, name = it["kind"], it["name"]
            if kind in ("type", "wrapper") and name in rt_types:
                return "ungated", ungated
            if kind == "modifier" and ("View", name) in rt_members:
                return "ungated", ungated
            if kind in ("member-call", "implicit"):
                for o in {x.split(".")[-1] for e in it["extra"] for x in e.replace("/", ",").split(",")}:
                    if (o, name) in rt_members:
                        return "ungated", ungated
            if kind == "static":
                ctx, mem = name.split(".", 1)
                if (ctx, mem) in rt_members:
                    return "ungated", ungated
        return status, note

    rows = []
    for key, it in sorted(items.items()):
        status, note = classify_all(it)
        jids = sorted({j for f in it["files"] for j in file_j.get(f, ())})
        rows.append({
            "kind": it["kind"], "name": it["name"], "count": it["count"], "files": len(it["files"]),
            "example": it["example"], "owners": sorted(",".join(sorted(it["extra"])).split(",")) if it["extra"] else [],
            "by_file": dict(it["by"]),
            "status": status, "block": note, "journeys": jids,
            "journeys_own": sorted({j for f in it["files"] for j in file_own.get(f, ())}),
        })

    # init-form gaps for delivered types
    form_gaps = []
    for (tname, label), it in sorted(form_items.items()):
        if tname in cov_types and label != "_" and label not in manifest["labels"][tname] \
                and label not in ext_inits.get(tname, set()):
            form_gaps.append({"type": tname, "label": label, "count": it["count"], "files": len(it["files"]),
                              "example": it["example"], "blocks": sorted(cov_types[tname]),
                              "in_witnesses": label in wit_forms.get(tname, set())})

    # ---- missing ranking ----
    missing = [r for r in rows if r["status"] == "missing"]
    missing.sort(key=lambda r: (-len(r["journeys"]), -len(r["journeys_own"]), -r["count"], r["name"]))

    # ---- interop inside SwiftUI files ----
    interop = Counter()
    interop_ex = {}
    import lexer
    for f in swiftui_files:
        code = lexer.strip(files[f])
        for i, line in enumerate(code.splitlines(), 1):
            for m in re.finditer(r"\b((?:NS|CA|CG|CV|UT|SF)[A-Z]\w+)\b", line):
                interop[m.group(1)] += 1
                interop_ex.setdefault(m.group(1), f"{f}:{i}")
    interop_rows = [{"name": n, "count": c, "example": interop_ex[n]} for n, c in interop.most_common()]

    # ---- services ----
    spec, svc = scan_services.scan(notch, HERE / "services.json")
    imports = Counter()
    for f, t in files.items():
        for m in re.finditer(r"^\s*(?:@preconcurrency\s+)?import\s+([\w.]+)", t, re.M):
            imports[m.group(1)] += 1

    # ---- comparison counts per notch group ----
    comp = {}
    cmp_md = (pulse / "docs/comparison/README.md").read_text()
    cur = None
    for line in cmp_md.splitlines():
        h = re.match(r"^## (Notch: [\w-]+)$", line)
        if h:
            cur = h.group(1)
            comp[cur] = Counter()
            continue
        if line.startswith("## "):
            cur = None
        if cur:
            m = re.match(r"^\| .* \| (match|differs|windows-missing|mac-missing) \|", line)
            if m:
                comp[cur][m.group(1)] += 1
    comp_tot = Counter()
    for c in comp.values():
        comp_tot.update(c)

    # per-journey API stats
    jstats = {}
    for j in journeys:
        fs = set(j["all_files"]) & set(swiftui_files)
        names = {(r["kind"], r["name"]) for r in rows if j["id"] in r["journeys"]}
        jstats[j["id"]] = {
            "swiftui_files": len(set(j["own_files"]) & set(swiftui_files)),
            "all_swiftui_files": len(fs),
            "own_swiftui_lines": sum(files[f].count("\n") for f in set(j["own_files"]) & set(swiftui_files)),
            "apis": len(names),
            "missing": sum(1 for r in rows if r["status"] == "missing" and j["id"] in r["journeys"]),
        }

    # ---- slices (cumulative, in dependency order) ----
    slices = []
    seen_missing = set()
    seen_all = set()
    for sl in jspec["slices"]:
        sfiles = set(expand(notch, sl["files"]))
        for pat in sl["files"]:
            if not expand(notch, [pat]):
                warnings.append(f'{sl["id"]}: no file matches {pat}')
        used = []
        for r in rows:
            n = sum(c for f, c in r["by_file"].items() if f in sfiles)
            if n:
                used.append({"kind": r["kind"], "name": r["name"], "status": r["status"], "uses": n,
                             "files": sum(1 for f in r["by_file"] if f in sfiles), "block": r["block"],
                             "owners": r["owners"], "new": (r["kind"], r["name"]) not in seen_all})
        missing_here = [u for u in used if u["status"] == "missing"]
        excl_uses = sum(u["uses"] for u in used if u["status"] == "excluded")
        plat_uses = sum(u["uses"] for u in used if u["status"] == "platform")
        slices.append({"id": sl["id"], "name": sl["name"], "why": sl["why"], "journeys": sl["journeys"],
                       "files": sorted(sfiles), "swiftui_lines": sum(files[f].count("\n") for f in sfiles if f in files),
                       "apis": len(used), "missing": len(missing_here), "excluded_uses": excl_uses, "platform_uses": plat_uses,
                       "new_missing": [u for u in missing_here if (u["kind"], u["name"]) not in seen_missing],
                       "partly": [u for u in used if u["status"] == "partly"],
                       "ungated": [u for u in used if u["status"] == "ungated"],
                       "all_missing": missing_here})
        seen_missing |= {(u["kind"], u["name"]) for u in missing_here}
        seen_all |= {(u["kind"], u["name"]) for u in used}

    # ---- families of missing APIs ----
    fams = []
    for fam in notes["families"]:
        names = set(fam["names"])
        rs = [r for r in rows if (r["name"] in names or r["name"].split(".")[-1] in names) and r["kind"] != "combine"]
        ms = [r for r in rs if r["status"] == "missing"]
        s1 = next(s for s in slices if s["id"] == "S1")
        s1files = set(s1["files"])
        fams.append({"id": fam["id"], "name": fam["name"], "plan": fam["plan"],
                     "apis": len(rs), "missing": len(ms), "ungated": sum(1 for r in rs if r["status"] == "ungated"),
                     "uses": sum(r["count"] for r in rs), "missing_uses": sum(r["count"] for r in ms),
                     "journeys": len({j for r in rs for j in r["journeys"]}),
                     "journeys_own": len({j for r in rs for j in r["journeys_own"]}),
                     "s1_uses": sum(c for r in rs for f, c in r["by_file"].items() if f in s1files),
                     "members": sorted(f"{r['name']}:{r['status']}" for r in rs)})

    # ---- view fixtures (acceptance pictures) ----
    fixtures = {}
    for fname in ("notch-views.json", "notch-views-hover.json"):
        fp = pulse / "qa" / fname
        if fp.exists():
            lst = json.loads(fp.read_text())
            fixtures[fname] = {"total": len(lst), "by_area": dict(Counter(x.get("area", "(hover variant)") for x in lst))}

    meta = {
        "pulse_head": git(pulse, "rev-parse", "HEAD"),
        "pulse_notch_dirty_files": len([l for l in git(pulse, "status", "--porcelain", "--", "mac/Notch").splitlines() if l]),
        "swiftright_head": git(REPO, "rev-parse", "HEAD"),
        "sdk": ix["sdk"],
        "sdk_interfaces": ix["files"],
        "swift_files": len(files),
        "swift_lines": sum(t.count("\n") for t in files.values()),
        "swiftui_files": len(swiftui_files),
        "swiftui_lines": sum(files[f].count("\n") for f in swiftui_files),
        "manifest_id": manifest["id"],
        "manifest_blocks": len(manifest["blocks"]),
        "witness_files": len(wit_paths), "runtime_types": len(rt_types), "runtime_members": len(rt_members),
        "unassigned_swiftui_files": unassigned,
        "warnings": warnings,
    }
    data = {"meta": meta, "journeys": [{k: v for k, v in j.items() if k not in ("all_files",)} for j in journeys],
            "journey_stats": jstats, "api": rows, "init_form_gaps": form_gaps, "missing_ranked": [r["name"] for r in missing],
            "interop": interop_rows, "slices": slices, "fixtures": fixtures, "families": fams, "services": [{**s, **svc[s["id"]]} for s in spec],
            "imports": imports.most_common(), "comparison": {k: dict(v) for k, v in comp.items()},
            "blocks": manifest["blocks"], "block_caveats": notes["block_caveats"]}
    Path(a.json).write_text(json.dumps(data, indent=1, sort_keys=True) + "\n")

    if not a.no_inject:
        import render
        render.inject(Path(a.doc), data)
    print(json.dumps({"meta": meta, "rows": len(rows), "missing": len(missing)}, indent=1))


if __name__ == "__main__":
    main()
