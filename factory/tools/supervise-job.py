#!/usr/bin/env python3
"""Run one owned local job with streamed logs, time/output/RSS budgets & a receipt."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def group_state(pgid):
    result = subprocess.run(
        ["ps", "-axo", "pid=,pgid=,rss=,stat="], capture_output=True, timeout=5, check=True
    )
    if len(result.stdout) > 1024 * 1024:
        raise RuntimeError("process inventory exceeded 1 MiB")
    rows = [row for line in result.stdout.splitlines()
            if len(row := line.split()) == 4 and int(row[1]) == pgid and not row[3].startswith(b"Z")]
    return len(rows), sum(int(row[2]) * 1024 for row in rows)


def signal_owned_group(process, sig):
    if not group_state(process.pid)[0]:
        return
    try:
        os.killpg(process.pid, sig)
    except (ProcessLookupError, PermissionError):
        # A short-lived job may exit between inventory & signal.
        if process.poll() is None or group_state(process.pid)[0]:
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--rss-mib", type=int, default=256)
    parser.add_argument("--log-mib", type=int, default=128)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or min(args.seconds, args.rss_mib, args.log_mib) <= 0:
        parser.error("command & positive budgets required")
    args.out.mkdir(parents=True, exist_ok=False)
    stdout = args.out / "stdout.bin"
    stderr = args.out / "stderr.bin"
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    start = time.monotonic()
    peak = 0
    reason = None
    process = None
    try:
        with stdout.open("xb") as so, stderr.open("xb") as se:
            process = subprocess.Popen(command, stdout=so, stderr=se, start_new_session=True)
            (args.out / "start.json").write_text(json.dumps({
                "pid": process.pid, "pgid": process.pid, "argv": command,
                "startedAt": started, "seconds": args.seconds,
                "rssMiB": args.rss_mib, "logMiB": args.log_mib,
            }, indent=2) + "\n")
            while process.poll() is None:
                peak = max(peak, group_state(process.pid)[1])
                if time.monotonic() - start > args.seconds:
                    reason = "wall-time-budget"
                elif peak > args.rss_mib * 1024 * 1024:
                    reason = "rss-budget"
                elif stdout.stat().st_size + stderr.stat().st_size > args.log_mib * 1024 * 1024:
                    reason = "log-budget"
                if reason:
                    break
                time.sleep(0.25)
            if reason:
                signal_owned_group(process, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    signal_owned_group(process, signal.SIGKILL)
                    process.wait(timeout=5)
            else:
                process.wait()
                if stdout.stat().st_size + stderr.stat().st_size > args.log_mib * 1024 * 1024:
                    reason = "log-budget"
            # Do not leave descendants behind after an owned job finishes.
            if group_state(process.pid)[0]:
                signal_owned_group(process, signal.SIGTERM)
                time.sleep(0.25)
                if group_state(process.pid)[0]:
                    signal_owned_group(process, signal.SIGKILL)
                    time.sleep(0.25)
    except BaseException:
        if process is not None and process.poll() is None:
            try:
                signal_owned_group(process, signal.SIGKILL)
                process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
        raise
    receipt = {
        "kind": "factory-supervised-local-job-v1", "argv": command,
        "pid": process.pid, "exitCode": process.returncode, "budgetFailure": reason,
        "startedAt": started, "finishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "seconds": round(time.monotonic() - start, 3), "peakGroupRssBytes": peak,
        "stdout": {"bytes": stdout.stat().st_size, "sha256": file_hash(stdout)},
        "stderr": {"bytes": stderr.stat().st_size, "sha256": file_hash(stderr)},
        "ownedGroupQuiescent": group_state(process.pid)[0] == 0,
    }
    (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))
    return 124 if reason else process.returncode


if __name__ == "__main__":
    sys.exit(main())
