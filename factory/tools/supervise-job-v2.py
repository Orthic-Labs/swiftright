#!/usr/bin/env python3
"""Bounded local job supervisor with fail-closed inventory receipts.

Only the process group created by this supervisor may be signalled. Inventory
failure never triggers a broad process scan or kill; it is retained in receipt.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from dataclasses import dataclass


MAX_PS_OUTPUT = 1024 * 1024
INVENTORY_RETRIES = 3
INVENTORY_TIMEOUT = 1.0


@dataclass
class Inventory:
    known: bool
    count: int | None
    rss_bytes: int | None
    error: str = ""
    attempts: int = 0


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory_once(pgid: int) -> tuple[int, int]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,pgid=,rss=,stat="],
        capture_output=True,
        timeout=INVENTORY_TIMEOUT,
        check=True,
    )
    if len(result.stdout) > MAX_PS_OUTPUT or len(result.stderr) > MAX_PS_OUTPUT:
        raise RuntimeError("process inventory exceeded 1 MiB")
    count = 0
    rss = 0
    for line in result.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        if len(fields) != 4:
            raise RuntimeError("malformed process inventory row")
        try:
            row_pgid = int(fields[1])
            row_rss_kib = int(fields[2])
        except ValueError as exc:
            raise RuntimeError("non-numeric process inventory row") from exc
        if row_pgid == pgid and not fields[3].startswith(b"Z"):
            count += 1
            rss += row_rss_kib * 1024
    return count, rss


def leader_alive(process: subprocess.Popen[bytes]) -> bool:
    """Prove supervisor-created leader owns a same-ID process group."""
    if process.poll() is not None:
        return False
    try:
        return os.getpgid(process.pid) == process.pid
    except (ProcessLookupError, PermissionError, OSError):
        return False


def inventory(process: subprocess.Popen[bytes], fault: str) -> Inventory:
    errors: list[str] = []
    for attempt in range(1, INVENTORY_RETRIES + 1):
        try:
            if fault == "live-retry" and leader_alive(process) and attempt <= 2:
                raise TimeoutError("injected live inventory timeout")
            if fault == "live-timeout" and leader_alive(process):
                raise TimeoutError("injected live inventory timeout")
            if fault == "after-exit" and not leader_alive(process):
                raise TimeoutError("injected post-exit inventory timeout")
            count, rss = inventory_once(process.pid)
            return Inventory(True, count, rss, attempts=attempt)
        except (OSError, subprocess.SubprocessError, TimeoutError, RuntimeError) as exc:
            errors.append(f"attempt-{attempt}:{type(exc).__name__}:{exc}")
            if attempt < INVENTORY_RETRIES:
                time.sleep(0.05)
    return Inventory(False, None, None, ";".join(errors), INVENTORY_RETRIES)


def signal_owned_group(process: subprocess.Popen[bytes], sig: signal.Signals, *, allow_dead_leader: bool = False) -> bool:
    """Signal only original leader PGID after ownership check."""
    if not allow_dead_leader and not leader_alive(process):
        return False
    try:
        os.killpg(process.pid, sig)
        return True
    except (ProcessLookupError, PermissionError, OSError):
        return False


def terminate_owned(process: subprocess.Popen[bytes], events: list[dict], *, group_verified: bool = False) -> None:
    if process.poll() is None:
        sent = signal_owned_group(process, signal.SIGTERM)
        events.append({"signal": "SIGTERM", "sent": sent, "leaderAlive": sent or leader_alive(process)})
        if sent:
            group_verified = True
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                killed = signal_owned_group(process, signal.SIGKILL, allow_dead_leader=group_verified)
                events.append({"signal": "SIGKILL", "sent": killed, "leaderAlive": killed or leader_alive(process)})
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    events.append({"signal": "wait", "sent": False, "leaderAlive": leader_alive(process)})
    elif group_verified:
        sent = signal_owned_group(process, signal.SIGTERM, allow_dead_leader=True)
        events.append({"signal": "SIGTERM", "sent": sent, "leaderAlive": False, "ownership": "original-pgid"})
        if sent:
            time.sleep(0.25)
            killed = signal_owned_group(process, signal.SIGKILL, allow_dead_leader=True)
            if killed:
                events.append({"signal": "SIGKILL", "sent": True, "leaderAlive": False, "ownership": "original-pgid"})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--rss-mib", type=int, default=256)
    parser.add_argument("--log-mib", type=int, default=128)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--test-inventory-fault", choices=("none", "live-retry", "live-timeout", "after-exit"), default="none", help=argparse.SUPPRESS)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or min(args.seconds, args.rss_mib, args.log_mib) <= 0:
        parser.error("command & positive budgets required")
    args.out.mkdir(parents=True, exist_ok=False)
    stdout_path = args.out / "stdout.bin"
    stderr_path = args.out / "stderr.bin"
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    started_monotonic = time.monotonic()
    process: subprocess.Popen[bytes] | None = None
    peak = 0
    reason: str | None = None
    inventory_errors: list[str] = []
    inventory_attempts = 0
    termination: list[dict] = []
    run_error = ""
    exit_code: int | None = None
    final_inventory = Inventory(False, None, None, "not observed")
    owned_group_verified = False
    try:
        with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
            owned_group_verified = leader_alive(process)
            (args.out / "start.json").write_text(
                json.dumps({"pid": process.pid, "pgid": process.pid, "argv": command, "startedAt": started, "seconds": args.seconds, "rssMiB": args.rss_mib, "logMiB": args.log_mib}, indent=2) + "\n",
                encoding="utf-8",
            )
            while process.poll() is None:
                owned_group_verified = owned_group_verified or leader_alive(process)
                observed = inventory(process, args.test_inventory_fault)
                inventory_attempts += observed.attempts
                if not observed.known:
                    inventory_errors.append(observed.error)
                    reason = "inventory-unavailable"
                else:
                    peak = max(peak, observed.rss_bytes or 0)
                if observed.known:
                    elapsed = time.monotonic() - started_monotonic
                    if elapsed > args.seconds:
                        reason = "wall-time-budget"
                    elif peak > args.rss_mib * 1024 * 1024:
                        reason = "rss-budget"
                    elif stdout_path.stat().st_size + stderr_path.stat().st_size > args.log_mib * 1024 * 1024:
                        reason = "log-budget"
                if reason:
                    break
                time.sleep(0.25)
            if reason:
                terminate_owned(process, termination, group_verified=owned_group_verified)
            else:
                process.wait()
                if stdout_path.stat().st_size + stderr_path.stat().st_size > args.log_mib * 1024 * 1024:
                    reason = "log-budget"
            exit_code = process.returncode
            final_inventory = inventory(process, args.test_inventory_fault)
            inventory_attempts += final_inventory.attempts
            if not final_inventory.known:
                inventory_errors.append(final_inventory.error)
                if reason is None:
                    reason = "inventory-unavailable"
            elif final_inventory.rss_bytes is not None:
                peak = max(peak, final_inventory.rss_bytes)
            if final_inventory.known and (final_inventory.count or 0) > 0:
                reason = reason or "owned-group-not-quiescent"
                terminate_owned(process, termination, group_verified=owned_group_verified)
                final_inventory = inventory(process, args.test_inventory_fault)
                inventory_attempts += final_inventory.attempts
                if not final_inventory.known:
                    inventory_errors.append(final_inventory.error)
                    reason = reason or "inventory-unavailable"
    except BaseException as exc:
        run_error = f"{type(exc).__name__}: {exc}"
        if reason is None:
            reason = "supervisor-error"
        if process is not None:
            terminate_owned(process, termination)
            if process.poll() is not None:
                exit_code = process.returncode
    finally:
        if process is not None and process.poll() is None:
            terminate_owned(process, termination, group_verified=owned_group_verified)
            exit_code = process.returncode
        if process is not None and not final_inventory.known:
            final_inventory = inventory(process, args.test_inventory_fault)
            inventory_attempts += final_inventory.attempts
            if not final_inventory.known:
                inventory_errors.append(final_inventory.error)
        if process is not None and final_inventory.known and (final_inventory.count or 0) > 0:
            reason = reason or "owned-group-not-quiescent"
            terminate_owned(process, termination, group_verified=owned_group_verified)
            final_inventory = inventory(process, args.test_inventory_fault)
            inventory_attempts += final_inventory.attempts
            if not final_inventory.known:
                inventory_errors.append(final_inventory.error)
        quiescence_known = final_inventory.known
        quiescent = bool(quiescence_known and final_inventory.count == 0)
        receipt = {
            "kind": "factory-supervised-local-job-v2",
            "argv": command,
            "pid": process.pid if process is not None else None,
            "exitCode": exit_code,
            "budgetFailure": reason,
            "startedAt": started,
            "finishedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "seconds": round(time.monotonic() - started_monotonic, 3),
            "peakGroupRssBytes": peak,
            "inventory": {"retries": INVENTORY_RETRIES, "timeoutSeconds": INVENTORY_TIMEOUT, "attempts": inventory_attempts, "errors": inventory_errors},
            "finalInventory": {
                "known": final_inventory.known,
                "count": final_inventory.count,
                "rssBytes": final_inventory.rss_bytes,
                "error": final_inventory.error,
                "attempts": final_inventory.attempts,
            },
            "quiescenceKnown": quiescence_known,
            "ownedGroupQuiescent": quiescent,
            "termination": termination,
            "supervisorError": run_error,
        }
        if stdout_path.exists():
            receipt["stdout"] = {"bytes": stdout_path.stat().st_size, "sha256": file_hash(stdout_path)}
        if stderr_path.exists():
            receipt["stderr"] = {"bytes": stderr_path.stat().st_size, "sha256": file_hash(stderr_path)}
        (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return 1 if reason else int(exit_code or 0)


if __name__ == "__main__":
    sys.exit(main())
