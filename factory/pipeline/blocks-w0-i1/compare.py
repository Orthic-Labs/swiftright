#!/usr/bin/env python3
"""I1 gate: Windows decode dumps against the Mac ImageIO oracle.
usage: compare.py WINDOWS_DIR ORACLE_DIR [--tolerances tolerances.json] [--json OUT.json] [--measure]
WINDOWS_DIR holds run-01 ... run-NN (each results.json + run.bin from ImageDump; run-01 also old-results.json + old-run.bin = the block 35 Swift decoder).
Determinism (N): every run's run.bin must equal run-01's byte for byte and every result must equal run-01's.
Accuracy (run-01 against the oracle), per case class:
  lossless / ico / orientation (no tolClass): byte-exact, with two stated exceptions that are not decode differences:
      - pixels with alpha 0: the RGB under them is ignored (the paint contract drops it: docs/foundations-images-fonts.md 1.2);
      - cases whose oracle is itself lossy (ImageIO returned premultiplied pixels, "alphaLossy"): opaque pixels exact, partly transparent pixels compared premultiplied, within 1.
  tolClass (jpeg-420, jpeg-444, ..., p3, thumbnail): max and mean absolute difference per channel under tolerances.json (maxPerChannel, meanPerChannel); --measure only prints the numbers.
  refOverride "old": the reference is the block 35 Swift decoder's buffer (the oracle is wrong for that case, see refReason).
  negative: must throw.  ico-policy: decodes."""
import json, sys, zlib
from pathlib import Path


def oracle_bytes(d, cid, index):
    p = d / f"{cid}.rgba"
    if p.exists(): return p.read_bytes()
    z = d / f"{cid}.rgba.z"
    if z.exists(): return zlib.decompress(z.read_bytes())
    same = index.get(cid, {}).get("sameAs")
    return oracle_bytes(d, same, index) if same else None


def diff(got, exp, premul_lossy):
    """-> (max per channel [r,g,b,a], mean per channel, differing pixels, compared pixels)"""
    n = len(got) // 4; mx = [0] * 4; sm = [0] * 4; bad = 0
    for i in range(0, len(got), 4):
        ga, ea = got[i + 3], exp[i + 3]
        d = [0, 0, 0, abs(ga - ea)]
        if ga != 0 or ea != 0:
            for c in range(3):
                if premul_lossy and 0 < ea < 255 and 0 < ga < 255:
                    d[c] = abs(round(got[i + c] * ga / 255) - round(exp[i + c] * ea / 255))
                    if d[c] <= 1 and premul_lossy == "exact1": d[c] = 0 if d[c] == 0 else d[c]
                elif ga != 0 and ea != 0 or True:
                    d[c] = abs(got[i + c] - exp[i + c]) if not (ga == 0 or ea == 0) else (0 if (ga == 0 and ea == 0) else abs(round(got[i + c] * ga / 255) - round(exp[i + c] * ea / 255)))
        if any(d):
            bad += 1
            for c in range(4):
                sm[c] += d[c]
                if d[c] > mx[c]: mx[c] = d[c]
    return mx, [s / n for s in sm], bad, n


