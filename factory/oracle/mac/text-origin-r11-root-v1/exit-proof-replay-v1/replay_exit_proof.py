#!/usr/bin/env python3
"""Replay retained Text Mac host bytes with explicit child exit receipts.

This source never compiles, relabels, or rewrites prior captures. It copies
only measured retained host bytes into fresh internal execution scratch. Root
invocation supplies fresh scratch & output. Permission failure holds before
host launch; every owned child receives bounded time, RSS, output, waitpid,
& sealed stdout/stderr evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MAX_JSON = 2 * 1024 * 1024
MAX_OUTPUT = 8 * 1024 * 1024
MAX_TOTAL_OUTPUT = 256 * 1024 * 1024
MAX_RSS = 1024 * 1024 * 1024
SHA = "sha256:"
HEX = re.compile(r"^[0-9a-f]{64}$")
CASE_ID = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418"
TUPLE_ID = "sr1-text-paint-v2-r11-paired20-20261012"
HOST_SHA = SHA + "fb2757beded3e6d1d4d650b508ed28f2080f0168d56948f7a1dac2bc897db84c"
AX_SHA = SHA + "7f1013de103feefabf35a525bfedd28a2abbe60763761c8e0372530f8a051581"
ROOT = Path(__file__).resolve().parents[5]
PRODUCER = ROOT / "factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1" / CASE_ID / "producer-bytes-v1"


class Hold(ValueError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def bounded_json(path: Path) -> Any:
    st = path.lstat()
    if not st.st_mode or not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise Hold(f"bounded JSON required: {path}")
    return json.loads(path.read_bytes().decode("utf-8-sig"))


def hash_file(path: Path, limit: int = MAX_OUTPUT) -> tuple[int, str]:
    st = path.lstat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise Hold(f"bounded regular file required: {path}")
    total = 0
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise Hold(f"output grew past bound: {path}")
            digest.update(chunk)
    return total, SHA + digest.hexdigest()


def normalize_hash(value: Any) -> str:
    """Accept producer manifest's measured bare SHA while retaining canonical refs."""
    if not isinstance(value, str):
        raise Hold("producer hash must be text")
    bare = value.removeprefix(SHA)
    if not HEX.fullmatch(bare):
        raise Hold("producer hash must be 64 lowercase hex characters")
    return SHA + bare


def reject_symlink_components(path: Path, root: Path) -> None:
    raw = path.expanduser()
    if not raw.is_absolute():
        raise Hold(f"absolute internal path required: {path}")
    try:
        parts = raw.relative_to(root).parts
    except ValueError as exc:
        raise Hold(f"path escapes internal root: {path}") from exc
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise Hold(f"symlink component rejected: {current}")


