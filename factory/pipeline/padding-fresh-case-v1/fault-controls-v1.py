#!/usr/bin/env python3
"""Offline source-admission controls for fresh Padding packet.

Copies only packet-listed bounded files into fresh fixture roots, then invokes
validate-padding-fresh-inputs.py. Originals, binaries, & native state remain untouched.
"""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, subprocess, sys
from pathlib import Path

MAX_TOTAL = 32 * 1024 * 1024
MAX_FILE = 8 * 1024 * 1024


def bounded_hash(path: Path) -> tuple[str, int]:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_FILE:
        raise ValueError(f"unsafe fixture input: {path}")
    h = hashlib.sha256(); total = 0
    with path.open("rb") as f:
        while True:
            b = f.read(1024 * 1024)
            if not b: break
            total += len(b)
            if total > MAX_FILE: raise ValueError(f"fixture file grew: {path}")
            h.update(b)
    return h.hexdigest(), total


def load_json(path: Path):
    st = path.stat()
    if st.st_size > 2 * 1024 * 1024: raise ValueError(f"JSON exceeds bound: {path}")
    return json.loads(path.read_bytes().decode("utf-8-sig"))


def write_json(path: Path, obj) -> None:
    data = (json.dumps(obj, indent=2) + "\n").encode()
    if len(data) > MAX_FILE: raise ValueError(f"fixture JSON exceeds bound: {path}")
    path.write_bytes(data)


def reseal_packet_ref(packet: dict, root: Path, rel: str) -> None:
    p = root / rel
    digest, size = bounded_hash(p)
    for row in packet["references"]:
        if row.get("path") == rel:
            row["sha256"], row["bytes"] = digest, size
            return
    raise ValueError(f"missing packet reference: {rel}")


def prepare_fixture(base_root: Path, base_packet: Path, case_root: Path) -> Path:
    if case_root.exists(): raise ValueError(f"fixture collision: {case_root}")
    packet = load_json(base_packet)
    rows = packet.get("references")
    if not isinstance(rows, list): raise ValueError("packet references missing")
    case_root.mkdir(parents=True)
    total = 0
    # Copy only explicit packet references. No recursive discovery.
    for row in rows:
        rel = row.get("path")
        if not isinstance(rel, str) or Path(rel).is_absolute() or ".." in Path(rel).parts:
            raise ValueError(f"unsafe packet reference: {rel!r}")
        src = base_root / rel
        st = src.stat()
        if not src.is_file() or src.is_symlink() or st.st_size > MAX_FILE:
            raise ValueError(f"unsafe packet input: {rel}")
        total += st.st_size
        if total > MAX_TOTAL: raise ValueError("fixture input total exceeds 32 MiB")
        dst = case_root / rel; dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    dst_packet = case_root / base_packet.relative_to(base_root)
    dst_packet.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(base_packet, dst_packet)
    return dst_packet


