"""Strict r14 issued/run/memory lineage joins for adapter v10."""
from __future__ import annotations

import re
from pathlib import Path

from bounded_io_v9 import bounded_json, verify_ref

EXPECTED_RUN_ID = "01acb1d24a04471fa5709dac1c4a73c5"
EXPECTED_ISSUED_SHA256 = "sha256:7216cd29266556cff4fec9a214f4bd5b403218db27d2007edc90823334e500e6"
JOB_MEMORY_LIMIT = 1073741824
JOB_MEMORY_FLAGS = 0x200

def canonical_hash(value):
    if not isinstance(value, str):
        raise ValueError("lineage hash missing")
    candidate = value if value.startswith("sha256:") else "sha256:" + value
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", candidate):
        raise ValueError("lineage hash malformed")
    return candidate


def require_plan_lineage(plan: dict) -> dict:
    lineage = plan.get("issuedLineage")
    if not isinstance(lineage, dict) or not re.fullmatch(r"[0-9a-f]{32}", str(lineage.get("runID"))):
        raise ValueError("r14 issued lineage plan binding missing")
    canonical_hash(lineage.get("issuedMetadataSha256"))
    return lineage


def _integer(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def validate_memory_receipt(task: dict, plan: dict) -> dict:
    lineage = require_plan_lineage(plan)
    if task.get("status") != "completed-source-bound-observation" or canonical_hash(task.get("issuedMetadataHash")) != lineage["issuedMetadataSha256"]:
        raise ValueError("task result issued lineage mismatch")
    receipt = task.get("memoryReceipt")
    if not isinstance(receipt, dict) or receipt.get("kind") != "factory-interactive-job-memory-receipt-v1" or receipt.get("status") != "passed":
        raise ValueError("memory receipt not admitted")
    if receipt.get("runID") != lineage["runID"] or canonical_hash(receipt.get("issuedMetadataHash")) != lineage["issuedMetadataSha256"]:
        raise ValueError("memory receipt nonce/hash mismatch")
    if receipt.get("jobMemoryLimitBytes") != JOB_MEMORY_LIMIT or receipt.get("limitFlags") != JOB_MEMORY_FLAGS or receipt.get("activeProcessCount") != 1 or receipt.get("killOnJobClose") is not False:
        raise ValueError("memory receipt cap/active-process proof mismatch")
    peak = receipt.get("peakJobMemoryUsedBytes")
    if not _integer(peak) or peak < 0 or peak > JOB_MEMORY_LIMIT:
        raise ValueError("memory receipt peak exceeds admitted cap")
    if not _integer(receipt.get("parentPid")) or receipt["parentPid"] <= 0:
        raise ValueError("memory receipt parent PID missing")
    return {"runID": lineage["runID"], "issuedMetadataHash": lineage["issuedMetadataSha256"], "jobMemoryLimitBytes": JOB_MEMORY_LIMIT, "limitFlags": JOB_MEMORY_FLAGS, "peakJobMemoryUsedBytes": peak, "activeProcessCount": 1, "killOnJobClose": False}


def validate_document_lineage(document: dict, root: Path, plan: dict) -> dict:
    lineage = require_plan_lineage(plan)
    roles = document.get("roles")
    if not isinstance(roles, dict):
        raise ValueError("adapter roles missing")
    issued_ref = roles.get("issuedMetadata")
    task_ref = roles.get("taskResult")
    if not isinstance(issued_ref, dict) or not isinstance(task_ref, dict):
        raise ValueError("issued metadata/task result refs required")
    issued_path = root / issued_ref["path"]
    verify_ref(issued_path, issued_ref, max_bytes=2 * 1024 * 1024)
    if issued_ref.get("sha256") != lineage["issuedMetadataSha256"]:
        raise ValueError("issued metadata reference hash mismatch")
    issued = bounded_json(issued_path)
    if issued.get("runID") != lineage["runID"] or issued.get("expectedCount") != 20 or issued.get("frozenTupleBound") is not False:
        raise ValueError("issued metadata run/count/boundary mismatch")
    task_path = root / task_ref["path"]
    verify_ref(task_path, task_ref, max_bytes=2 * 1024 * 1024)
    task = bounded_json(task_path)
    memory = validate_memory_receipt(task, plan)
    return {"runID": lineage["runID"], "issuedMetadataHash": lineage["issuedMetadataSha256"], "memoryReceipt": memory}

