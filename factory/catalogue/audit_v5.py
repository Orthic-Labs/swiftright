"""Reconcile conditional declarations using a recorded compiler execution."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path
from typing import Any, Iterable

from factory.core.artifacts import canonical_hash, file_hash
from .audit_v2 import audit_v2

_CONDITION = "compiler(>=5.3) && $TildeSendable"
_ELSE_CONDITION = f"else({_CONDITION})"
_EXPLICIT_EXCLUSIONS = {"hidden-attribute", "excluded-target-availability"}


def _normalized_target(value: str) -> str:
    return value.replace("-macosx", "-macos")


def _load_probe(path: Path, target: str | None) -> dict[str, Any]:
    evidence = json.loads(path.read_text(encoding="utf-8"))
    claimed_hash = evidence.get("evidenceHash")
    unhashed = dict(evidence)
    unhashed.pop("evidenceHash", None)
    if not claimed_hash or canonical_hash(unhashed) != claimed_hash:
        raise ValueError("compiler conditional probe evidence hash is invalid")
    if evidence.get("kind") != "swift-compiler-conditional-probe" or evidence.get("condition") != _CONDITION:
        raise ValueError("probe evidence does not test the required TildeSendable condition")
    runs = evidence.get("targetRuns", [])
    by_target = {_normalized_target(run.get("target", "")): run for run in runs}
    required_targets = {"arm64-apple-macos27.0", "arm64e-apple-macos27.0"}
    if not required_targets.issubset(by_target):
        raise ValueError("conditional probe lacks exact arm64 & arm64e catalogue target runs")
    source_argument = str(Path(evidence["source"]["path"]).resolve())
    selected_branches: set[str] = set()
    for run in runs:
        if run.get("compile", {}).get("returnCode") != 0 or run.get("execution", {}).get("returnCode") != 0:
            raise ValueError("compiler conditional probe did not compile and execute successfully")
        stdout = run.get("execution", {}).get("stdout")
        observed = {"selected=tilde-sendable": "tilde-sendable", "selected=else": "else"}.get((stdout or "").strip())
        stdout_hash = "sha256:" + hashlib.sha256((stdout or "").encode()).hexdigest()
        if not observed or observed != run.get("selectedBranch") or stdout_hash != run.get("execution", {}).get("stdoutByteSha256"):
            raise ValueError("probe stdout bytes do not prove one selected branch")
        argv = run.get("compile", {}).get("argv", [])
        if ("-sdk" not in argv or argv[argv.index("-sdk") + 1] != evidence.get("sdk") or
                "-target" not in argv or argv[argv.index("-target") + 1] != run.get("target") or
                source_argument not in argv):
            raise ValueError("probe compile arguments do not bind target, SDK, & source")
        selected_branches.add(observed)
        binary = Path(run["execution"]["argv"][0])
        if binary.exists() and file_hash(binary) != run["execution"]["binarySha256"]:
            raise ValueError("executed probe binary hash does not match probe evidence")
    if len(selected_branches) != 1:
        raise ValueError("arm64 & arm64e compiler probes disagree on conditional branch")
    observed = next(iter(selected_branches))
    if observed != evidence.get("selectedBranch"):
        raise ValueError("combined selected branch does not match target probe outputs")
    if evidence.get("inactiveBranch") != ("else" if observed == "tilde-sendable" else "tilde-sendable"):
        raise ValueError("probe inactive branch does not match observed compiler output")
    if target and _normalized_target(target) not in by_target:
        raise ValueError("probe evidence does not include symbolgraph target")
    source = Path(evidence["source"]["path"])
    if not source.is_absolute():
        source = Path.cwd() / source
    source_bytes = source.read_bytes()
    if file_hash(source) != evidence["source"]["sha256"] or source_bytes.decode() != evidence["source"].get("content"):
        raise ValueError("compiler probe source hash does not match current source")
    compiler = Path(evidence["toolchain"]["swiftc"])
    if file_hash(compiler) != evidence["toolchain"]["swiftcSha256"]:
        raise ValueError("compiler binary hash does not match probe evidence")
    return evidence


def apply_probe_result(audit: dict[str, Any], evidence: dict[str, Any], evidence_path: str) -> dict[str, Any]:
    """Annotate exact probe branches without converting them into hidden rows."""
    selected = evidence["selectedBranch"]
    rows = audit["declarations"]
    annotated = {"active": 0, "inactive": 0}
    for row in rows:
        conditions = row.get("conditions", [])
        has_active = _CONDITION in conditions
        has_inactive = _ELSE_CONDITION in conditions
        if has_active == has_inactive:
            continue
        if has_active:
            branch = "active" if selected == "tilde-sendable" else "inactive"
        else:
            branch = "inactive" if selected == "tilde-sendable" else "active"
        annotated[branch] += 1
        row["conditionalResolution"] = {
            "condition": _CONDITION,
            "branch": branch,
            "otherConditions": [condition for condition in conditions if condition not in {_CONDITION, _ELSE_CONDITION}],
            "evidenceHash": evidence["evidenceHash"],
        }
        if row["classification"] in _EXPLICIT_EXCLUSIONS:
            continue
        if branch == "inactive":
            row["priorClassification"] = row["classification"]
            if "symbol" in row:
                row["priorSymbol"] = row.pop("symbol")
            if "candidates" in row:
                row["priorCandidates"] = row.pop("candidates")
                row["priorCandidateCount"] = row.pop("candidateCount", None)
            row["classification"] = "inactive-compiler-conditional"
        elif row["classification"] == "unresolved-conditional":
            row["classification"] = "active-compiler-conditional-unmapped"

    counts: dict[str, int] = {}
    for row in rows:
        category = row["classification"]
        counts[category] = counts.get(category, 0) + 1
    audit["version"] = 5
    audit["status"] = "incomplete-context-signature-audit" if any(
        name in counts for name in ("unexplained", "unresolved-conditional", "active-compiler-conditional-unmapped", "ambiguous-context-signature")
    ) else "complete"
    audit["method"] += " Exact `compiler(>=5.3) && $TildeSendable` branch availability is derived from a separately hashed compile-and-run probe; inactive rows are not hidden or counted as API matches."
    audit["compilerConditionalEvidence"] = {
        "path": evidence_path,
        "evidenceHash": evidence["evidenceHash"],
        "condition": evidence["condition"],
        "targets": [run["target"] for run in evidence["targetRuns"]],
        "selectedBranch": evidence["selectedBranch"],
        "inactiveBranch": evidence["inactiveBranch"],
        "targetRunStdout": {run["target"]: run["execution"]["stdout"] for run in evidence["targetRuns"]},
        "targetRunStdoutByteSha256": {run["target"]: run["execution"]["stdoutByteSha256"] for run in evidence["targetRuns"]},
        "sourceSha256": evidence["source"]["sha256"],
        "compilerSha256": evidence["toolchain"]["swiftcSha256"],
    }
    audit["summary"]["byClassification"] = dict(sorted(counts.items()))
    audit["summary"]["compilerConditionalRows"] = annotated
    audit.pop("auditHash", None)
    audit["auditHash"] = canonical_hash(audit)
    return audit


def audit_v5(interface_paths: Iterable[Path], graph_paths: Iterable[Path], *, probe_evidence_path: Path,
              symbolgraph_target: str | None = None, comparison_graph_paths: Iterable[Path] = ()) -> dict[str, Any]:
    evidence = _load_probe(Path(probe_evidence_path), symbolgraph_target)
    audit = audit_v2(interface_paths, graph_paths, symbolgraph_target=symbolgraph_target,
                     comparison_graph_paths=comparison_graph_paths, version=5)
    return apply_probe_result(audit, evidence, str(probe_evidence_path))