def copy_measured(source: Path, destination: Path, expected_bytes: int, expected_hash: str, root: Path) -> dict[str, Any]:
    reject_symlink_components(source, Path(source.anchor))
    reject_symlink_components(destination, root)
    st = source.lstat()
    if not source.is_file() or source.is_symlink() or st.st_size != expected_bytes or expected_bytes > MAX_OUTPUT:
        raise Hold(f"measured producer source mismatch: {source}")
    if destination.exists():
        raise Hold(f"execution copy collision: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total = 0
    with source.open("rb") as inp, destination.open("xb") as out:
        while chunk := inp.read(1024 * 1024):
            total += len(chunk)
            if total > expected_bytes:
                raise Hold(f"producer source grew during copy: {source}")
            digest.update(chunk)
            out.write(chunk)
    actual = SHA + digest.hexdigest()
    if total != expected_bytes or actual != expected_hash:
        raise Hold(f"producer copy hash drift: {source}")
    os.chmod(destination, 0o700)
    copied_bytes, copied_hash = hash_file(destination, MAX_OUTPUT)
    if copied_bytes != expected_bytes or copied_hash != expected_hash:
        raise Hold(f"execution copy verification failed: {destination}")
    return {"archivedPath": str(source), "executionPath": str(destination), "bytes": copied_bytes, "sha256": copied_hash, "mode": "0700"}


def sample_rss(pid: int) -> tuple[int | None, str | None]:
    """Use bounded macOS ps output; fail closed if sample cannot be read."""
    try:
        result = subprocess.run(
            ["/bin/ps", "-o", "rss=", "-p", str(pid)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
            check=False,
        )
        if result.returncode != 0 or len(result.stdout) > 8192:
            return None, "ps rss query failed"
        value = result.stdout.strip().splitlines()
        if not value or not value[0].strip().isdigit():
            return None, "ps rss value missing"
        return int(value[0].strip()) * 1024, None
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        return None, str(exc)


def terminate_owned(proc: subprocess.Popen[bytes], receipt: dict[str, Any]) -> None:
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
        receipt["termSent"] = True
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        receipt["killSent"] = True
        proc.wait(timeout=5)
    except ProcessLookupError:
        receipt["processMissing"] = True


def run_owned(
    command: list[str],
    stdout_path: Path,
    stderr_path: Path,
    timeout: float,
    max_rss: int,
    stdin_pipe: bool = False,
) -> tuple[dict[str, Any], subprocess.Popen[bytes] | None]:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    out = stdout_path.open("wb")
    err = stderr_path.open("wb")
    started = now()
    proc: subprocess.Popen[bytes] | None = None
    receipt: dict[str, Any] = {
        "argv": command,
        "startedAtUtc": started,
        "pid": None,
        "waitPidObserved": False,
        "exitCode": None,
        "timedOut": False,
        "outputLimitExceeded": False,
        "rssLimitExceeded": False,
        "rssObserved": False,
        "rssPeakBytes": None,
        "termSent": False,
        "killSent": False,
        "streamsSealed": False,
    }
    try:
        proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE if stdin_pipe else subprocess.DEVNULL,
            stdout=out,
            stderr=err,
            start_new_session=False,
        )
        receipt["pid"] = proc.pid
        deadline = time.monotonic() + timeout
        peak = 0
        rss_error = None
        while proc.poll() is None:
            if time.monotonic() >= deadline:
                receipt["timedOut"] = True
                terminate_owned(proc, receipt)
                break
            for path in (stdout_path, stderr_path):
                if path.stat().st_size > MAX_OUTPUT:
                    receipt["outputLimitExceeded"] = True
                    terminate_owned(proc, receipt)
                    break
            if receipt["outputLimitExceeded"]:
                break
            rss, rss_error = sample_rss(proc.pid)
            if rss is not None:
                receipt["rssObserved"] = True
                peak = max(peak, rss)
                if peak > max_rss:
                    receipt["rssLimitExceeded"] = True
                    terminate_owned(proc, receipt)
                    break
            time.sleep(0.1)
        if proc.poll() is None:
            terminate_owned(proc, receipt)
        receipt["exitCode"] = proc.wait(timeout=5)
        receipt["waitPidObserved"] = True
        receipt["rssPeakBytes"] = peak or None
        if rss_error and not receipt["rssObserved"]:
            receipt["rssError"] = rss_error
    finally:
        if proc is not None and proc.poll() is None:
            terminate_owned(proc, receipt)
        if stdin_pipe and proc is not None and proc.stdin is not None:
            try:
                proc.stdin.close()
            except OSError:
                pass
        out.flush()
        err.flush()
        out.close()
        err.close()
        out_bytes, out_hash = hash_file(stdout_path)
        err_bytes, err_hash = hash_file(stderr_path)
        receipt.update({
            "stdout": {"path": str(stdout_path), "bytes": out_bytes, "sha256": out_hash},
            "stderr": {"path": str(stderr_path), "bytes": err_bytes, "sha256": err_hash},
            "streamsSealed": True,
            "endedAtUtc": now(),
        })
    return receipt, proc


def finish_owned(
    proc: subprocess.Popen[bytes],
    out: Any,
    err: Any,
    stdout_path: Path,
    stderr_path: Path,
    started: str,
    receipt: dict[str, Any],
    timeout: float,
    max_rss: int,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    peak = 0
    rss_error = None
    while proc.poll() is None:
        if time.monotonic() >= deadline:
            receipt["timedOut"] = True
            terminate_owned(proc, receipt)
            break
        for path in (stdout_path, stderr_path):
            if path.stat().st_size > MAX_OUTPUT:
                receipt["outputLimitExceeded"] = True
                terminate_owned(proc, receipt)
                break
        if receipt["outputLimitExceeded"]:
            break
        rss, rss_error = sample_rss(proc.pid)
        if rss is not None:
            receipt["rssObserved"] = True
            peak = max(peak, rss)
            if peak > max_rss:
                receipt["rssLimitExceeded"] = True
                terminate_owned(proc, receipt)
                break
        time.sleep(0.1)
    if proc.poll() is None:
        terminate_owned(proc, receipt)
    receipt["exitCode"] = proc.wait(timeout=5)
    receipt["waitPidObserved"] = True
    receipt["rssPeakBytes"] = peak or None
    if rss_error and not receipt["rssObserved"]:
        receipt["rssError"] = rss_error
    out.flush()
    err.flush()
    out.close()
    err.close()
    out_bytes, out_hash = hash_file(stdout_path)
    err_bytes, err_hash = hash_file(stderr_path)
    receipt.update({
        "stdout": {"path": str(stdout_path), "bytes": out_bytes, "sha256": out_hash},
        "stderr": {"path": str(stderr_path), "bytes": err_bytes, "sha256": err_hash},
        "streamsSealed": True,
        "endedAtUtc": now(),
    })
    return receipt


def require_producer(manifest_path: Path, host: Path, ax: Path) -> dict[str, Any]:
    manifest = bounded_json(manifest_path)
    if manifest.get("kind") != "factory-mac-pilot-producer-byte-archive-v1":
        raise Hold("producer byte archive kind mismatch")
    rows = {row.get("archivePath"): row for row in manifest.get("files", []) if isinstance(row, dict)}
    host_row = next((row for path, row in rows.items() if str(path).endswith("/capture-host")), None)
    ax_row = next((row for path, row in rows.items() if str(path).endswith("/ax-f5-ax-client")), None)
    if not host_row or not ax_row:
        raise Hold("producer archive lacks capture-host or AX client")
    for actual, row, expected in ((host, host_row, HOST_SHA), (ax, ax_row, AX_SHA)):
        if int(row.get("bytes", -1)) <= 0 or normalize_hash(row.get("sha256")) != expected:
            raise Hold(f"producer measured hash row mismatch: {actual.name}")
        size, digest = hash_file(actual, MAX_OUTPUT)
        if size != int(row["bytes"]) or digest != expected:
            raise Hold(f"retained producer bytes drift: {actual}")
    return {"manifest": str(manifest_path), "host": {"path": str(host), "bytes": host_row["bytes"], "sha256": HOST_SHA}, "ax": {"path": str(ax), "bytes": ax_row["bytes"], "sha256": AX_SHA}}


def stage_execution(producer: dict[str, Any], scratch: Path) -> dict[str, Any]:
    execution_root = scratch / "bin"
    reject_symlink_components(execution_root, scratch)
    if execution_root.exists() and any(execution_root.iterdir()):
        raise Hold("execution bin must be fresh")
    execution_root.mkdir(parents=True, exist_ok=True)
    host = copy_measured(Path(producer["host"]["path"]), execution_root / "capture-host", producer["host"]["bytes"], producer["host"]["sha256"], scratch)
    ax = copy_measured(Path(producer["ax"]["path"]), execution_root / "ax-f5-ax-client", producer["ax"]["bytes"], producer["ax"]["sha256"], scratch)
    return {"host": host, "ax": ax, "root": str(execution_root)}


def validate_execution_record(execution: dict[str, Any], scratch: Path) -> None:
    """Reject archived-path execution, drift, symlinks, & non-executable copies."""
    root = (scratch / "bin").resolve()
    if execution.get("root") != str(root):
        raise Hold("execution root record mismatch")
    for role in ("host", "ax"):
        row = execution.get(role)
        if not isinstance(row, dict):
            raise Hold(f"execution row missing: {role}")
        archived = Path(str(row.get("archivedPath", "")))
        staged = Path(str(row.get("executionPath", "")))
        if not archived.is_absolute() or not staged.is_absolute() or archived == staged:
            raise Hold(f"archived/execution path collision: {role}")
        try:
            if staged.resolve().parent != root or not staged.resolve().is_relative_to(root):
                raise Hold(f"execution path outside scratch: {role}")
        except OSError as exc:
            raise Hold(f"execution path cannot resolve: {role}") from exc
        reject_symlink_components(staged, scratch)
        st = staged.lstat()
        if not stat.S_ISREG(st.st_mode) or not (st.st_mode & stat.S_IXUSR):
            raise Hold(f"execution copy not owner-executable: {role}")
        size, digest = hash_file(staged, MAX_OUTPUT)
        if size != int(row.get("bytes", -1)) or digest != row.get("sha256"):
            raise Hold(f"execution copy record drift: {role}")


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def replay(args: argparse.Namespace) -> int:
    output = args.output.resolve()
    scratch_raw = args.scratch.expanduser()
    if output.exists() and any(output.iterdir()):
        raise Hold("fresh output must be empty; prior evidence is immutable")
    scratch_root = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory").resolve()
    reject_symlink_components(scratch_raw, scratch_root)
    scratch = scratch_raw.resolve()
    if not scratch.is_relative_to(scratch_root) or scratch == scratch_root:
        raise Hold("scratch must be child of internal SwiftRightFactory cache")
    output.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(parents=True, exist_ok=True)
    producer = require_producer(args.producer_manifest, args.host_binary, args.ax_client)
    execution = stage_execution(producer, scratch)
    validate_execution_record(execution, scratch)
    host_binary = Path(execution["host"]["executionPath"])
    ax_client = Path(execution["ax"]["executionPath"])
    producer["execution"] = execution
    preflight_out = output / "ax-preflight.stdout.txt"
    preflight_err = output / "ax-preflight.stderr.txt"
    # Execute only staged internal copies; archived producer paths remain
    # provenance refs in receipt and are never passed to Popen.
    preflight, _ = run_owned([str(ax_client), "--preflight"], preflight_out, preflight_err, 15, args.max_rss)
    preflight_json = None
    try:
        preflight_json = json.loads(preflight_out.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        pass
    if preflight["exitCode"] != 0 or not isinstance(preflight_json, dict) or preflight_json.get("axTrusted") is not True:
        result = {"kind": "factory-mac-text-exit-proof-replay-v1", "status": "HELD", "nativeActions": 0, "reason": "AX preflight unavailable or untrusted", "producer": producer, "preflight": preflight}
        write_json(output / "replay-receipt.json", result)
        return 2
    total_output = 0
    runs: list[dict[str, Any]] = []
    for run in range(1, args.runs + 1):
        run_root = scratch / f"{args.case_id}.exit-proof.run-{run:03d}"
        run_out = output / f"run-{run:03d}"
        if run_root.exists() or run_out.exists():
            raise Hold(f"fresh run collision: {run}")
        run_root.mkdir(parents=True)
        run_out.mkdir(parents=True)
        row: dict[str, Any] = {"run": run, "caseID": args.case_id, "hostHash": HOST_SHA, "axHash": AX_SHA}
        for label, extra in (("plain", ["--plain"]), ("instrumented", [])):
            stdout = run_out / f"{label}.stdout.txt"
            stderr = run_out / f"{label}.stderr.txt"
            png = run_out / f"{label}.png"
            receipt, _ = run_owned([str(host_binary), "--png", str(png), "--scale", "1", "--scheme", "light", *extra], stdout, stderr, args.host_timeout, args.max_rss)
            if receipt["streamsSealed"] and png.exists():
                png_bytes, png_hash = hash_file(png)
                receipt["png"] = {"path": str(png), "bytes": png_bytes, "sha256": png_hash}
                total_output += png_bytes
            if receipt["streamsSealed"] and stdout.exists() and stdout.stat().st_size <= MAX_JSON:
                try:
                    write_json(run_out / f"{label}.raw.json", json.loads(stdout.read_text(encoding="utf-8-sig")))
                except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                    receipt["rawJson"] = "unavailable"
            row[label] = receipt
            total_output += receipt["stdout"]["bytes"] + receipt["stderr"]["bytes"]
        window_stdout = run_out / "owned-window.stdout.txt"
        window_stderr = run_out / "owned-window.stderr.txt"
        events = run_out / "owned-window-events.jsonl"
        window_command = [str(host_binary), "--window", "--case", args.case_id, "--scheme", "light", "--events", str(events)]
        ax_out = run_out / "external-ax.stdout.txt"
        ax_err = run_out / "external-ax.stderr.txt"
        ax_command = [str(ax_client), "--pid", "{host-pid}", "--owner-path", str(host_binary), "--owner-hash", HOST_SHA, "--window-title", "SwiftRightFactory-" + args.case_id]
        # Host PID is bound into AX argv only after host creation.
        host_started = now()
        host_stdout = window_stdout.open("wb")
        host_stderr = window_stderr.open("wb")
        host = subprocess.Popen(window_command, stdin=subprocess.PIPE, stdout=host_stdout, stderr=host_stderr, start_new_session=False)
        ax_command[2] = str(host.pid)
        host_receipt = {
            "argv": window_command, "startedAtUtc": host_started, "pid": host.pid,
            "waitPidObserved": False, "exitCode": None, "timedOut": False,
            "outputLimitExceeded": False, "rssLimitExceeded": False, "rssObserved": False,
            "rssPeakBytes": None, "termSent": False, "killSent": False, "quitSent": False, "streamsSealed": False,
        }
        ax_receipt = None
        try:
            ax_receipt, _ = run_owned(ax_command, ax_out, ax_err, 15, args.max_rss)
        finally:
            if host.stdin is not None:
                try:
                    host.stdin.write(b'{"step":"quit"}\n'); host.stdin.flush(); host_receipt["quitSent"] = True
                except (BrokenPipeError, OSError):
                    host_receipt["quitSent"] = False
                try: host.stdin.close()
                except OSError: pass
            host_receipt = finish_owned(host, host_stdout, host_stderr, window_stdout, window_stderr, host_started, host_receipt, args.host_timeout, args.max_rss)
        if ax_receipt is None:
            raise Hold(f"AX worker failed to produce receipt for run {run}")
        row["host"] = host_receipt
        write_json(run_out / "owned-window-process.json", {"pid": host_receipt["pid"], "executable": str(host_binary), "archivedExecutable": str(args.host_binary), "binaryHash": HOST_SHA, "windowTitle": "SwiftRightFactory-" + args.case_id, "retainedProcessHandle": True, "waitPidObserved": host_receipt["waitPidObserved"]})
        if events.exists():
            event_bytes, event_hash = hash_file(events)
            row["events"] = {"path": str(events), "bytes": event_bytes, "sha256": event_hash}
            total_output += event_bytes
        if ax_out.exists() and ax_out.stat().st_size <= MAX_JSON:
            try: write_json(run_out / "external-ax.raw.json", json.loads(ax_out.read_text(encoding="utf-8-sig")))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError): row["axRawJson"] = "unavailable"
        row["ax"] = ax_receipt
        total_output += ax_receipt["stdout"]["bytes"] + ax_receipt["stderr"]["bytes"]
        write_json(run_out / "exit-proof.json", row)
        runs.append(row)
        if total_output > MAX_TOTAL_OUTPUT:
            raise Hold("replay output exceeds total bound")
    result = {"kind": "factory-mac-text-exit-proof-replay-v1", "status": "OBSERVED-HELD", "nativeActions": args.runs * 4, "qualified": False, "caseID": args.case_id, "tupleID": TUPLE_ID, "producer": producer, "preflight": preflight, "runs": runs, "holds": ["semantic qualification remains held until Windows/Mac comparison review"]}
    write_json(output / "replay-receipt.json", result)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--producer-manifest", type=Path, default=PRODUCER / "manifest.json")
    parser.add_argument("--host-binary", type=Path, default=PRODUCER / "capture-host")
    parser.add_argument("--ax-client", type=Path, default=PRODUCER / "ax-f5-ax-client")
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case-id", default=CASE_ID)
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--host-timeout", type=float, default=45)
    parser.add_argument("--max-rss", type=int, default=MAX_RSS)
    args = parser.parse_args()
    if args.runs < 1 or args.runs > 20 or args.max_rss < 1:
        raise Hold("invalid bounded replay arguments")
    if args.case_id != CASE_ID:
        raise Hold("only measured Text case is admitted")
    try:
        return replay(args)
    except (Hold, OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        args.output.mkdir(parents=True, exist_ok=True)
        write_json(args.output / "replay-receipt.json", {"kind": "factory-mac-text-exit-proof-replay-v1", "status": "HELD", "nativeActions": 0, "qualified": False, "reason": str(exc)})
        raise


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (Hold, OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print(f"exit-proof replay held: {exc}", file=os.sys.stderr)
        raise SystemExit(2)
