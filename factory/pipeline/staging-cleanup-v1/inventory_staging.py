#!/usr/bin/env python3
"""Read-only inventory of Dell D:\\Claude path dependencies in repository receipts/drivers/plans."""
from __future__ import annotations
import hashlib, json, os, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "factory/pipeline/staging-cleanup-v1"
MAX_BYTES = 2 * 1024 * 1024
SUFFIXES = {".md", ".json", ".jsonl", ".ps1", ".py", ".sh", ".txt", ".toml", ".yaml", ".yml", ".swift", ".swiftin", ".swiftpm"}
PATH_RE = re.compile(r"(?i)(?<![A-Za-z0-9_])D:(?:\\|/)[^\"'`<>\s,;\)\]\}]+")
WORD_RE = re.compile(r"(?i)\\b(active|current|owned|staged|pending|required|read[- ]only|retired|superseded|obsolete|blocked|failed|cleared|deleted|false|historical|preimage|scratch)\\b")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def ownership_hint(root_name: str):
    low = root_name.lower()
    if low == "swiftright":
        return "shared-source-root", "repository references identify shared SwiftRight source root"
    if low.startswith("factory-swiftright-"):
        return "factory-owned-candidate-root", "drivers require factory-swiftright-* owned root"
    if low.startswith("sr0-") or low.startswith("sr0s-"):
        return "sr0-stage-root", "SR0 staging references; status must govern movement"
    if low == ".rightkit-managed":
        return "tooling-managed-root", "tool path is external managed tooling"
    return "unresolved", "no local ownership declaration found"


def classify(contexts):
    text = " ".join(contexts).lower()
    retired = any(x in text for x in ("retired", "superseded", "obsolete", "deleted", "test-path", "false afterwards", "preimage", "explicitly superseded"))
    active = any(x in text for x in ("active", "current", "owned", "staged", "pending", "required", "read-only", "new factory", "fresh owned"))
    if retired and active:
        return "mixed-evidence-review"
    if retired:
        return "retired-candidate"
    if active:
        return "active-reference"
    return "unresolved"


def iter_scan_files():
    # Git-tracked plans/drivers/status receipts keep scan bounded; untracked raw captures are excluded.
    args = ["git", "ls-files", "-z", "--", "factory/HELD.md", "factory/IMPLEMENTATION.md", "factory/native/windows", "factory/pipeline"]
    try:
        output = subprocess.check_output(args, cwd=ROOT)
    except (OSError, subprocess.CalledProcessError):
        return
    for raw in output.split(b"\\0"):
        if raw:
            yield ROOT / raw.decode("utf-8", "strict")


def main():
    # Git grep reads only tracked plans/drivers/status text & avoids raw capture trees.
    args = ["git", "grep", "-n", "-I", "-E", r"D:[\\/][^[:space:]\"'`<>;,)]+", "--", "factory/HELD.md", "factory/IMPLEMENTATION.md", "factory/native/windows", "factory/pipeline"]
    try:
        output = subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as exc:
        output = exc.output or ""
    except OSError:
        output = ""
    refs = []
    source_files = set()
    for record in output.splitlines():
        pieces = record.split(":", 2)
        if len(pieces) != 3 or not pieces[1].isdigit():
            continue
        source, line_no_text, line = pieces
        source_files.add(source)
        line_no = int(line_no_text)
        for match in PATH_RE.finditer(line):
            raw = match.group(0).rstrip(".:")
            norm = raw.replace("/", "\\")
            parts = norm.split("\\")
            tail = parts[2:]
            root_name = tail[0] if tail else ""
            # Paths naming files directly beneath D:\Claude belong to parent root.
            if root_name not in {".rightkit-managed"} and (not root_name or "." in root_name):
                root_name = ""
            refs.append({"source": source, "line": line_no, "raw": raw, "normalized": norm, "root": "D:\\Claude\\" + root_name if root_name else "D:\\Claude", "rootName": root_name, "context": line.strip()[:700]})
    unique = {(ref["source"], ref["line"], ref["normalized"]): ref for ref in refs}
    refs = list(unique.values())
    roots = {}
    for ref in refs:
        entry = roots.setdefault(ref["root"], {"root": ref["root"], "rootName": ref["rootName"], "references": [], "contexts": []})
        entry["references"].append({"source": ref["source"], "line": ref["line"], "path": ref["normalized"]})
        entry["contexts"].append(ref["context"])
    for root in roots.values():
        hint, evidence = ownership_hint(root["rootName"])
        root["ownershipHint"] = hint
        root["ownershipEvidence"] = evidence
        root["classification"] = classify(root["contexts"])
        root["referenceCount"] = len(root["references"])
        root["evidenceContexts"] = root["contexts"][:12]
        del root["contexts"]
    roots_list = sorted(roots.values(), key=lambda x: x["root"].lower())
    active = [x for x in roots_list if x["classification"] == "active-reference"]
    retired = [x for x in roots_list if x["classification"] == "retired-candidate"]
    mixed = [x for x in roots_list if x["classification"] == "mixed-evidence-review"]
    unresolved = [x for x in roots_list if x["classification"] == "unresolved"]
    report = {
        "kind": "factory-dell-staging-cleanup-inventory-v1", "version": 1,
        "scope": "local repository text receipts/drivers/plans only; no Dell connection or mutation",
        "repositoryRoot": str(ROOT),
        "scan": {"method": "git grep -n -I", "paths": ["factory/HELD.md", "factory/IMPLEMENTATION.md", "factory/native/windows", "factory/pipeline"], "filesWithMatches": len(source_files), "matchedLines": len(output.splitlines()), "largeFilesSkipped": 0, "binaryFilesSkipped": 0},
        "absoluteReferenceCount": len(refs), "uniqueRootCount": len(roots_list), "roots": roots_list,
        "summary": {"activeReferenceRoots": len(active), "retiredCandidateRoots": len(retired), "mixedEvidenceRoots": len(mixed), "unresolvedRoots": len(unresolved)},
        "safeConsolidationPolicy": {
            "activeReferenceRoots": "preserve in place until every absolute path receipt, driver & plan is rewritten and rehashed",
            "retiredCandidateRoots": "move only after owner confirms no active process/lock and archive manifest preserves every byte/hash; this inventory performs no move",
            "mixedEvidenceRoots": "hold; reconcile current status against historical receipts before any move",
            "unresolvedRoots": "hold; require explicit owner/status evidence", "delete": "forbidden in this packet",
        },
    }
    (OUT / "inventory.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    manifest = {"kind": "factory-dell-staging-cleanup-v1-stage", "files": []}
    for path in sorted(p for p in OUT.rglob("*") if p.is_file() and p.name != "stage-manifest.json" and "__pycache__" not in p.parts):
        manifest["files"].append({"path": path.relative_to(OUT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    manifest["fileCount"] = len(manifest["files"])
    manifest["totalBytes"] = sum(x["bytes"] for x in manifest["files"])
    (OUT / "stage-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "ok", "references": len(refs), "roots": len(roots_list), "active": len(active), "retiredCandidates": len(retired), "mixed": len(mixed), "unresolved": len(unresolved)}, indent=2))

if __name__ == "__main__":
    main()
