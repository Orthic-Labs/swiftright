#!/usr/bin/env python3
"""Assemble tuple12 only from byte-bound, repository-local receipts."""
import argparse, hashlib, json, re
from pathlib import Path

MEMBERS = ("windows_renderer", "windows_fixture_exe", "windows_smoke_exe", "old_msix", "new_msix", "old_dmg", "new_dmg")
HEX = re.compile(r"^[0-9a-fA-F]{64}$")
REPO = Path(__file__).resolve().parents[1]

def fail(message):
    raise SystemExit(f"error: {message}")

def safe_file(value):
    raw = Path(value.strip()).expanduser()
    if not raw.is_absolute(): raw = Path.cwd() / raw
    if raw.is_symlink(): fail(f"source symlink refused: {raw}")
    try: path = raw.resolve(strict=True)
    except FileNotFoundError: fail(f"source missing: {raw}")
    if not path.is_file() or path.is_symlink(): fail(f"source must be regular file: {raw}")
    try: path.relative_to(REPO)
    except ValueError: fail(f"source outside repository: {path}")
    return path

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""): h.update(block)
    return h.hexdigest()

def bound_artifact(receipt):
    """Return (artifact path, artifact digest); reject hash-only receipts."""
    if receipt.suffix.lower() in {".exe", ".dll", ".msix", ".dmg", ".app"}: return receipt, digest(receipt)
    try: obj = json.loads(receipt.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc: fail(f"source must be binary or sealed JSON receipt: {receipt} ({exc})")
    if obj.get("sealed") is not True or obj.get("receipt_type") not in {"binary", "run"}: fail(f"receipt is not sealed binary/run receipt: {receipt}")
    artifact_value, artifact_hash = obj.get("artifact_path"), str(obj.get("artifact_sha256", "")).lower()
    if not isinstance(artifact_value, str) or not HEX.fullmatch(artifact_hash): fail(f"receipt lacks artifact_path/artifact_sha256 join: {receipt}")
    artifact = safe_file(artifact_value); actual = digest(artifact)
    if actual != artifact_hash: fail(f"receipt artifact hash mismatch: {artifact} expected={artifact_hash} actual={actual}")
    return artifact, actual

def pair(value, label):
    if "=" not in value: fail(f"{label} must be NAME=VALUE")
    name, item = value.split("=", 1)
    if name not in MEMBERS or not item.strip(): fail(f"unknown member or empty {label}: {value}")
    return name, item.strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidate", type=Path, default=Path(__file__).with_name("tuple12-candidate.json"))
    ap.add_argument("--member", action="append", default=[], metavar="NAME=SHA256")
    ap.add_argument("--source", action="append", default=[], metavar="NAME=PATH")
    ns = ap.parse_args(); candidate_raw = ns.candidate.expanduser()
    if candidate_raw.is_symlink(): fail(f"candidate symlink refused: {candidate_raw}")
    candidate = candidate_raw.resolve()
    if not candidate.is_file() or candidate.is_symlink(): fail(f"candidate must be regular file: {candidate}")
    try: candidate.relative_to(REPO)
    except ValueError: fail(f"candidate outside repository: {candidate}")
    data = json.loads(candidate.read_text(encoding="utf-8"))
    if tuple(data.get("members", {})) != MEMBERS: fail("candidate member schema mismatch")
    requested = {}
    for value in ns.member:
        name, raw = pair(value, "member")
        if not HEX.fullmatch(raw): fail(f"non-64-hex hash: {value}")
        requested[name] = raw.lower()
    source_args = {}
    for value in ns.source:
        name, raw = pair(value, "source")
        if name in source_args: fail(f"duplicate source: {name}")
        source_args[name] = safe_file(raw)
    if not requested and not source_args: fail("at least one reviewed member hash and source is required")
    populated = {n for n in MEMBERS if data["members"][n].get("sha256") or data["members"][n].get("source")}
    missing_revalidation = populated - set(source_args)
    if missing_revalidation:
        fail("prepopulated member requires fresh --source revalidation: " + ",".join(sorted(missing_revalidation)))
    missing = set(requested) - set(source_args)
    if missing: fail("member hash requires matching --source: " + ",".join(sorted(missing)))
    updates, refs = {}, {}
    for name, receipt in source_args.items():
        artifact, actual = bound_artifact(receipt)
        if name in requested and requested[name] != actual: fail(f"member hash does not match artifact bytes: {name}")
        updates[name] = actual
        refs[name] = f"{receipt} sha256={digest(receipt)} artifact={artifact} artifact_sha256={actual}"
    for name, value in updates.items():
        data["members"][name]["sha256"] = value
        old = data["members"][name].get("source", [])
        data["members"][name]["source"] = list(dict.fromkeys([*old, refs[name]]))
    top_renderer = str(data.get("renderer_sha256", "")).lower()
    member_renderer = str(data["members"]["windows_renderer"].get("sha256", "")).lower()
    if top_renderer and member_renderer and top_renderer != member_renderer:
        fail(f"renderer join mismatch: renderer_sha256={top_renderer} windows_renderer={member_renderer}")
    complete = all(HEX.fullmatch(str(data["members"][n].get("sha256", ""))) and data["members"][n].get("source") for n in MEMBERS)
    data["status"] = "RECEIPTED_CANDIDATE" if complete else "PARTIAL_RECEIPTS"
    data["note"] = "Candidate only; every populated hash is bound to verified artifact bytes or sealed binary/run receipt; tuple12 qualification remains pending stage, W08 proof, matrix, native, package, and 20-per-side receipts."
    candidate.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print("UPDATED", candidate, *sorted(updates))

if __name__ == "__main__": main()