def main():
    a = sys.argv[1:]
    win, orc = Path(a[0]), Path(a[1])
    tol = json.loads(Path(a[a.index("--tolerances") + 1]).read_text()) if "--tolerances" in a else {}
    measure = "--measure" in a
    runs = sorted(p for p in win.iterdir() if p.is_dir() and p.name.startswith("run-"))
    base = runs[0]
    res = json.loads((base / "results.json").read_text())["cases"]; binf = (base / "run.bin").read_bytes()
    old_res = {c["id"]: c for c in json.loads((base / "old-results.json").read_text())["cases"]} if (base / "old-results.json").exists() else {}
    old_bin = (base / "old-run.bin").read_bytes() if (base / "old-run.bin").exists() else b""
    manifest = {c["id"]: c for c in json.loads((Path(__file__).resolve().parent / "corpus/manifest.json").read_text())["cases"]}
    index = {c["id"]: c for c in json.loads((orc / "oracle.json").read_text())["cases"]}
    # N-run determinism
    det = {"runs": len(runs), "identicalBuffers": True, "identicalResults": True, "mismatches": []}
    for r in runs[1:]:
        if (r / "run.bin").read_bytes() != binf: det["identicalBuffers"] = False; det["mismatches"].append(r.name + ":run.bin")
        rr = json.loads((r / "results.json").read_text())["cases"]
        if [(c["id"], c["result"], c.get("w"), c.get("h"), c.get("contentID"), c.get("error")) for c in rr] != [(c["id"], c["result"], c.get("w"), c.get("h"), c.get("contentID"), c.get("error")) for c in res]:
            det["identicalResults"] = False; det["mismatches"].append(r.name + ":results")
    rows = []; failed = 0
    for r in res:
        cid, kind = r["id"], r["kind"]; o = index.get(cid, {}); m = manifest[cid]
        cls = m.get("tolClass") or ("thumbnail" if o.get("thumbnailOracle") else None)
        row = dict(id=cid, kind=kind, cls=cls or "exact")
        if kind == "negative":
            row["pass"] = r["result"] == "threw"; row["error"] = r.get("error", "")[:100]
            row["macImageIO"] = "returns an image (partial)" if o.get("imageIOReturnsImage") else "returns nothing"; row["wicCodecAlone"] = r.get("codecOnly")
        elif kind == "ico-policy":
            row["pass"] = r["result"] == "ok"; row["note"] = "decoded, no oracle (tie rule is a unit test)"
        elif r["result"] != "ok":
            row["pass"] = False; row["error"] = r.get("error", "")[:140]
        else:
            got = binf[r["offset"]:r["offset"] + r["length"]]
            exp = None; refname = "Mac ImageIO"
            if m.get("refOverride") == "old":
                refname = "block 35 Swift decoder"
                oc = old_res.get(cid)
                if oc and oc.get("result") == "ok": exp = old_bin[oc["offset"]:oc["offset"] + oc["length"]]; ew, eh = oc["w"], oc["h"]
            elif "w" in o:
                exp = oracle_bytes(orc, cid, index); ew, eh = o["w"], o["h"]
            if exp is None and m.get("equalsCase"):
                other = next(x for x in res if x["id"] == m["equalsCase"])
                exp = binf[other["offset"]:other["offset"] + other["length"]]; ew, eh = other["w"], other["h"]; refname = "Windows decode of " + m["equalsCase"] + " (oracle: Mac, " + m["equalsReason"][:40] + ")"
            if exp is None:
                row["pass"] = None; row["note"] = "no reference: " + str(o.get("oracle")); row["decodedOnWindows"] = f"{r['w']}x{r['h']}"
            elif (r["w"], r["h"]) != (ew, eh):
                row["pass"] = False; row["note"] = f"dims {r['w']}x{r['h']} vs {refname} {ew}x{eh}"
            else:
                lossy = bool(o.get("alphaLossy")) and refname == "Mac ImageIO"
                mx, mean, bad, n = diff(got, exp, "lossy" if lossy else None)
                row.update(ref=refname, max=mx, mean=[round(v, 4) for v in mean], badPixels=bad, pixels=n, oracleAlphaLossy=lossy)
                t = tol.get(cls) if cls else None
                if cls and measure: row["pass"] = None
                elif cls and t: row["pass"] = max(mx) <= t["maxPerChannel"] and max(mean) <= t["meanPerChannel"]
                elif cls: row["pass"] = False; row["note"] = f"no tolerance named for class {cls}"
                else: row["pass"] = (max(mx) <= (1 if lossy else 0))
        if row["pass"] is False: failed += 1
        rows.append(row)
    summary = dict(determinism=det, failed=failed, cases=len(rows))
    if "--json" in a: Path(a[a.index("--json") + 1]).write_text(json.dumps(dict(summary=summary, rows=rows), indent=1))
    for row in rows:
        flag = {True: "PASS", False: "FAIL", None: "NOGATE"}[row["pass"]]
        print(f"{flag:7} {row['id']:30} {row['cls']:12}", {k: v for k, v in row.items() if k in ("max", "mean", "badPixels", "note", "error", "ref")})
    print(json.dumps(summary))


main()
