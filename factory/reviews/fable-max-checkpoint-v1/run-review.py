#!/usr/bin/env python3
"""Feed one bounded read-only Fable Max CLI review without shell execution."""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--prompt", type=Path, required=True)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
prompt = args.prompt.resolve()
prompt.relative_to(repo)
if not prompt.is_file() or prompt.stat().st_size > 32 * 1024:
    raise SystemExit("prompt missing or over32KiB")
args.out.mkdir(parents=True, exist_ok=False)
session = str(uuid.uuid4())
argv = [
    "/Users/adrdsouza/.local/bin/claude", "--print", "--model", "fable",
    "--effort", "max", "--session-id", session,
    "--name", "SwiftRight checkpoint Fable Max",
    "--output-format", "json", "--restricted", "--safe-mode",
    "--strict-mcp-config", "--tools", "Read,Glob,Grep",
    "--permission-mode", "plan", "--permission-prompts", "none",
    "--disable-slash-commands", "--no-chrome",
]
started = dt.datetime.now(dt.timezone.utc).isoformat()
invocation = {"kind": "factory-fable-max-review-invocation-v1", "sessionId": session,
              "modelRequested": "fable", "effortRequested": "max", "argv": argv,
              "cwd": str(repo), "promptPath": str(prompt.relative_to(repo)),
              "startedAt": started, "readOnly": True, "nativeWorkPaused": True}
(args.out / "invocation.json").write_text(json.dumps(invocation, indent=2) + "\n")
with prompt.open("rb") as stdin:
    result = subprocess.run(argv, cwd=repo, stdin=stdin, check=False)
terminal = {**invocation, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "exitCode": result.returncode}
(args.out / "terminal.json").write_text(json.dumps(terminal, indent=2) + "\n")
raise SystemExit(result.returncode)