def invoke_validator(repo: Path, fixture_root: Path, packet: Path, expected: bool) -> tuple[bool, str]:
    tool = repo / "factory/pipeline/padding-fresh-case-v1/validate-padding-fresh-inputs.py"
    cp = subprocess.run([sys.executable, str(tool), "--root", str(fixture_root), "--packet", str(packet)], cwd=repo, capture_output=True, text=True, timeout=10)
    out = (cp.stdout + cp.stderr).strip()
    accepted = cp.returncode == 0 and '"status":"SOURCE_ADMISSION_PASS"' in cp.stdout
    if accepted != expected:
        raise AssertionError(f"unexpected validator result rc={cp.returncode}: {out[:2000]}")
    return accepted, out[:4000]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--packet", required=True, type=Path)
    ap.add_argument("--control-root", required=True, type=Path)
    args = ap.parse_args()
    repo = args.root.resolve(); base_packet = args.packet.resolve(); base_root = repo
    if args.control_root.exists(): raise ValueError("control root must be fresh")
    args.control_root.mkdir(parents=True)
    baseline = prepare_fixture(base_root, base_packet, args.control_root / "baseline")
    _, baseline_out = invoke_validator(repo, args.control_root / "baseline", baseline, True)
    cases = [
      ("historical-host-relabel", "packet", None, lambda p, r: p["historical"].update(tupleMacHostSha256=p["freshMac"]["tupleMacHostSha256"]), "historical donor unexpectedly equals fresh host"),
      ("wrong-witness-source", "packet", None, lambda p, r: p["source"].update(witnessSha256="0"*64), "frozen fresh witness top-level source hash drift"),
      ("candidate-nested-witness-drift", "json", "factory/pipeline/padding-fresh-case-v1/candidate-source-manifest.json", lambda p, r: p["channels"]["witnesses"][0].update(sourceHash="sha256:"+"1"*64), "candidate witness source hash mismatch"),
      ("case-tuple-mac-host-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json", lambda p, r: p["tuple"]["hostHashes"].update(macos="sha256:"+"2"*64), "fresh host hash drift"),
      ("case-identity-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json", lambda p, r: p.update(id=p["id"]+".mutated"), "fresh case/tuple identity drift"),
      ("compiler-output-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/host/evidence/compiler-receipt.json", lambda p, r: p["compiler"]["outputBinary"].update(sha256="sha256:"+"3"*64), "compiler receipt/output mismatch"),
      ("host-build-source-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/host/host-build-r1.json", lambda p, r: p["source"].update(sha256="sha256:"+"4"*64), "host build/source mismatch"),
      ("runtime-commit-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json", lambda p, r: p["tuple"].update(runtimeCommit="0"*40), "runtime commit drift"),
      ("renderer-hash-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/generated/13bfe5b8fbd9/cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json", lambda p, r: p["tuple"].update(rendererHash="sha256:"+"7"*64), "renderer hash drift"),
      ("mac-promoted", "json", "factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/evidence/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9/summary.json", lambda p, r: p.update(acceptance="promoted"), "Mac evidence incorrectly promoted"),
      ("candidate-manifest-top-source-drift", "json", "factory/pipeline/padding-fresh-case-v1/candidate-source-manifest.json", lambda p, r: p.update(sourceHash="sha256:"+"5"*64), "candidate manifest source hash mismatch"),
      ("windows-host-packet-drift", "packet", None, lambda p, r: p["freshMac"].update(tupleWindowsHostSha256="6"*64), "fresh host hash drift"),
      ("mac-candidate-flag-drift", "json", "factory/oracle/mac/padding-origin-r11-source-v1/observed-mac20-r1/evidence/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9/summary.json", lambda p, r: p.update(candidateOnly=False), "Mac evidence incorrectly promoted"),
    ]
    results = [{"name":"baseline", "accepted":True, "expectedAccepted":True, "nativeActions":0, "output":baseline_out}]
    for name, kind, rel, mutate, expected_error in cases:
        root = args.control_root / name
        packet = prepare_fixture(base_root, base_packet, root)
        if kind == "packet":
            obj = load_json(packet); mutate(obj, obj); write_json(packet, obj)
        else:
            if not rel:
                raise ValueError(f"missing explicit fixture path: {name}")
            doc_path = root / rel
            doc = load_json(doc_path); mutate(doc, doc); write_json(doc_path, doc)
            packet_obj = load_json(packet); reseal_packet_ref(packet_obj, root, rel); write_json(packet, packet_obj)
        ok, out = invoke_validator(repo, root, packet, False)
        if expected_error not in out:
            raise AssertionError(f"{name} missing expected rejection {expected_error!r}: {out[:2000]}")
        results.append({"name":name, "accepted":False, "expectedAccepted":False, "nativeActions":0, "error":expected_error, "output":out})
    receipt={"schema":"factory-padding-fresh-source-fault-controls-v1", "status":"SOURCE_CONTROLS_PASS", "nativeActions":0, "lockActions":0, "compilerActions":0, "cases":results}
    out=args.control_root/"padding-source-fault-controls.json"; out.write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps({"status":receipt["status"], "cases":len(results), "nativeActions":0, "receipt":str(out)}))
    return 0

if __name__ == "__main__":
    try: raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"status":"SOURCE_CONTROLS_FAIL", "nativeActions":0, "reason":str(exc)}))
        raise SystemExit(2)
