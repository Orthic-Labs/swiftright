#!/usr/bin/env python3
"""Verify frozen real-process Swift16 import evidence without inference."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "swift-stdlib-process-evidence.json"
TARGET = "arm64-apple-macosx27.0"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
HEADER = ROOT / "factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/swift-foundation/swift-foundation-index-evidence.json"
SOURCE_FACTS = ROOT / "factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-v1/swift-stdlib-evidence.json"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_SOURCE = "sha256:ccd1c05df90165f805e7de278ca3f6945f1a1544e9b8b3da0297ebfcc80f3669"
EXPECTED = {
    "Optional": ("enum", "s:4main8OptionalO", "s:Sq"), "Never": ("enum", "s:4main5NeverO", "s:s5NeverO"),
    "Float": ("struct", "s:4main5FloatV", "s:Sf"), "Double": ("struct", "s:4main6DoubleV", "s:Sd"),
    "Int": ("struct", "s:4main3IntV", "s:Si"), "Int8": ("struct", "s:4main4Int8V", "s:s4Int8V"),
    "Int16": ("struct", "s:4main5Int16V", "s:s5Int16V"), "Int32": ("struct", "s:4main5Int32V", "s:s5Int32V"),
    "Int64": ("struct", "s:4main5Int64V", "s:s5Int64V"), "UInt": ("struct", "s:4main4UIntV", "s:Su"),
    "UInt8": ("struct", "s:4main5UInt8V", "s:s5UInt8V"), "UInt16": ("struct", "s:4main6UInt16V", "s:s6UInt16V"),
    "UInt32": ("struct", "s:4main6UInt32V", "s:s6UInt32V"), "UInt64": ("struct", "s:4main6UInt64V", "s:s6UInt64V"),
    "RangeReplaceableCollection": ("protocol", "s:4main26RangeReplaceableCollectionP", "s:Sm"),
    "MutableCollection": ("protocol", "s:4main17MutableCollectionP", "s:SM"),
}

def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()

def path(value: str) -> Path:
    return ROOT / value

def check(condition: bool, message: str) -> None:
    if not condition: raise RuntimeError(message)

def refs(raw: str) -> list[dict]:
    pat = re.compile(r"key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [{"kind": k.strip(), "name": n, "usr": u, "line": int(l), "column": int(c)} for k,n,u,l,c in pat.findall(raw)]

def main() -> None:
    d = json.loads(EVIDENCE.read_text())
    check(d["inputs"]["target"] == TARGET, "target missing or changed")
    check(sha(LINK) == EXPECTED_LINK, "immutable836 changed")
    check(d["inputs"]["immutable836"]["sha256"] == EXPECTED_LINK, "immutable link pin mismatch")
    check(sha(HEADER) == d["inputs"]["headerWitnessEvidence"]["sha256"], "header evidence changed")
    check(sha(SOURCE_FACTS) == d["inputs"]["sourceFactsEvidence"]["sha256"], "source facts changed")
    source_path = Path(d["inputs"]["swiftInterface"]["path"])
    check(sha(source_path) == EXPECTED_SOURCE, "Swift interface changed")
    check(d["inputs"]["swiftInterface"]["sha256"] == EXPECTED_SOURCE, "Swift interface pin mismatch")
    probe = path(d["inputs"]["probe"]["path"])
    request = path(d["requests"]["path"])
    preimage = path(d["requests"]["preimage"]["path"])
    raw = path(d["raw"]["path"])
    check(sha(probe) == d["inputs"]["probe"]["sha256"], "probe changed")
    check(sha(request) == d["requests"]["sha256"] == sha(preimage), "request/preimage mismatch")
    check(request.read_bytes() == preimage.read_bytes(), "request preimage differs")
    check(sha(raw) == d["raw"]["sha256"], "raw SourceKit output changed")
    check(raw.stat().st_size < 100 * 1024 * 1024, "raw output requires chunks")
    for label, process in d["processes"].items():
        check(process["exit"] == 0, f"{label} did not exit 0")
        for stream in ("stdout", "stderr"):
            p = path(process[stream]["path"])
            check(sha(p) == process[stream]["sha256"], f"{label} {stream} changed")
    all_refs = refs(raw.read_text(errors="replace"))
    check(d["counts"]["sourceKitRefEntities"] == len(all_refs), "SourceKit denominator changed")
    check(d["counts"]["exactImportedTargets"] == 16, "import target count changed")
    check(d["counts"]["exactMainHeaderTargets"] == 16, "main target count changed")
    header = json.loads(HEADER.read_text())
    header_records = {r["name"]: r for m in header["modules"] if m["module"] == "Swift" for r in m["targetRecords"]}
    old = json.loads(SOURCE_FACTS.read_text())
    old_targets = {t["target"].split(".", 1)[1]: t for t in old["targets"]}
    check(len(d["targets"]) == 16, "evidence target count changed")
    for t in d["targets"]:
        name = t["target"].split(".", 1)[1]
        kind, main_usr, imported_usr = EXPECTED[name]
        main = t["headerIndexWitness"]["record"]
        imported = t["compiledImportWitness"]["record"]
        check((t["kind"], main["kind"], main["usr"], imported["usr"]) == (kind, kind, main_usr, imported_usr), f"identity changed: {name}")
        check(main == header_records[name], f"header witness mismatch: {name}")
        check(imported["line"] == old_targets[name]["sourceKitReference"]["record"]["line"], f"probe line changed: {name}")
        check(t["conditions"] == old_targets[name]["ownerSource"]["conditions"], f"conditions changed: {name}")
        check(t["headerIndexWitness"]["demangle"]["summary"] == f"main.{name}", f"main demangle changed: {name}")
        check(t["compiledImportWitness"]["demangle"]["summary"] == f"Swift.{name}", f"import demangle changed: {name}")
        check(t["headerIndexWitness"]["evidence"]["rawModule"] == "Swift", f"header module changed: {name}")
    symbols = d["demangleSymbols"]
    check(symbols["count"] == 32 and symbols["mainHeaderCount"] == 16 and symbols["compiledImportCount"] == 16, "demangle denominator changed")
    check(sha(path(symbols["path"])) == symbols["sha256"], "demangle symbol input changed")
    check(d["runnerSource"]["sha256"] == sha(path(d["runnerSource"]["path"])), "runner source changed")
    print(f"swift stdlib process verification: 16 main-header witnesses + 16 compiled import witnesses; {len(all_refs)} raw SourceKit entities; all real process receipts, source conditions, canonical IDs & full demangles pinned; exits0")
if __name__ == "__main__": main()
