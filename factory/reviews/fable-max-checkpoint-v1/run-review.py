#!/usr/bin/env python3
"""Feed one bounded read-only Fable Max CLI review without shell execution."""
import argparse
import datetime as dt
import hashlib
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
policy = Path(__file__).resolve().parent / "adversarial-objective-v1.md"
if not policy.is_file() or policy.is_symlink() or policy.stat().st_size > 12 * 1024:
    raise SystemExit("mandatory adversarial objective brief missing or over12KiB")
policy_bytes = policy.read_bytes()
prompt_bytes = prompt.read_bytes()
review_input = policy_bytes + b"\n\n--- CHECKPOINT EVIDENCE PACKET (DISPUTED CLAIMS) ---\n\n" + prompt_bytes
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
              "promptSha256": hashlib.sha256(prompt_bytes).hexdigest(),
              "objectiveBriefPath": str(policy.relative_to(repo)),
              "objectiveBriefSha256": hashlib.sha256(policy_bytes).hexdigest(),
              "reviewInputSha256": hashlib.sha256(review_input).hexdigest(),
              "startedAt": started, "readOnly": True, "nativeWorkPaused": True}
(args.out / "invocation.json").write_text(json.dumps(invocation, indent=2) + "\n")
result = subprocess.run(argv, cwd=repo, input=review_input, check=False)
terminal = {**invocation, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "exitCode": result.returncode}
(args.out / "terminal.json").write_text(json.dumps(terminal, indent=2) + "\n")
raise SystemExit(result.returncode)
