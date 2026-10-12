"""Strict paired Mac full-viewport & Windows centered Count1/Count20 verifier.

This reader is diagnostic only: it never promotes parity, golden images, or
qualification.  It verifies source/case/tuple/receipt/lifecycle joins first,
then compares every paired client raster byte-for-byte as RGBA.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops

MAX_JSON = 16 * 1024 * 1024
MAX_BINARY = 64 * 1024 * 1024
HASH_CHUNK = 1024 * 1024
EXPECTED_ROWS = {"client.png", "observation.raw.json", "stderr.bin", "supervision.json", "original-start.json"}
WINDOWS_COMPILE_KINDS = {"factory-rectangle-owned-compile-v1", "factory-pilot-five-owned-compile-v1"}


class VerificationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise VerificationError(message)


def read_bytes(path: Path, cap: int) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"missing/non-regular file: {path}")
    size = path.stat().st_size
    if size > cap:
        fail(f"file exceeds cap: {path}")
    return path.read_bytes()


def sha256(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        fail(f"missing/non-regular file: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(HASH_CHUNK):
            h.update(chunk)
    return h.hexdigest()


def json_file(path: Path) -> Any:
    try:
        return json.loads(read_bytes(path, MAX_JSON).decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON: {path}: {exc}")


def unprefix(value: Any) -> str:
    return value[7:] if isinstance(value, str) and value.startswith("sha256:") else value


def exact_file(root: Path, row: dict[str, Any], *, label: str) -> Path:
    rel = row.get("path")
    if not isinstance(rel, str) or not rel or Path(rel).is_absolute():
        fail(f"{label}: unsafe row path")
    target = (root / rel).resolve()
    base = root.resolve()
    try:
        target.relative_to(base)
    except ValueError:
        fail(f"{label}: row escapes root")
    raw = read_bytes(target, MAX_BINARY)
    if len(raw) != row.get("bytes") or sha256(target) != unprefix(row.get("sha256")):
        fail(f"{label}: row bytes/hash mismatch")
    return target


def load_manifest(run: Path, expected_case: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, Any], Path]:
    manifest = json_file(run / "manifest.json")
    if not isinstance(manifest, dict) or manifest.get("kind") != "factory-full-viewport-mac-count1-archive-v1":
        fail(f"{run}: unexpected Mac manifest kind")
    rows = manifest.get("rows")
    if not isinstance(rows, list) or {r.get("path") for r in rows if isinstance(r, dict)} != EXPECTED_ROWS or len(rows) != len(EXPECTED_ROWS):
        fail(f"{run}: Mac manifest row set mismatch")
    row_map = {r["path"]: r for r in rows}
    for name, row in row_map.items():
        if not isinstance(row, dict):
            fail(f"{run}: malformed row {name}")
        exact_file(run, row, label=f"{run.name}/{name}")
    raw = json_file(run / "observation.raw.json")
    image_path = run / "client.png"
    if expected_case is not None and manifest.get("case") != expected_case:
        fail(f"{run}: Mac case mismatch")
    with Image.open(image_path) as image:
        if image.width != 800 or image.height != 600:
            fail(f"{run}: Mac client dimensions mismatch")
    return manifest, raw, image_path


def verify_mac_run(run: Path, expected: dict[str, Any] | None) -> dict[str, Any]:
    manifest, raw, image_path = load_manifest(run, expected["case"] if expected else None)
    if manifest.get("sourceHash") != expected["sourceHash"] or manifest.get("hostSourceHash") != expected["hostSourceHash"]:
        fail(f"{run}: Mac source witness mismatch")
    if manifest.get("hostHash") != expected["hostHash"]:
        fail(f"{run}: Mac host hash mismatch")
    receipt_hash = sha256(expected["receipt_path"])
    if unprefix(manifest.get("buildReceiptHash")) != receipt_hash:
        fail(f"{run}: Mac build receipt hash mismatch")
    if manifest.get("referenceContext", {}).get("tupleRendererHash") != expected["rendererHash"] or manifest.get("referenceContext", {}).get("runtimeCommit") != expected["runtimeCommit"]:
        fail(f"{run}: Mac renderer/runtime mismatch")
    if manifest.get("captureScale") != 2.5 or manifest.get("viewportDip") != [320, 240] or manifest.get("hostAlignment") != "center" or manifest.get("hostBackground") != "explicit opaque white":
        fail(f"{run}: Mac viewport/placement witness mismatch")
    if manifest.get("qualified") is not False or manifest.get("originalTerminalProof") is not True or manifest.get("permissionRequests") is not False:
        fail(f"{run}: Mac qualification/lifecycle guard mismatch")
    expected_pid = manifest.get("originalPid")
    if not isinstance(expected_pid, int) or raw.get("pid") != expected_pid or raw.get("status") != "OBSERVED" or raw.get("kind") != "factory-full-viewport-mac-observation-v1":
        fail(f"{run}: Mac raw observation/PID mismatch")
    if raw.get("permissionRequests") is not False or raw.get("captureScale") != 2.5 or raw.get("viewportPoints") != [320, 240] or raw.get("imagePixels") != [800, 600]:
        fail(f"{run}: Mac raw geometry/lifecycle mismatch")
    supervision = json_file(run / "supervision.json")
    original = json_file(run / "original-start.json")
    if supervision.get("kind") != "factory-supervised-local-job-v2" or supervision.get("pid") != expected_pid or supervision.get("exitCode") != 0 or supervision.get("budgetFailure") is not None or supervision.get("quiescenceKnown") is not True or supervision.get("ownedGroupQuiescent") is not True or supervision.get("finalInventory", {}).get("known") is not True or supervision.get("finalInventory", {}).get("count") != 0 or supervision.get("termination") != [] or supervision.get("supervisorError") != "":
        fail(f"{run}: Mac supervision lifecycle mismatch")
    if original.get("pid") != expected_pid or original.get("pgid") != expected_pid or not isinstance(original.get("argv"), list) or not original["argv"]:
        fail(f"{run}: Mac original process join mismatch")
    row_map = {row["path"]: row for row in manifest["rows"]}
    if supervision.get("stdout", {}).get("bytes") != row_map["observation.raw.json"].get("bytes") or unprefix(supervision.get("stdout", {}).get("sha256")) != unprefix(row_map["observation.raw.json"].get("sha256")):
        fail(f"{run}: Mac stdout row mismatch")
    if supervision.get("stderr", {}).get("bytes") != row_map["stderr.bin"].get("bytes") or unprefix(supervision.get("stderr", {}).get("sha256")) != unprefix(row_map["stderr.bin"].get("sha256")):
        fail(f"{run}: Mac stderr row mismatch")
    return {"manifest": manifest, "raw": raw, "image": image_path, "pid": expected_pid, "imageHash": sha256(image_path)}


def rgba(path: Path) -> tuple[Image.Image, str, str, str]:
    read_bytes(path, MAX_BINARY)
    with Image.open(path) as image:
        if image.width * image.height > 2_000_000:
            fail(f"image exceeds pixel cap: {path}")
        source_mode = image.mode
        converted = image.convert("RGBA")
    conversion = "none" if source_mode == "RGBA" else f"{source_mode}->RGBA channel-preserving decode"
    return converted, hashlib.sha256(converted.tobytes()).hexdigest(), source_mode, conversion


def image_diff(left: Image.Image, right: Image.Image) -> tuple[int | None, list[int] | None]:
    if left.size != right.size:
        return None, None
    diff = ImageChops.difference(left, right)
    mask = diff.getchannel(0)
    for channel in diff.getbands()[1:]:
        mask = ImageChops.lighter(mask, diff.getchannel(channel))
    bbox = mask.getbbox()
    return sum(1 for pixel in mask.getdata() if pixel), list(bbox) if bbox else None


def _bounded_copy_tree(source: Path, destination: Path) -> None:
    files = 0
    total = 0
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        target = destination / rel
        if path.is_symlink() or (path.is_file() and path.stat().st_size > MAX_BINARY):
            fail(f"negative fixture unsafe file: {path}")
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        if not path.is_file():
            fail(f"negative fixture non-regular file: {path}")
        files += 1
        total += path.stat().st_size
        if files > 64 or total > 16 * 1024 * 1024:
            fail("negative fixture exceeds bounded copy cap")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def _mutate_manifest(run: Path, field: str, value: Any) -> None:
    manifest_path = run / "manifest.json"
    manifest = json_file(manifest_path)
    if field == "case":
        manifest["case"] = {"id": "mutated-case", "hash": "sha256:mutated-case"}
    elif field == "runtime":
        manifest["referenceContext"]["runtimeCommit"] = "mutated-runtime"
    elif field == "renderer":
        manifest["referenceContext"]["tupleRendererHash"] = "sha256:mutated-renderer"
    else:
        manifest[field] = value
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def run_negative_controls(mac_run: Path, expected: dict[str, Any]) -> dict[str, Any]:
    """Exercise production Mac reader against bounded, coherently copied Count1 fixtures."""
    checks: list[str] = []
    source_root = mac_run.parent
    with tempfile.TemporaryDirectory(prefix="paired20-controls-", dir=".factory-work") as scratch:
        scratch_root = Path(scratch)
        baseline_copy = scratch_root / "baseline"
        _bounded_copy_tree(mac_run, baseline_copy)
        verify_mac_run(baseline_copy, expected)
        mutation_values = {
            "sourceHash": "sha256:mutated-witness",
            "case": None,
            "runtime": None,
            "renderer": None,
        }
        for field, value in mutation_values.items():
            target = scratch_root / field
            _bounded_copy_tree(mac_run, target)
            _mutate_manifest(target, field, value)
            try:
                verify_mac_run(target, expected)
            except VerificationError:
                checks.append(field)
            else:
                fail(f"production reader accepted mutated {field} join")

        client = scratch_root / "client"
        _bounded_copy_tree(mac_run, client)
        raw_path = client / "observation.raw.json"
        raw = json_file(raw_path)
        raw["imagePixels"] = [799, 600]
        raw_path.write_text(json.dumps(raw, separators=(",", ":")), encoding="utf-8")
        manifest = json_file(client / "manifest.json")
        for row in manifest["rows"]:
            if row["path"] == "observation.raw.json":
                row["bytes"] = raw_path.stat().st_size
                row["sha256"] = "sha256:" + sha256(raw_path)
        (client / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        try:
            verify_mac_run(client, expected)
        except VerificationError:
            checks.append("client")
        else:
            fail("production reader accepted mutated client geometry")

        pixel = scratch_root / "pixel"
        _bounded_copy_tree(mac_run, pixel)
        image_path = pixel / "client.png"
        with Image.open(image_path) as image:
            changed = image.convert("RGBA")
            old = changed.getpixel((0, 0))
            changed.putpixel((0, 0), ((old[0] ^ 1), old[1], old[2], old[3]))
            changed.save(image_path, format="PNG")
        manifest = json_file(pixel / "manifest.json")
        for row in manifest["rows"]:
            if row["path"] == "client.png":
                row["bytes"] = image_path.stat().st_size
                row["sha256"] = "sha256:" + sha256(image_path)
        (pixel / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        verify_mac_run(pixel, expected)
        original, *_ = rgba(mac_run / "client.png")
        mutated, *_ = rgba(image_path)
        differing, _ = image_diff(original, mutated)
        if differing != 1:
            fail("production reader/pixel comparator missed one-pixel mutation")
        checks.append("pixel")
    return {
        "passed": True,
        "count": len(checks),
        "mutations": checks,
        "reader": "verify_mac_run",
        "fixture": str(source_root),
        "scope": "Mac-side artifact faults only; Windows negative-control coverage unavailable",
    }


def verify_receipt(receipt_path: Path) -> dict[str, Any]:
    receipt = json_file(receipt_path)
    if not isinstance(receipt, dict) or receipt.get("kind") != "factory-full-viewport-mac-build-receipt-v1" or receipt.get("exitCode") != 0 or receipt.get("nativeActions") != 0 or receipt.get("originalHandleRetained") is not True or receipt.get("qualified") is not False:
        fail("Mac build receipt lifecycle/qualification mismatch")
    sources = receipt.get("sources")
    if not isinstance(sources, list) or len(sources) != 2 or any(not isinstance(row, dict) for row in sources):
        fail("Mac build receipt source witness mismatch")
    if any(not isinstance(row.get("sha256"), str) or not isinstance(row.get("bytes"), int) for row in sources):
        fail("Mac build receipt source rows malformed")
    return {"receipt": receipt, "receipt_path": receipt_path, "receipt_hash": sha256(receipt_path), "sourceHash": sources[0]["sha256"], "hostSourceHash": sources[1]["sha256"], "hostHash": receipt.get("executable", {}).get("sha256"), "rendererHash": None, "runtimeCommit": None, "case": None}


def verify_windows(root: Path, expected_count: int) -> dict[str, Any]:
    control_dirs = sorted(p for p in root.glob("control-*") if p.is_dir() and (p / "coordinator.json").is_file())
    if len(control_dirs) != 1:
        fail(f"expected one coordinator directory, found {len(control_dirs)}")
    coordinator = json_file(control_dirs[0] / "coordinator.json")
    if coordinator.get("count") != expected_count or coordinator.get("status") != "completed-source-bound-observation" or coordinator.get("wholeBatchExitConfirmed") is not True or coordinator.get("lockReleased") is not True or coordinator.get("cleanupErrors") != []:
        fail("Windows coordinator count/status/lock join mismatch")
    parent = coordinator.get("taskParentProof", {})
    if parent.get("kernelWait") != 0 or parent.get("kernelExitCode") != 0 or parent.get("dotNetExited") is not True or parent.get("dotNetExitCode") != 0:
        fail("Windows coordinator parent lifecycle mismatch")
    native_dirs = sorted(p for p in (root / "native").glob(f"count{expected_count}-r*") if p.is_dir())
    if len(native_dirs) != 1:
        fail(f"expected one Windows native Count{expected_count} directory, found {len(native_dirs)}")
    batch = native_dirs[0]
    receipt_path = batch / "observation.json"
    compile_receipt = json_file(receipt_path)
    if compile_receipt.get("kind") not in WINDOWS_COMPILE_KINDS or compile_receipt.get("phase") != "final" or compile_receipt.get("exitCode") != 0 or compile_receipt.get("nativeActions") != 0 or compile_receipt.get("ownedExited") is not True or compile_receipt.get("streamDrainComplete") is not True or compile_receipt.get("streamsSealed") is not True:
        fail("Windows compile receipt lifecycle mismatch")
    compile_hash = sha256(receipt_path)
    if compile_hash != unprefix(coordinator.get("compileReceiptHash")) or compile_receipt.get("exeSha256") != unprefix(coordinator.get("exeHash")):
        fail("Windows coordinator/compile receipt hash mismatch")
    issued = json_file(batch / "issued-metadata.json")
    if issued.get("expectedCount") != expected_count or issued.get("kind") != "factory-prelaunch-capture-metadata-v2":
        fail("Windows issued metadata count/kind mismatch")
    native_observation = json_file(batch / "native-observation.json")
    native_records = native_observation if isinstance(native_observation, list) else [native_observation]
    if len(native_records) != expected_count:
        fail("Windows native observation count mismatch")
    runtime = json_file(batch / "runtime-source-receipt.json")
    if runtime.get("synthetic") is not False or runtime.get("sourceCommit") != compile_receipt.get("runtimeSourceCommit") or runtime.get("sourceTreeHash") != compile_receipt.get("runtimeSourceTreeHash"):
        fail("Windows runtime source receipt mismatch")
    plan = json_file(batch / "plan.json")
    if plan.get("case") != compile_receipt.get("case") or sha256(batch / "plan.json") != unprefix(issued.get("plan", {}).get("sha256")) or plan.get("case") != issued.get("case") or any(row.get("manifestHash") != plan.get("manifestHash") for row in native_records if isinstance(row, dict)):
        fail("Windows plan/case/observation manifest join mismatch")
    return {"root": root, "batch": batch, "coordinator": coordinator, "compile": compile_receipt, "compile_hash": compile_hash, "issued": issued, "runtime": runtime, "plan": plan, "native_records": native_records}


def verify_windows_run(batch: Path, run_number: int, expected: dict[str, Any], issued: dict[str, Any], compile: dict[str, Any], native_records: list[dict[str, Any]]) -> dict[str, Any]:
    run = batch / f"native-{run_number:02d}"
    if not run.is_dir():
        fail(f"missing Windows run {run.name}")
    required = ["native.pixels.json", "native.printwindow.png", "native.printwindow.repeat.png", "lifecycle-timing.json", "capture-outcome.json", "final-exit-certificate.json", "measured-capture-identity.json"]
    for name in required:
        if not (run / name).is_file():
            fail(f"{run.name}: missing lifecycle/pixel file {name}")
    obs = native_records[run_number - 1]
    if not isinstance(obs, dict):
        fail(f"{run.name}: malformed batch native observation")
    pixels = json_file(run / "native.pixels.json")
    timing = json_file(run / "lifecycle-timing.json")
    outcome = json_file(run / "capture-outcome.json")
    final_exit = json_file(run / "final-exit-certificate.json")
    identity = json_file(run / "measured-capture-identity.json")
    if obs.get("index") != run_number or obs.get("case") != compile.get("case") or obs.get("compiledPlanCase") != compile.get("case") or obs.get("sourceHash") != compile.get("sourceHash") or obs.get("rendererSha256") != compile.get("rendererSha256") or obs.get("runtimeSourceCommit") != compile.get("runtimeSourceCommit") or obs.get("runtimeSourceTreeHash") != compile.get("runtimeSourceTreeHash") or obs.get("compileReceiptHash") != expected["compile_hash"] or obs.get("exeSha256") != compile.get("exeSha256") or obs.get("exitCode") != 0 or obs.get("occlusionQualified") is not False or obs.get("nativeParity") != "hold":
        fail(f"{run.name}: Windows source/case/tuple/receipt join mismatch")
    file_rows = obs.get("files")
    if not isinstance(file_rows, list) or not file_rows:
        fail(f"{run.name}: native observation file rows missing")
    for row in file_rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str) or Path(row["path"]).is_absolute() or ".." in Path(row["path"]).parts:
            fail(f"{run.name}: unsafe native observation file row")
        target = run / row["path"]
        if not target.is_file() or target.is_symlink() or sha256(target) != unprefix(row.get("sha256")):
            fail(f"{run.name}: native observation file row hash mismatch")
    pid = obs.get("ownedIdentity", {}).get("pid")
    if not isinstance(pid, int) or obs.get("ownedIdentity", {}).get("path") != compile.get("exePath"):
        fail(f"{run.name}: Windows owned process mismatch")
    if pixels.get("kind") != "factory-background-pixel-observation" or pixels.get("pid") != pid or pixels.get("hwnd") != obs.get("hwnd") or pixels.get("width") != 800 or pixels.get("height") != 600 or pixels.get("dpi") != 240 or pixels.get("printWindowFlags") != 3 or pixels.get("printWindowFlagNames") != "PW_CLIENTONLY|PW_RENDERFULLCONTENT" or pixels.get("printWindowRepeatStable") is not True:
        fail(f"{run.name}: Windows DPI/client readback mismatch")
    sample = [s for s in pixels.get("samples", []) if isinstance(s, dict) and s.get("method") == "printwindow" and s.get("repeat") == 1]
    if len(sample) != 1 or unprefix(sample[0].get("sha256")) != sha256(run / "native.printwindow.png") or sample[0].get("path") != "native.printwindow.png":
        fail(f"{run.name}: Windows PNG sample join mismatch")
    repeat = [s for s in pixels.get("samples", []) if isinstance(s, dict) and s.get("method") == "printwindow" and s.get("repeat") == 2]
    if len(repeat) != 1 or unprefix(repeat[0].get("sha256")) != sha256(run / "native.printwindow.repeat.png") or sha256(run / "native.printwindow.png") != sha256(run / "native.printwindow.repeat.png"):
        fail(f"{run.name}: Windows repeated PNG mismatch")
    timing_ok = timing.get("kind") == "factory-rectangle-retained-handle-timing-v1" and timing.get("compileReceiptHash") == expected["compile_hash"] and timing.get("exeHash") == unprefix(compile.get("exeSha256")) and timing.get("nativeExitDeadlineSeconds") == 15 and timing.get("rawDrainMilliseconds") == 5000 and timing.get("rawHashesQualification") == "sealed-raw" and any(o.get("phase") == "native-exit-wait-return" and o.get("hasExited") is True and o.get("exitCode") == 0 for o in timing.get("observations", []))
    if not timing_ok:
        fail(f"{run.name}: Windows timing bound/handle lifecycle mismatch")
    if outcome.get("compileReceiptHash") != expected["compile_hash"] or outcome.get("exeHash") != unprefix(compile.get("exeSha256")) or outcome.get("sourceHash") != compile.get("sourceHash") or outcome.get("primaryError") != "" or outcome.get("rawHashesQualification") != "sealed-raw" or outcome.get("cleanup", {}).get("confirmedOwnedExit") is not True or outcome.get("cleanup", {}).get("kernelWaitResult") != 0 or outcome.get("cleanup", {}).get("error") != "":
        fail(f"{run.name}: Windows capture outcome lifecycle mismatch")
    if final_exit.get("kind") != "factory-final-exit-certificate-v1" or final_exit.get("start", {}).get("pid") != pid or final_exit.get("start", {}).get("exeHash") != unprefix(compile.get("exeSha256")) or final_exit.get("sample", {}).get("exitCode") != 0 or final_exit.get("sample", {}).get("kernelAfter") != 0:
        fail(f"{run.name}: Windows final exit join mismatch")
    if identity.get("run") != run_number or identity.get("ownedIdentity", {}).get("pid") != pid or identity.get("ownedIdentity", {}).get("compileReceiptHash") != expected["compile_hash"] or identity.get("ownedIdentity", {}).get("exeHash") != unprefix(compile.get("exeSha256")):
        fail(f"{run.name}: Windows measured identity mismatch")
    return {"run": run_number, "dir": run, "pixels": pixels, "obs": obs, "lifecycleBounds": True, "pid": pid}


def discover_mac_runs(root: Path, expected_count: int) -> list[Path]:
    """Resolve one legacy Count1 archive or exact run sets; reject extras."""
    if expected_count == 1:
        if (root / "manifest.json").is_file():
            return [root]
        runs = sorted(p for p in root.glob("run-[0-9][0-9][0-9]") if p.is_dir())
        if [p.name for p in runs] != ["run-001"]:
            fail("Mac Count1 sidecar must be one archive or exactly run-001")
        return runs
    runs = sorted(p for p in root.glob("run-[0-9][0-9][0-9]") if p.is_dir())
    expected_names = [f"run-{n:03d}" for n in range(1, expected_count + 1)]
    if [p.name for p in runs] != expected_names:
        fail(f"Mac sidecar must contain exactly run-001..run-{expected_count:03d}")
    return runs


def read_expected_case(path: Path) -> dict[str, Any]:
    value = json_file(path)
    if isinstance(value, dict) and isinstance(value.get("case"), dict):
        value = value["case"]
    if not isinstance(value, dict) or not isinstance(value.get("id"), str) or not isinstance(value.get("hash"), str):
        fail("expected-case-json must contain case.id and case.hash")
    return {"id": value["id"], "hash": value["hash"]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mac-root", type=Path, required=True, help="Mac Count1 archive or observed-mac20-rN directory")
    parser.add_argument("--windows-root", type=Path, required=True, help="actual-native-r1/files directory")
    parser.add_argument("--mac-build-receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, choices=(1, 20), default=20)
    parser.add_argument("--expected-case-json", type=Path, help="optional case object used to bind external Count1/Count20 context")
    args = parser.parse_args()
    receipt_info = verify_receipt(args.mac_build_receipt)
    mac_runs = discover_mac_runs(args.mac_root, args.expected_count)
    # Read run-001 first to obtain case/runtime/renderer joins from its manifest.
    first_manifest, first_raw, first_image = load_manifest(mac_runs[0])
    ref = dict(receipt_info)
    ref["case"] = first_manifest.get("case")
    if args.expected_case_json:
        declared_case = read_expected_case(args.expected_case_json)
        if ref["case"] != declared_case:
            fail("Mac archive/expected case join mismatch")
        ref["case"] = declared_case
    ref["rendererHash"] = first_manifest.get("referenceContext", {}).get("tupleRendererHash")
    ref["runtimeCommit"] = first_manifest.get("referenceContext", {}).get("runtimeCommit")
    if first_manifest.get("sourceHash") != ref["sourceHash"] or first_manifest.get("hostSourceHash") != ref["hostSourceHash"] or first_manifest.get("hostHash") != ref["hostHash"] or not ref["case"] or not ref["rendererHash"] or not ref["runtimeCommit"]:
        fail("Mac build receipt/run-001 source/case/witness tuple mismatch")
    if receipt_info["receipt"].get("sources", [])[0].get("sha256") != ref["sourceHash"] or receipt_info["receipt"].get("sources", [])[1].get("sha256") != ref["hostSourceHash"]:
        fail("Mac receipt source witness mismatch")
    mac_evidence = [verify_mac_run(run, ref) for run in mac_runs]
    negative_controls = run_negative_controls(mac_runs[0], ref)
    win = verify_windows(args.windows_root, args.expected_count)
    compile = win["compile"]
    if compile.get("sourceHash") != ref["sourceHash"] or compile.get("case") != ref["case"] or compile.get("runtimeSourceCommit") != ref["runtimeCommit"] or compile.get("rendererSha256") != unprefix(ref["rendererHash"]):
        fail("Windows/Mac source/case/runtime/renderer join mismatch")
    if compile.get("planSha256") != unprefix(win["issued"].get("plan", {}).get("sha256")):
        fail("Windows plan/compile join mismatch")
    windows_runs = [verify_windows_run(win["batch"], n, win, win["issued"], compile, win["native_records"]) for n in range(1, args.expected_count + 1)]
    pairs = []
    exact_count = 0
    geometry_count = 0
    lifecycle_count = 0
    for number, (mac, windows) in enumerate(zip(mac_evidence, windows_runs), 1):
        left, left_hash, left_mode, left_conversion = rgba(mac["image"])
        right, right_hash, right_mode, right_conversion = rgba(windows["dir"] / "native.printwindow.png")
        left_png_hash = sha256(mac["image"])
        right_png_hash = sha256(windows["dir"] / "native.printwindow.png")
        differing, bounds = image_diff(left, right)
        exact = left.size == right.size and left_hash == right_hash
        if exact:
            exact_count += 1
        if windows["lifecycleBounds"]:
            lifecycle_count += 1
        # Mac archive reports accessibilityAttempted=false, so semantic geometry
        # comparison remains explicitly pending instead of being inferred from paint.
        geometry_exact = None
        pairs.append({
            "run": number,
            "macDecodedRgbaSha256": left_hash,
            "windowsDecodedRgbaSha256": right_hash,
            "macPngFileSha256": left_png_hash,
            "windowsPngFileSha256": right_png_hash,
            "macSourcePNGMode": left_mode,
            "windowsSourcePNGMode": right_mode,
            "declaredModeConversion": {"mac": left_conversion, "windows": right_conversion},
            "imageSize": list(left.size),
            "differingPixelCount": differing,
            "differingPixelBounds": bounds,
            "exactPaint": exact,
            "geometryExact": geometry_exact,
            "semanticChannel": "pending; Mac accessibilityAttempted=false",
            "lifecycleBounds": windows["lifecycleBounds"],
            "performanceTimingComparison": "pending; raw lifecycle timing retained; no duration/velocity/stall agreement claimed",
        })
    report = {
        "kind": f"factory-centered-paired-count{args.expected_count}-comparison-v1",
        "macRoot": str(args.mac_root),
        "windowsRoot": str(args.windows_root),
        "macBuildReceipt": str(args.mac_build_receipt),
        "expectedCount": args.expected_count,
        "pairCount": len(pairs),
        "pairs": pairs,
        "exactPaintRuns": exact_count,
        "geometryExactRuns": geometry_count,
        "lifecycleBoundsRuns": lifecycle_count,
        "semanticComparison": {"status": "pending", "reason": "Mac archive accessibilityAttempted=false; no AX/geometry channel available"},
        "performanceTimingComparison": {"status": "pending", "evidence": "each Windows native-XX/lifecycle-timing.json & Mac run-XXX/observation.raw.json retained", "claims": []},
        "negativeControls": negative_controls,
        "normalisation": "none; channel-preserving decode to RGBA for exact comparison",
        "goldenPromotion": False,
        "parityPromotion": False,
        "qualified": False,
        "nativeActions": 0,
        "eligibility": "diagnostic-only; exact source/case/tuple/receipt/lifecycle joins recorded",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps(report))
    return 0 if exact_count == args.expected_count else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerificationError as exc:
        raise SystemExit(f"verification failed: {exc}")
