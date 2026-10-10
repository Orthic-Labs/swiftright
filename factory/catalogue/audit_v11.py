"""V11 duplicate-pair consumer layered over immutable v10."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Any

from factory.core import artifacts
from . import audit_v7, audit_v8

V10_AUDIT_HASH = "sha256:6bf159b5230c0e36f966ff779eaa9c79893a6564cf7bf2ae82b334f28ff78514"
V10_FILE_SHA256 = "sha256:37d6cfde0447da0602262a7304f4d32e3f31da34adc1e8d567c9768dfe5c8935"
V10_SOURCE_SHA256 = "sha256:ef45aa7df9f3656600bc00de1dd9511b3775d6ca4ce545394502d2a10de7beb4"
V10_TEST_SHA256 = "sha256:9a35af7a8ac584a52bc705c51a0977e875e6795e671f7353d5dca73e7ded4f59"
LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
DUPE_GUARD_SOURCE_SHA256 = "sha256:50fd8272beb8f6242a968b7ce2f36dfe1d81066570f782fc5b02bcd03a016001"
DUPE_GUARD_TEST_SHA256 = "sha256:7aad3332d4f139dd27a07d453acdf7bc98a964f6288b6b961504f177e5df7786"
DUPE_CAPTURE_SHA256 = "sha256:e7bdf26635be7ebbc17cdd4d37ba796e3a22cce249b4b5425ad84dda84fc6ffd"
DUPE_CANDIDATE_SHA256 = "sha256:23c4d70c6b29c078bc8bc4f824ee30b304b882f3beac7ebdeaf69281c2edbf3e"
DUPE_RECEIPTS_SHA256 = "sha256:04aed18e57ad16af0fa5f70d913f5fa806adee078a94b88d9c58f06e4ae8a2ba"
DUPE_HELPER_SHA256 = "sha256:1b6162a37294e9dda0c190552116a097c5ff4d42a9c84330b439274bef39e859"
DUPE_RAW_EVIDENCE_SHA256 = "sha256:5287ecdbd267d2d30196855233ee285914b7e6bb4c24e25dafa911386bb1c89f"
DUPE_USR_INPUT_SHA256 = "sha256:10e5d039bb22cc2ebeefcd1065b9d73426174651b7c0777b8534fc8ad98d684b"
DUPE_PROBE_SOURCE_SHA256 = "sha256:5855c068a23cb7690d57edc46897f75ed57f13e96839f8541fe755b5e468c6cd"
DUPE_BRANCH_OUTPUT_SHA256 = "sha256:ef91c3c3676eb785cd57326857f9f22eca63bda787220a2fb8d2780e4e5e6d4c"
DUPE_DEMANGLE_OUTPUT_SHA256 = "sha256:bb47e5aecbf8c2d81a415daae7570d0b7b121d48ffa657e738daab789066f64c"
LINES = (4080, 5533, 9717, 23750, 32822)


def _require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file() or artifacts.file_hash(path) != expected:
        raise ValueError(f"{label} bytes differ from frozen receipt")


def _load_v10(path: Path, *, root: Path) -> dict[str, Any]:
    _require_hash(root / "factory/catalogue/audit_v10.py", V10_SOURCE_SHA256, "v10 source")
    _require_hash(root / "factory/catalogue/test_audit_v10.py", V10_TEST_SHA256, "v10 test")
    _require_hash(path, V10_FILE_SHA256, "v10 candidate")
    value = json.loads(path.read_text(encoding="utf-8"))
    body = dict(value)
    declared_hash = body.pop("auditHash", None)
    if declared_hash != V10_AUDIT_HASH or artifacts.canonical_hash(body) != declared_hash:
        raise ValueError("v10 canonical audit hash differs from frozen snapshot")
    return value


@lru_cache(maxsize=1)
def _duplicate_guard():
    folder = Path(__file__).resolve().parent / "duplicate-identity-spike"
    helper_path = folder / "duplicate_identity_validator.py"
    source_path = folder / "exact_identity_candidate.py"
    _require_hash(helper_path, DUPE_HELPER_SHA256, "duplicate identity helper")
    _require_hash(source_path, DUPE_GUARD_SOURCE_SHA256, "duplicate identity guard")
    sys.path.insert(0, str(folder))
    try:
        spec = importlib.util.spec_from_file_location("_sr1_v11_duplicate_guard", source_path)
        if spec is None or spec.loader is None:
            raise ValueError("cannot load pinned duplicate identity guard")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(folder))


def _duplicate_input_paths(root: Path) -> dict[str, tuple[str, str]]:
    return {
        "factory/catalogue/compiler-cursor-spike/link-evidence.json": ("immutable compiler links", LINK_SHA256),
        "factory/catalogue/duplicate-identity-spike/exact_identity_candidate.py": ("duplicate guard", DUPE_GUARD_SOURCE_SHA256),
        "factory/catalogue/duplicate-identity-spike/test_exact_identity_candidate.py": ("duplicate guard test", DUPE_GUARD_TEST_SHA256),
        "factory/catalogue/duplicate-identity-spike/capture_exact_probes.py": ("probe capture source", DUPE_CAPTURE_SHA256),
        "factory/catalogue/duplicate-identity-spike/exact-identity-candidate.json": ("duplicate candidate", DUPE_CANDIDATE_SHA256),
        "factory/catalogue/duplicate-identity-spike/exact-probe-receipts.json": ("fresh probe receipts", DUPE_RECEIPTS_SHA256),
        "factory/catalogue/duplicate-identity-spike/duplicate_identity_validator.py": ("duplicate helper", DUPE_HELPER_SHA256),
        "factory/catalogue/duplicate-identity-spike/raw-record-evidence.json": ("raw record lineage", DUPE_RAW_EVIDENCE_SHA256),
        "factory/catalogue/duplicate-identity-spike/usr-input.txt": ("exact demangle USR input", DUPE_USR_INPUT_SHA256),
        "factory/catalogue/duplicate-identity-spike/tilde-sendable-probe.swift": ("compiler feature probe", DUPE_PROBE_SOURCE_SHA256),
        "factory/catalogue/duplicate-identity-spike/exact-branch.stdout": ("fresh compiler branch result", DUPE_BRANCH_OUTPUT_SHA256),
        "factory/catalogue/duplicate-identity-spike/exact-demangle.stdout": ("fresh compiler USR trees", DUPE_DEMANGLE_OUTPUT_SHA256),
    }


def _fresh_probe(guard, links: dict[str, Any], *, root: Path) -> dict[str, Any]:
    folder = Path(guard.HERE)
    receipt_path = folder / "exact-probe-receipts.json"
    receipts = json.loads(receipt_path.read_text(encoding="utf-8"))
    toolchain = links["toolchainEvidence"]
    compiler = Path(toolchain["compiler"]["driverPath"])
    expected_compile = receipts["compile"]["argv"]
    expected_args = [
        str(compiler), "-sdk", toolchain["sdk"], "-target", toolchain["target"],
        str(folder / "tilde-sendable-probe.swift"), "-o",
    ]
    if expected_compile[:-1] != expected_args or expected_compile[-1] != "<internal-temporary-probe>":
        raise ValueError("fresh branch compiler receipt has unexpected invocation")
    _require_hash(compiler, toolchain["compiler"]["sha256"], "live swiftc driver")
    version = subprocess.run([str(compiler), "--version"], check=True, capture_output=True, text=True)
    if (not version.stderr.startswith("swift-driver version: ") or "\n" in version.stderr
            or toolchain["compiler"]["version"].splitlines()[0] not in version.stdout
            or f"Target: {toolchain['target']}.0" not in version.stdout):
        raise ValueError("live swiftc version differs from pinned compiler receipt")
    with tempfile.TemporaryDirectory(prefix="sr1-v11-probe-", dir="/tmp") as temporary:
        executable = Path(temporary) / "condition-probe"
        compile_run = subprocess.run([*expected_args, str(executable)], check=False,
                                     capture_output=True, text=True)
        if compile_run.returncode != receipts["compile"]["exitCode"] or compile_run.stderr:
            raise ValueError("fresh feature-conditional probe compilation failed")
        branch_run = subprocess.run([str(executable)], check=False, capture_output=True, text=True)
        if branch_run.returncode != receipts["branch"]["exitCode"] or branch_run.stderr:
            raise ValueError("fresh feature-conditional probe execution failed")
    if branch_run.stdout.encode("utf-8") != (folder / "exact-branch.stdout").read_bytes():
        raise ValueError("fresh feature-conditional result differs from pinned branch output")
    usr_input = (folder / "usr-input.txt").read_bytes()
    candidate_rows = json.loads((folder / "exact-identity-candidate.json").read_text())["rows"]
    usrs = [row["usr"] for row in candidate_rows]
    expected_usr_input = "".join("$s" + usr[2:] + "\n" for usr in usrs).encode("utf-8")
    if usr_input != expected_usr_input:
        raise ValueError("fresh demangle input differs from exact duplicate USR set")
    demangler = compiler.with_name("swift-demangle")
    _require_hash(demangler, guard.PINS["demangleTool"], "live swift-demangle")
    demangle_args = [str(demangler), "--expand"]
    demangle = subprocess.run(demangle_args, input=usr_input, check=True, capture_output=True)
    if demangle.stderr or demangle.stdout != (folder / "exact-demangle.stdout").read_bytes():
        raise ValueError("fresh USR demangle output differs from pinned tree receipt")
    return {
        "compilerPath": str(compiler), "compilerSha256": toolchain["compiler"]["sha256"],
        "compilerVersionSha256": "sha256:" + hashlib.sha256((version.stdout + version.stderr).encode()).hexdigest(),
        "probeSourceSha256": artifacts.file_hash(folder / "tilde-sendable-probe.swift"),
        "compileStdoutSha256": "sha256:" + hashlib.sha256(compile_run.stdout.encode()).hexdigest(),
        "compileStderrSha256": "sha256:" + hashlib.sha256(compile_run.stderr.encode()).hexdigest(),
        "branchStdoutSha256": "sha256:" + hashlib.sha256(branch_run.stdout.encode()).hexdigest(),
        "branchStderrSha256": "sha256:" + hashlib.sha256(branch_run.stderr.encode()).hexdigest(),
        "branch": branch_run.stdout.strip(), "demanglerPath": str(demangler),
        "demanglerSha256": artifacts.file_hash(demangler),
        "demangleStdoutSha256": "sha256:" + hashlib.sha256(demangle.stdout).hexdigest(),
        "demangleStderrSha256": "sha256:" + hashlib.sha256(demangle.stderr).hexdigest(),
        "demangledUsrCount": len(usrs),
    }


def _validate_duplicate_rows(v10: dict[str, Any], *, root: Path) -> dict[str, Any]:
    for relative, (label, digest) in _duplicate_input_paths(root).items():
        _require_hash(root / relative, digest, label)
    guard = _duplicate_guard()
    candidate_path = root / "factory/catalogue/duplicate-identity-spike/exact-identity-candidate.json"
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    if (candidate.get("kind") != "duplicate-exact-identity-review-candidate" or candidate.get("version") != 2
            or candidate.get("status") != "review-only" or candidate.get("summary") != {
                "acceptedDuplicatePairs": 5, "faultControls": 120, "promotionsMade": 0}):
        raise ValueError("frozen duplicate candidate shape or review receipt changed")
    if candidate.get("pins") != guard.PINS or len(candidate.get("rows", [])) != 5:
        raise ValueError("duplicate candidate pins/rows differ from exact five-row freeze")
    for row in candidate["rows"]:
        controls = row.get("faultControls", {})
        if len(controls) < 24 or any(
            not item.get("rejected") or item.get("requiredReason") not in item.get("reasons", [])
            for item in controls.values()
        ):
            raise ValueError("duplicate candidate lacks nonvacuous semantic fault controls")

    links_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    links = json.loads(links_path.read_text(encoding="utf-8"))
    trust = guard.frozen()
    link_rows = {(row["module"], row["interface"], row["line"]): row for row in links["rows"]}
    response_path = root / "factory/catalogue/duplicate-identity-spike/sourcekit-index-output.txt"
    response_text = response_path.read_text(encoding="utf-8")
    request_path = root / "factory/catalogue/compiler-cursor-spike/request-index-interface.yaml"
    request_text = request_path.read_text(encoding="utf-8")
    source_text = guard.SOURCE.read_text(encoding="utf-8")
    candidate_by_line = {row["key"][2]: row for row in candidate["rows"]}
    if set(candidate_by_line) != set(LINES):
        raise ValueError("duplicate candidate row allowlist differs from five reviewed rows")
    live = _fresh_probe(guard, links, root=root)
    demangle_text = (Path(guard.HERE) / "exact-demangle.stdout").read_text(encoding="utf-8")
    if guard.digest_bytes(response_text.encode()) != guard.PINS["response"]:
        raise ValueError("fresh duplicate SourceKit response bytes differ from immutable input")
    if guard.digest_bytes(request_text.encode()) != guard.PINS["request"]:
        raise ValueError("duplicate SourceKit request bytes differ from immutable input")

    v10_by_line: dict[int, list[dict[str, Any]]] = {}
    for declaration in v10["declarations"]:
        if declaration.get("module") == "SwiftUI" and declaration.get("line") in LINES:
            v10_by_line.setdefault(declaration["line"], []).append(declaration)
    promotions = []
    for line in LINES:
        spec = trust["rows"].get(line)
        if spec is None:
            raise ValueError(f"duplicate identity guard lacks exact pinned row {line}")
        link = spec["link"]
        if link_rows.get(("SwiftUI", link["interface"], line)) != link:
            raise ValueError("duplicate guard row differs from immutable 836 link row")
        if (link.get("linkHoldReason") != "duplicate-raw-entity-records"
                or link.get("linkEligibility") is not False or link.get("kind") != "var"
                or link.get("sourceHash") != guard.PINS["source"]
                or link.get("signature") != candidate_by_line[line].get("signature")):
            raise ValueError("duplicate member is outside exact unresolved source-row allowlist")
        declarations = v10_by_line.get(line, [])
        if len(declarations) != 1:
            raise ValueError("duplicate row does not map uniquely to immutable v10 declaration")
        declaration = declarations[0]
        if (declaration.get("classification") != "active-compiler-conditional-unmapped"
                or declaration.get("sourceKitEvidence", {}).get("reason") != "multiple-public-exact-context-compiler-records"
                or declaration.get("interface") != link["interface"]
                or declaration.get("signature") != link["signature"]
                or declaration.get("context") != link["context"]
                or declaration.get("sourceKitEvidence", {}).get("interfaceSha256") != guard.PINS["source"]):
            raise ValueError("duplicate bridge does not join to exact v10 held declaration")
        parsed = [record for record in guard.reconstruct_response(response_text)
                  if record["entity"].get("line") == line]
        if len(parsed) != 2:
            raise ValueError("duplicate raw response cardinality differs from exact paired-record claim")
        usr = parsed[0]["entity"].get("usr")
        assessments = declaration.get("sourceKitEvidence", {}).get("rawCandidateAssessments", [])
        assessment_pair = [item for item in assessments if item.get("usr") == usr and item.get("line") == line]
        if len(assessment_pair) != 2 or any(
            item.get("kind") != parsed[0]["entity"].get("kind")
            or item.get("effectiveAccess") != parsed[0]["entity"].get("effective_access")
            or item.get("name") != parsed[0]["entity"].get("name")
            for item in assessment_pair
        ):
            raise ValueError("duplicate raw pair does not match exact sourcekit assessment multiplicity")
        context_condition = spec["lexical"]["conditions"]
        if not context_condition or context_condition[-1] != ["compiler(>=5.3) && $TildeSendable", True]:
            raise ValueError("duplicate row does not resolve to measured active conditional branch")
        scope = spec["lexical"]["scope"]
        if len(scope) != 1 or scope[0].get("kind") != "struct":
            raise ValueError("duplicate row does not have exact single nominal source scope")
        row = {
            "module": "SwiftUI", "sourceHash": guard.PINS["source"], "line": line,
            "kind": "var", "name": spec["name"], "context": link["context"],
            "sourceLine": spec["lexical"]["lineText"],
            "activeCondition": context_condition[-1][0], "activeBranch": context_condition[-1][1],
            "scopeName": scope[0]["name"], "scopeLine": scope[0]["line"],
            "auditRowKey": link["auditRowKey"], "signature": link["signature"],
            "key": ["SwiftUI", link["interface"], line, "var"],
        }
        records = [item["record"] for item in parsed]
        entities = [item["entity"] for item in parsed]
        validated = guard.validate_duplicate_identity(
            row, entities, records, source_text=source_text, source_sha256=guard.PINS["source"],
            request_text=request_text, request_sha256=guard.PINS["request"],
            expected_request_sha256=link["compilerEvidence"]["requestSha256"],
            response_sha256=guard.PINS["response"], expected_response_sha256=link["compilerEvidence"]["responseSha256"],
            demangle_text=demangle_text, toolchain=links["toolchainEvidence"],
            expected_toolchain=trust["toolchain"], source_path=str(guard.SOURCE),
            raw_response_text=response_text)
        if not validated.get("accepted"):
            raise ValueError(f"duplicate identity production guard rejected line {line}: {validated.get('reasons')}")
        claim = candidate_by_line[line]
        positions = [{key: item[key] for key in ("startByte", "endByte")} for item in parsed]
        if (claim.get("key") != row["key"] or claim.get("auditRowKey") != row["auditRowKey"]
                or claim.get("signature") != row["signature"] or claim.get("usr") != usr
                or claim.get("sourceReconstruction") != spec["lexical"]
                or claim.get("rawPositions") != positions or claim.get("validator") != validated):
            raise ValueError("candidate duplicate row differs from independently replayed raw source and USR proof")
        promotions.append({"declaration": declaration, "link": link, "row": row,
                           "entities": entities, "records": records, "usr": usr,
                           "candidate": claim,
                           "validationArgs": {
                               "row": row, "raw_entities": entities, "raw_records": records,
                               "source_text": source_text, "source_sha256": guard.PINS["source"],
                               "request_text": request_text, "request_sha256": guard.PINS["request"],
                               "expected_request_sha256": link["compilerEvidence"]["requestSha256"],
                               "response_sha256": guard.PINS["response"],
                               "expected_response_sha256": link["compilerEvidence"]["responseSha256"],
                               "demangle_text": demangle_text,
                               "toolchain": links["toolchainEvidence"], "expected_toolchain": trust["toolchain"],
                               "source_path": str(guard.SOURCE), "raw_response_text": response_text,
                           }})
    return {"promotions": promotions, "liveProbe": live,
            "candidatePath": candidate_path, "guardPath": Path(guard.__file__),
            "pins": guard.PINS}


def build_audit_v11(v10_path: Path, *, root: Path) -> dict[str, Any]:
    root = Path(root)
    v10 = _load_v10(Path(v10_path), root=root)
    duplicate = _validate_duplicate_rows(v10, root=root)
    declarations = copy.deepcopy(v10["declarations"])
    v7 = audit_v8._load_pinned_v7(root / "factory/catalogue/evidence/interface-audit-v7.json")
    catalogue_path = root / v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogue"]
    if artifacts.file_hash(catalogue_path) != v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogueHash"]:
        raise ValueError("v7-pinned symbol catalogue bytes changed")
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))
    graph_by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in catalogue.get("symbols", []):
        if symbol.get("usr") != symbol.get("precise"):
            raise ValueError("pinned symbol catalogue has inconsistent USR/precise fields")
        graph_by_usr.setdefault(str(symbol["usr"]), []).append(symbol)

    present = absent = 0
    for entry in duplicate["promotions"]:
        declaration = entry["declaration"]
        target = next(row for row in declarations if (
            row.get("module"), row.get("interface"), row.get("line"), row.get("signature"), tuple(row.get("context", []))) == (
            declaration.get("module"), declaration.get("interface"), declaration.get("line"),
            declaration.get("signature"), tuple(declaration.get("context", []))))
        usr = entry["usr"]
        matches = graph_by_usr.get(usr, [])
        target["symbol"] = {"usr": usr, "source": "SourceKit duplicate records + exact paired-record compiler guard"}
        target["sourceKitEvidence"].pop("reason", None)
        target["sourceKitEvidence"]["compilerUsr"] = usr
        target["sourceKitEvidence"]["symbolGraphMatches"] = matches
        target["sourceKitEvidence"]["duplicateIdentityBridge"] = {
            "path": str(duplicate["candidatePath"].relative_to(root)),
            "sha256": DUPE_CANDIDATE_SHA256, "guardSha256": DUPE_GUARD_SOURCE_SHA256,
            "helperSha256": DUPE_HELPER_SHA256, "sourceHash": entry["row"]["sourceHash"],
            "rawPairCount": len(entry["records"]), "rawRecordSha256": entry["records"][0]["sha256"],
            "rawEntitySha256": artifacts.canonical_hash(entry["entities"][0]),
            "activeCondition": entry["row"]["activeCondition"],
            "activeBranch": entry["row"]["activeBranch"], "scopeName": entry["row"]["scopeName"],
            "scopeLine": entry["row"]["scopeLine"], "liveProbe": duplicate["liveProbe"],
        }
        target["classification"] = ("matched-sourcekit-usr-in-symbolgraph" if matches
                                     else "matched-sourcekit-usr-absent-from-symbolgraph")
        present += int(bool(matches))
        absent += int(not matches)

    from collections import Counter
    counts = Counter(row["classification"] for row in declarations)
    held_reasons = Counter(row.get("sourceKitEvidence", {}).get("reason") for row in declarations
                           if row.get("classification") in audit_v8.RESIDUAL_CLASSIFICATIONS
                           and row.get("sourceKitEvidence", {}).get("reason"))
    remaining = sum(counts[name] for name in audit_v8.RESIDUAL_CLASSIFICATIONS)
    payload = copy.deepcopy(v10)
    payload.pop("auditHash", None)
    payload.update({
        "version": 11,
        "status": "incomplete-v11-duplicate-identities-validated-inactive-branch-pending",
        "method": v10["method"] + " V11 adds five exact paired SourceKit records only after live compiler conditional proof, byte-identical raw-record parsing, public access, owner-tree, request, toolchain, and USR revalidation.",
        "parentAudit": {"path": str(Path(v10_path).relative_to(root)), "fileSha256": V10_FILE_SHA256,
                        "auditHash": V10_AUDIT_HASH},
        "declarations": declarations,
        "summary": {
            **v10["summary"],
            "newlyPromotedRows": v10["summary"]["newlyPromotedRows"] + len(duplicate["promotions"]),
            "exactSourceKitUsrLinks": v10["summary"]["exactSourceKitUsrLinks"] + len(duplicate["promotions"]),
            "heldSourceKitRows": v10["summary"]["heldSourceKitRows"] - len(duplicate["promotions"]),
            "sourceKitUsrPresentInSymbolGraph": v10["summary"]["sourceKitUsrPresentInSymbolGraph"] + present,
            "sourceKitUsrAbsentFromSymbolGraph": v10["summary"]["sourceKitUsrAbsentFromSymbolGraph"] + absent,
            "heldSourceKitReasons": dict(sorted(held_reasons.items())),
            "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
            "byClassification": dict(sorted(counts.items())),
        },
        "duplicateIdentityBridgeEvidence": {
            "path": str(duplicate["candidatePath"].relative_to(root)),
            "sha256": DUPE_CANDIDATE_SHA256, "guardSha256": DUPE_GUARD_SOURCE_SHA256,
            "helperSha256": DUPE_HELPER_SHA256, "probeReceiptsSha256": DUPE_RECEIPTS_SHA256,
            "promotedRows": len(duplicate["promotions"]), "faultControls": 120,
            "state": "consumer-validated",
        },
        "freshCompilerProbe": duplicate["liveProbe"],
        "pendingEvidence": [{"kind": "compiler-proven-inactive-interface-conditional",
                              "path": "factory/catalogue/inactive-branch-spike",
                              "expectedRows": remaining, "state": "awaiting independent review; row remains unresolved"}],
    })
    input_hashes = [{"path": str(Path(v10_path).relative_to(root)), "hash": V10_FILE_SHA256},
                    {"path": "factory/catalogue/audit_v10.py", "hash": V10_SOURCE_SHA256},
                    {"path": "factory/catalogue/test_audit_v10.py", "hash": V10_TEST_SHA256}]
    input_hashes.extend({"path": path, "hash": digest} for path, (_label, digest)
                        in _duplicate_input_paths(root).items())
    input_hashes.append({"path": "factory/catalogue/audit_v11.py", "hash": artifacts.file_hash(Path(__file__))})
    payload["provenance"] = artifacts.provenance(V10_AUDIT_HASH, input_hashes,
        producer="sr1-factory.catalogue.audit-v11-candidate")
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    candidate = build_audit_v11(root / "factory/catalogue/evidence/interface-audit-v10-candidate.json", root=root)
    artifacts.write_artifact(root / "factory/catalogue/evidence/interface-audit-v11-candidate.json", candidate)


if __name__ == "__main__":
    main()
