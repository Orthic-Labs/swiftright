#!/usr/bin/env python3
"""Source-only Count20 adapter packer.

Stages one fresh profile package from an admitted Count1 r5 package, a checked
Count1 coordinator certificate, and explicit Count20 lifecycle sources. It does
not execute PowerShell, native hosts, compilers, locks, or remote commands.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, stat, sys, zipfile
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
R5 = HERE.parent / "mta-pilot-stage-v1"
sys.path.insert(0, str(R5))
# Import bounded source helpers only; importing this module has no effects.
from stage_mta_count1_r5 import (MAX_FILES, MAX_FILE_BYTES, MAX_TOTAL_BYTES,
    HEX64, fail, regular, read_bytes, stream_hash, safe_rel, json_load,
    json_dump, copy_explicit, load_manifest, sha_file, reseal_candidate_graph,
    RELEASE_HELPER_SOURCE, RELEASE_HELPER_REL)

# V7 donor carries root-v3 cleanup in both renderer & MTA-worker roles. Keep
# this measured helper; older mta-stage v2 helper is not admissible here.
V7_WORKER_HELPER_SHA256 = "cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13"
V7_WORKER_HELPER_BYTES = 11288
V7_RENDERER_EXIT_SHA256 = "94db73dadfaa998fe63eefc5e7ce416310fe9072cd2fd09689f2f923f81538b4"
V7_RENDERER_EXIT_BYTES = 8684
V7_WORKER_EXIT_SHA256 = "78b9edaf1b72c389f3c026a6c1e1606505568803bfe3ad67ae1e66416809475d"
V7_WORKER_EXIT_BYTES = 12293

LIFECYCLE_FILES = (
    "coordinator-count20-lifecycle-v1.ps1",
    "dispatch-rectangle-count20-v1.ps1",
    "interactive-task-rectangle-count20-v1.ps1",
    "capture-rectangle-count20-v1.ps1",
    "all-owned-release-rectangle-r1.ps1",
    "uia-worker-invoke-v2.ps1",
    "Sr0OwnedJobProcess-v15.cs",
)


def ptoken(text: str, replacements: list[tuple[str, str]]) -> str:
    out = text
    for old, new in sorted(replacements, key=lambda x: len(x[0]), reverse=True):
        if old == new:
            continue
        # Require complete path/name tokens; this prevents r1->r10 damage.
        # Keep replacement literal; Windows path backslashes are not regex
        # replacement escapes.
        out = re.sub(r"(?<![A-Za-z0-9_.-])" + re.escape(old) + r"(?![A-Za-z0-9_.-])", lambda _match, value=new: value, out)
    return out


def transform(path: Path, replacements: list[tuple[str, str]]) -> None:
    raw = read_bytes(path)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return
    new = ptoken(text, replacements)
    if new == text:
        return
    enc = new.encode("utf-8")
    if len(enc) > MAX_FILE_BYTES:
        fail(f"transformed lifecycle source exceeds bound: {path}")
    tmp = path.with_name(path.name + ".replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"replacement collision: {tmp}")
    with tmp.open("xb") as fh:
        fh.write(enc)
    os.replace(tmp, path)


def replace_literals(path: Path, replacements: list[tuple[str, str]]) -> None:
    """Replace complete source tokens inside fresh staged files only."""
    raw = read_bytes(path)
    text = raw.decode("utf-8")
    updated = text
    for old, new in replacements:
        updated = updated.replace(old, new)
    if updated == text:
        return
    encoded = updated.encode("utf-8")
    if len(encoded) > MAX_FILE_BYTES:
        fail(f"literal-rebound source exceeds bound: {path}")
    tmp = path.with_name(path.name + ".literal-replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"replacement collision: {tmp}")
    with tmp.open("xb") as fh:
        fh.write(encoded)
    os.replace(tmp, path)


def verify_certificate(path: Path, digest: str, byte_count: int) -> dict[str, Any]:
    if not HEX64.fullmatch(digest.lower()):
        fail("--count1-certificate-sha256 must be 64 lowercase hex")
    got, size = sha_file(path)
    if got != digest.lower() or size != byte_count:
        fail("Count1 certificate hash/byte pin mismatch")
    cert = json_load(path)
    if not isinstance(cert, dict):
        fail("Count1 certificate must be JSON object")
    # Certificate is an actual successful original coordinator result. Reject
    # preflight, synthetic, failed, or missing parent/lock lineage.
    if cert.get("count") != 1:
        fail("Count1 certificate count must be 1")
    if cert.get("status") not in ("completed-source-bound-observation", "completed"):
        fail("Count1 certificate is not successful")
    for key in ("lockReleased", "wholeBatchExitConfirmed"):
        if cert.get(key) is not True:
            fail(f"Count1 certificate missing {key}=true")
    parent = cert.get("taskParentProof") or cert.get("parentProof")
    if not isinstance(parent, dict) or parent.get("kernelWait") not in (0,):
        fail("Count1 certificate missing original-parent kernel proof")
    if not isinstance(cert.get("runRoot"), str) or not cert["runRoot"]:
        fail("Count1 certificate missing runRoot")
    for key in ("sourceInputsHash", "issuedMetadataHash", "compileReceiptHash", "exeHash"):
        value = cert.get(key)
        if not isinstance(value, str) or not HEX64.fullmatch(value.lower()):
            fail(f"Count1 certificate missing measured {key}")
    cert["_sourceRef"] = {"sha256": digest.lower(), "bytes": size, "path": path.as_posix()}
    return cert


def copy_stage(donor: Path, out: Path, manifest: dict[str, Any]) -> None:
    for row in manifest["files"]:
        rel = safe_rel(row["path"])
        copy_explicit(donor / rel, out / rel)


def verify_count1_v7_closure(stage: Path) -> None:
    """Keep admitted Count1 V7 cleanup/wait contract intact before adaptation."""
    lifecycle = []
    for name in ("coordinator-count1-v3.ps1", "dispatch-text-single-v3.ps1",
                 "capture-text-single-v3.ps1", "interactive-task-text-single-v3.ps1",
                 "all-owned-release-text-r1.ps1"):
        p = stage / "overlay" / name
        if not p.is_file() or p.is_symlink():
            fail(f"admitted Count1 V7 source missing: {p}")
        text = read_bytes(p).decode("utf-8")
        if "FactoryProcessWaitV5" in text:
            fail(f"stale V5 process-wait caller: {name}")
        lifecycle.append(text)
    if not any("FactoryProcessWaitV6" in text for text in lifecycle):
        fail("V6 process-wait helper call absent from admitted Count1 closure")
    for rel in ("producer/support/cleanup.ps1",
                "producer/dependencies/uia-worker/support/cleanup.ps1"):
        p = stage / rel
        if not p.is_file() or p.is_symlink():
            fail(f"root-v3 cleanup role missing: {p}")


def replace_fresh(src: Path, dst: Path) -> None:
    """Replace one already-staged donor row inside this fresh output only."""
    regular(src, MAX_FILE_BYTES)
    if not dst.exists() or dst.is_symlink():
        fail(f"expected staged lifecycle target missing: {dst}")
    tmp = dst.with_name(dst.name + ".lifecycle-replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"lifecycle replacement collision: {tmp}")
    copy_explicit(src, tmp)
    os.replace(tmp, dst)


def copy_lifecycle(root: Path, stage: Path, profile: str, token: str) -> None:
    for name in LIFECYCLE_FILES:
        src = root / name
        if not src.is_file() or src.is_symlink():
            fail(f"missing lifecycle source: {src}")
        # Keep profile donor's capture implementation as source of truth. The
        # lifecycle copy only supplies Count20 orchestration.
        target_name = name.replace("rectangle", profile)
        dst = stage / "overlay" / target_name
        if dst.exists():
            replace_fresh(src, dst)
        else:
            copy_explicit(src, dst)
    # Adapt exact admitted profile capture; lifecycle donor supplies batch
    # orchestration, never another profile's capture body.
    donor_capture = stage / "overlay" / f"capture-{profile}-single-v3.ps1"
    if not donor_capture.exists():
        donor_capture = stage / "overlay" / f"capture-{profile}-single-v2.ps1"
    if not donor_capture.exists():
        fail(f"profile capture source missing for {profile}")
    profile_c20 = stage / "overlay" / f"capture-{profile}-count20-v1.ps1"
    if profile_c20.exists():
        replace_fresh(donor_capture, profile_c20)
    else:
        copy_explicit(donor_capture, profile_c20)
    # Bounded semantic edits, preserving profile body. Exact Count1 literals
    # are changed only in Count20 parameter/identity checks.
    raw = read_bytes(profile_c20).decode("utf-8")
    raw = raw.replace("[ValidateSet(1)]", "[ValidateSet(1,20)]")
    raw = raw.replace("Count1", "Count20").replace("count1", "count20")
    raw = raw.replace("$Count=1", "$Count=20")
    raw = raw.replace("$outputPath 1 $CompileReceiptHash", "$outputPath $Count $CompileReceiptHash")
    raw = raw.replace("$sourceDocument.count -ne 1", "$sourceDocument.count -ne $Count")
    raw = raw.replace("$sourceDocument.kind -cne 'factory-text-source-inputs-v1'", "$sourceDocument.kind -notin @('factory-text-source-inputs-v1','factory-text-source-inputs-v2')")
    raw = raw.replace("$sourceDocument.kind -cne 'factory-circle-source-inputs-v1'", "$sourceDocument.kind -notin @('factory-circle-source-inputs-v1','factory-circle-source-inputs-v2')")
    # Donor dispatch can retain rectangle source-kind tokens after Count20
    # adaptation. Rebind only these complete semantic tokens per profile;
    # never perform substring/count-wide replacement.
    source_kinds = {
        "text": ("factory-text-source-inputs-v1", "factory-text-source-inputs-v2"),
        "circle": ("factory-circle-source-inputs-v1", "factory-circle-source-inputs-v2"),
    }[profile]
    raw = raw.replace("factory-rectangle-source-inputs-v1", source_kinds[0])
    raw = raw.replace("factory-rectangle-source-inputs-v2", source_kinds[1])
    raw = raw.replace("factory-rectangle-capture-dispatch-count", f"factory-{profile}-capture-dispatch-count")
    # Only the batch-wide issued capture list scales to Count20.  Keep
    # per-run allocation uniqueness at exactly one identity.
    batch_count = "@($issuedMetadata.captures).Count -ne 1"
    if raw.count(batch_count) != 1:
        fail("Count20 capture batch-count expression is not uniquely pinned")
    raw = raw.replace(batch_count, "@($issuedMetadata.captures).Count -ne $Count", 1)
    raw = raw.replace("$_.run -ne 1", "$_.run -lt 1 -or $_.run -gt $Count")
    if "$allocated.Count -ne 1" not in raw:
        fail("Count20 per-run allocation uniqueness guard changed")
    enc = raw.encode("utf-8")
    if len(enc) > MAX_FILE_BYTES:
        fail("profile Count20 capture exceeds bound")
    # Replace staged donor copy only inside this fresh stage; donor stays
    # immutable & failed writes leave evidence instead of deleting anything.
    tmp = profile_c20.with_name(profile_c20.name + ".count20-replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"Count20 capture replacement collision: {tmp}")
    with tmp.open("xb") as fh:
        fh.write(enc)
    os.replace(tmp, profile_c20)


def verify_no_v5_closure(stage: Path) -> None:
    """Reject stale process-wait callers across final Count20 PowerShell."""
    for p in sorted(stage.rglob("*.ps1")):
        if p.is_symlink():
            fail(f"symlinked PowerShell source: {p}")
        text = read_bytes(p).decode("utf-8", errors="strict")
        if "FactoryProcessWaitV5" in text:
            fail(f"stale V5 process-wait caller in final Count20 closure: {p.relative_to(stage)}")


def repair_profile_external_paths(stage: Path, profile: str) -> None:
    """Keep profile's measured rolling host roots in preflight/source refs.

    Text Count1's successful compiler package, receipt and serializer control
    live under hosts\text-baseline. Donor lifecycle packets historically carry
    an unused Rectangle serializer path; rebind only that exact external role
    before graph reseal, while preserving serializer bytes/hash.
    """
    if profile != "text":
        return
    stale_paths = (
        r"D:\Claude\swiftright\.factory-work\hosts\rectangle\dependencies\serializer-actual-r2\control.json",
        r"D:\Claude\swiftright\.factory-work\hosts\text\dependencies\serializer-actual-r2\control.json",
    )
    new = r"D:\Claude\swiftright\.factory-work\hosts\text-baseline\dependencies\serializer-actual-r2\control.json"
    preflight = stage / "overlay" / "capture-build-preflight.ps1"
    if not preflight.is_file() or preflight.is_symlink():
        fail("Text build preflight source missing")
    raw = read_bytes(preflight).decode("utf-8")
    matches = [candidate for candidate in stale_paths if raw.count(candidate) == 1]
    if len(matches) == 1 and raw.count(new) == 0:
        old = matches[0]
    elif len(matches) == 0 and raw.count(new) == 1:
        old = new
    else:
        fail("Text serializer preflight donor path is not uniquely pinned")
    if old != new:
        updated = raw.replace(old, new)
        tmp = preflight.with_name(preflight.name + ".text-root-replace")
        if tmp.exists() or tmp.is_symlink():
            fail("Text preflight replacement collision")
        with tmp.open("xb") as fh:
            fh.write(updated.encode("utf-8"))
        os.replace(tmp, preflight)
    source_path = stage / "admission" / "source-inputs.json"
    source = json_load(source_path)
    serializer = source.get("serializerRef")
    if not isinstance(serializer, dict) or serializer.get("path") not in (*stale_paths, new):
        fail("Text serializer source ref is not exact donor path")
    serializer["path"] = new
    json_dump(source_path, source)


def adapt_count20_fault_seed(stage: Path) -> None:
    """Keep Count20 valid baseline while retaining invalid-count fault control."""
    p = stage / "overlay" / "test-profile-integration.ps1"
    if not p.is_file() or p.is_symlink():
        fail("profile integration control missing")
    raw = read_bytes(p).decode("utf-8")
    old = "if($n -ceq 'count'){$bad.$n=20}"
    if raw.count(old) != 1:
        fail("Count20 integration fault seed is not exact Count1 form")
    # Count20 source is valid at 20; mutation must be 21 so control still
    # rejects it without weakening production Count20 admission.
    new = "if($n -ceq 'count'){$bad.$n=21}"
    raw = raw.replace(old, new)
    tmp = p.with_name(p.name + ".count20-replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"replacement collision: {tmp}")
    with tmp.open("xb") as fh:
        fh.write(raw.encode("utf-8"))
    os.replace(tmp, p)


def reseal_binding(stage: Path) -> tuple[str, int]:
    path = stage / "producer" / "integration-bindings.json"
    binding = json_load(path)
    rows = binding.get("files") if isinstance(binding, dict) else None
    if not isinstance(rows, list) or not rows:
        fail("integration bindings missing")
    seen: set[str] = set()
    for row in rows:
        rel = row.get("path") if isinstance(row, dict) else None
        if not isinstance(rel, str) or rel in seen:
            fail("integration binding row invalid")
        seen.add(rel); safe_rel(rel)
        src = stage / "overlay" / rel
        if not src.exists():
            src = stage / "producer" / rel
        if src.exists():
            row["sha256"], row["bytes"] = sha_file(src)
    json_dump(path, binding)
    return sha_file(path)


def refresh_local_identity_refs(stage: Path, si: dict[str, Any]) -> None:
    """Refresh hashes for transformed local producer/overlay roles."""
    local_hashes = {
        "buildPreflightHash": stage / "overlay" / "capture-build-preflight.ps1",
        "capturePlanHash": stage / "producer" / "capture-plan.json",
        "integrationBindingsHash": stage / "producer" / "integration-bindings.json",
        "workerContractHash": stage / "producer" / "dependencies" / "uia-worker" / "worker-contract.json",
        "uiaWorkerHash": stage / "producer" / "dependencies" / "uia-worker" / "invoke-worker-mta.ps1",
        "workerReleaseHelperHash": stage / RELEASE_HELPER_REL,
    }
    for field, path in local_hashes.items():
        if not path.is_file() or path.is_symlink():
            fail(f"transformed local identity role missing: {field}")
        digest, size = sha_file(path)
        si[field] = digest
        if field == "integrationBindingsHash":
            ref = si.get("integrationBindingsRef")
        elif field == "capturePlanHash":
            ref = si.get("capturePlanRef")
        elif field == "buildPreflightHash":
            ref = None
        else:
            ref = None
        if isinstance(ref, dict):
            ref["sha256"] = "sha256:" + digest
            ref["bytes"] = size


def overlay_rows(stage: Path) -> list[dict[str, Any]]:
    rows = []
    for p in sorted((stage / "overlay").rglob("*")):
        if not p.is_file() or p.name == "stage-manifest.json":
            continue
        rel = p.relative_to(stage / "overlay").as_posix()
        digest, size = sha_file(p)
        rows.append({"path": rel, "bytes": size, "sha256": digest})
    return rows


def make_manifest(stage: Path, profile: str, cert: dict[str, Any]) -> dict[str, Any]:
    worker_helper = stage / "producer/dependencies/uia-worker/support/final-exit-certificate.ps1"
    if not worker_helper.is_file() or worker_helper.is_symlink():
        fail("prospective v2 worker release helper missing")
    helper_hash, helper_bytes = sha_file(worker_helper)
    expected_helper_hash, expected_helper_bytes = V7_WORKER_EXIT_SHA256, V7_WORKER_EXIT_BYTES
    if helper_hash != expected_helper_hash or helper_bytes != expected_helper_bytes:
        fail("worker release helper is not prospective v2")
    rows=[]; total=0
    for p in sorted(stage.rglob("*")):
        if not p.is_file() or p.name == "stage-manifest.json":
            continue
        rel=p.relative_to(stage).as_posix(); safe_rel(rel)
        digest,size=sha_file(p); rows.append({"path":rel,"bytes":size,"sha256":digest}); total+=size
    if len(rows)>MAX_FILES or total>MAX_TOTAL_BYTES: fail(f"Count20 stage bounds exceeded: {len(rows)} files/{total} bytes")
    return {"kind":f"factory-{profile}-mta-count20-stage-v1","count":20,"compilerActions":0,
      "count1Certificate":cert["_sourceRef"],"files":rows,
      "limits":{"maxFiles":MAX_FILES,"maxFileBytes":MAX_FILE_BYTES,"maxTotalBytes":MAX_TOTAL_BYTES},
      "lifecycle":{"setupSeconds":180,"nativeWindowSeconds":30,"nativeExitSeconds":15,"captureSeconds":600,"cleanupSeconds":60,"outerSeconds":840,"schedulerMinutes":15},
      "mtaControlPaths":["overlay/final-exit-certificate-mta-v1.ps1","overlay/test-mta-config-admission.ps1","overlay/test-uia-mta-controls.ps1"],
      "workerPath":"producer/dependencies/uia-worker/invoke-worker-mta.ps1",
      "rendererHelperPath":"producer/support/final-exit-certificate.ps1",
      "workerHelperPath":"producer/dependencies/uia-worker/support/final-exit-certificate.ps1",
      "workerHelperConfigKind":"factory-uia-snapshot-worker-config-v2",
      "workerHelperSha256":helper_hash,
      "workerHelperBytes":helper_bytes,
      "cleanupHelperPaths":["producer/support/cleanup.ps1","producer/dependencies/uia-worker/support/cleanup.ps1"],
      "cleanupHelperSha256":V7_WORKER_HELPER_SHA256,
      "cleanupHelperBytes":V7_WORKER_HELPER_BYTES}


def make_installer(profile: str, namespace: str, package_sha: str, cert_ref: dict[str, Any], source_inputs_sha: str, template_sha: str) -> str:
    # Installer accepts package path at invocation; no Mac absolute path is
    # embedded. It creates no runRoot: capture requires fresh absent root.
    guard=f"integration-fresh-{profile}-v1.ps1"
    worker_helper_sha = V7_WORKER_EXIT_SHA256
    issue=f"issue-{profile}-metadata-v1.ps1"
    dispatch=f"dispatch-{profile}-count20-v1.ps1"
    coordinator="coordinator-count20-lifecycle-v1.ps1"
    temp_root = (
        r"D:\Claude\swiftright\.factory-work\hosts\circle"
        if profile == "circle"
        else r"D:\Claude\swiftright\.factory-work\hosts\text-baseline"
    )
    return f'''param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip=$PackagePath;$zipSha256='{package_sha}';$templateSha256='{template_sha}';$count1CertificateSha256='{cert_ref["sha256"]}';$count1CertificateBytes={cert_ref["bytes"]}
$temp='{temp_root}\\{namespace}\\count20-r10\\package';$namespaceRoot='D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{namespace}';$control=Join-Path $namespaceRoot 'control-count20-r10';$producerRoot=Join-Path $namespaceRoot 'producer-count20-r10';$admissionRoot=Join-Path $namespaceRoot 'admission-count20-r10';$overlayRoot=Join-Path $namespaceRoot 'overlay-count20-r10';$outputRoot=Join-Path $namespaceRoot 'native';$runRoot=Join-Path $outputRoot 'count20-r10'
if(-not(Test-Path -LiteralPath $zip -PathType Leaf)){{throw 'package missing'}};if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne $zipSha256){{throw 'package hash drift'}};if((Test-Path -LiteralPath $temp) -or (Test-Path -LiteralPath $namespaceRoot)){{throw 'fresh destination collision'}}
Expand-Archive -LiteralPath $zip -DestinationPath $temp;$m=Get-Content -Raw -LiteralPath (Join-Path $temp 'stage-manifest.json')|ConvertFrom-Json
foreach($row in $m.files){{$f=Join-Path $temp $row.path;$i=Get-Item -LiteralPath $f -Force;if($i.Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){{throw ('stage drift '+$row.path)}}}}
foreach($s in @(Get-ChildItem -LiteralPath $temp -Filter '*.ps1' -File -Recurse)){{$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($s.FullName,[ref]$tokens,[ref]$errors)|Out-Null;if($null -ne $errors -and $errors.Count -gt 0){{throw ('PowerShell parse failure '+$s.FullName+': '+[string]$errors[0])}}}}
$cert=Join-Path $temp 'admission/count1-certificate.json';$ci=Get-Item -LiteralPath $cert -Force;if($ci.Length -ne $count1CertificateBytes -or (Get-FileHash $cert).Hash.ToLowerInvariant() -cne $count1CertificateSha256){{throw 'Count1 certificate drift'}};$c1=Get-Content -Raw -LiteralPath $cert|ConvertFrom-Json;if($c1.count -ne 1 -or $c1.status -notin @('completed','completed-source-bound-observation') -or $c1.lockReleased -ne $true -or $c1.wholeBatchExitConfirmed -ne $true){{throw 'Count1 certificate not successful'}};$parent=$c1.taskParentProof;if($null -eq $parent -or $parent.kernelWait -ne 0){{throw 'Count1 original-parent kernel proof missing'}};foreach($k in @('sourceInputsHash','issuedMetadataHash','compileReceiptHash','exeHash')){{if(([string]$c1.$k) -notmatch '^[0-9a-f]{{64}}$'){{throw ('Count1 measured lineage missing '+$k)}}}}
New-Item -ItemType Directory -Path $namespaceRoot,$control,$producerRoot,$admissionRoot,$overlayRoot,$outputRoot -ErrorAction Stop|Out-Null
Copy-Item (Join-Path $temp 'producer\\*') $producerRoot -Recurse;Copy-Item (Join-Path $temp 'admission\\*') $admissionRoot -Recurse;Copy-Item (Join-Path $temp 'overlay\\*') $overlayRoot -Recurse
$source=Join-Path $admissionRoot 'source-inputs.json';if((Get-FileHash $source).Hash.ToLowerInvariant() -cne '{source_inputs_sha}'){{throw 'source-inputs hash drift'}}
$mta=Join-Path $producerRoot 'dependencies\\uia-worker\\invoke-worker-mta.ps1';$contract=Join-Path $producerRoot 'dependencies\\uia-worker\\worker-contract.json';$renderer=Join-Path $producerRoot 'support\\final-exit-certificate.ps1';$worker=Join-Path $producerRoot 'dependencies\\uia-worker\\support\\final-exit-certificate.ps1';$rendererCleanup=Join-Path $producerRoot 'support\\cleanup.ps1';$workerCleanup=Join-Path $producerRoot 'dependencies\\uia-worker\\support\\cleanup.ps1';foreach($f in @($mta,$contract,$renderer,$worker,$rendererCleanup,$workerCleanup)){{if(-not(Test-Path $f -PathType Leaf)){{throw 'required worker/renderer cleanup closure missing'}}}};if((Get-Item -LiteralPath $renderer).Length -ne 8684 -or (Get-FileHash $renderer).Hash.ToLowerInvariant() -cne '{V7_RENDERER_EXIT_SHA256}'){{throw 'renderer final-exit helper drift'}};if((Get-Item -LiteralPath $worker).Length -ne 12293 -or (Get-FileHash $worker).Hash.ToLowerInvariant() -cne '{V7_WORKER_EXIT_SHA256}'){{throw 'worker final-exit helper drift'}};foreach($f in @($rendererCleanup,$workerCleanup)){{if((Get-Item -LiteralPath $f).Length -ne 11288 -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne '{V7_WORKER_HELPER_SHA256}'){{throw 'root-v3 cleanup helper drift'}}}}
$overlayRows=@(Get-ChildItem -LiteralPath $overlayRoot -File -Recurse|ForEach-Object{{$rel=$_.FullName.Substring($overlayRoot.Length).TrimStart('\\');[ordered]@{{path=$rel.Replace('\\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}}}})
$mtaConfigControl=Join-Path $overlayRoot 'test-mta-config-admission.ps1';$uiaMtaControl=Join-Path $overlayRoot 'test-uia-mta-controls.ps1';foreach($f in @($mtaConfigControl,$uiaMtaControl,(Join-Path $overlayRoot 'final-exit-certificate-mta-v1.ps1'))){{if(-not(Test-Path -LiteralPath $f -PathType Leaf)){{throw ('MTA control source missing '+$f)}}}};& $mtaConfigControl -OutputPath (Join-Path $control 'mta-config-controls.json');& $uiaMtaControl -WorkerPath (Join-Path $producerRoot 'dependencies/uia-worker/worker.ps1') -InvokerPath $mta -SchemaPath (Join-Path $producerRoot 'dependencies/uia-worker/schema.ps1')|Set-Content (Join-Path $control 'uia-mta-controls.json') -Encoding UTF8
$si=Get-Content -Raw -LiteralPath $source|ConvertFrom-Json;$wc=Get-Content -Raw -LiteralPath $contract|ConvertFrom-Json;if(-not $wc.sourceBindings -or @($wc.sourceBindings|Where-Object{{$_.path.Replace('\\','/') -ceq 'invoke-worker-mta.ps1'}}).Count -ne 1){{throw 'worker contract MTA binding missing'}};$guard=Join-Path $overlayRoot '{guard}';. $guard;& (Join-Path $overlayRoot 'test-profile-integration.ps1') -GuardPath $guard -Root $producerRoot -SourceInputsPath $source|Set-Content (Join-Path $control 'integration-controls.json') -Encoding UTF8;Assert-FactoryIntegrationSources $producerRoot $si|Out-Null
# Fresh output run root is intentionally absent until dispatch/capture owns it.
$issueArgs=@{{Count=20;SourceInputsPath=$source;SourceInputsHash='{source_inputs_sha}';OutputPath=(Join-Path $admissionRoot 'issued-metadata.json');RunRoot=$runRoot;PlanPath=$si.planRef.path;PlanHash=$si.planHash;CompileReceiptPath=$si.compileRef.path;CompileReceiptHash=$si.compileReceiptHash;ExePath=$si.exeRef.path;ExeHash=$si.exeHash;RendererPath=$si.rendererRef.path;RendererHash=$si.rendererSha256;SerializerPath=$si.serializerRef.path;SerializerHash=$si.serializerControlSha256;TuplePath=$si.tupleRef.path;TupleHash=$si.tupleHash;BindingPath=$si.bindingRef.path;BindingHash=$si.bindingHash;RecipePath=$si.recipeRef.path;RecipeHash=$si.recipeHash}};& (Join-Path $overlayRoot '{issue}') @issueArgs
$issued=Join-Path $admissionRoot 'issued-metadata.json';$issuedHash=(Get-FileHash $issued).Hash.ToLowerInvariant();$cfg=[ordered]@{{admissionRoot=$admissionRoot;compileReceiptHash=$si.compileReceiptHash;controlRoot=$control;count=20;exeHash=$si.exeHash;integrationGuardHash=(Get-FileHash $guard).Hash.ToLowerInvariant();integrationGuardPath=$guard;issuedMetadataHash=$issuedHash;issuedMetadataPath=$issued;outputRoot=$outputRoot;overlayRoot=$overlayRoot;owner='pending-root-lock';package=$si.compiledHostPackagePath;producerRoot=$producerRoot;runRoot=$runRoot;serializerControlSha256=$si.serializerControlSha256;sourceInputsHash='{source_inputs_sha}';sourceInputsPath=$source;sourceBindings=$overlayRows;count1Certificate=$c1}}
$cfgPath=Join-Path $control 'config-template.json';$cfg|ConvertTo-Json -Depth 32|Set-Content $cfgPath -Encoding UTF8;$cfgHash=(Get-FileHash $cfgPath).Hash.ToLowerInvariant();& (Join-Path $overlayRoot '{coordinator}') -Template $cfgPath -TemplateHash $cfgHash -PreflightOnly
[ordered]@{{status='source-count20-preflight-passed';profile='{profile}';count=20;packageSha256=$zipSha256;count1CertificateSha256=$count1CertificateSha256;sourceInputsHash='{source_inputs_sha}';nativeActions=0;lockActions=0;compilerActions=0}}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $control 'package-preflight.json') -Encoding UTF8
'''


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--profile", choices=("text","circle"), required=True)
    ap.add_argument("--donor-root", type=Path, required=True, help="fresh admitted Count1 r5 stage root")
    ap.add_argument("--count1-certificate", type=Path, required=True)
    ap.add_argument("--count1-certificate-sha256", required=True)
    ap.add_argument("--count1-certificate-bytes", type=int, required=True)
    ap.add_argument("--lifecycle-root", type=Path, required=True)
    ap.add_argument("--output-root", type=Path, required=True)
    ap.add_argument("--output-zip", type=Path, required=True)
    ap.add_argument("--output-installer", type=Path, required=True)
    ap.add_argument("--namespace", required=True)
    ap.add_argument("--old-namespace")
    args=ap.parse_args()
    donor=args.donor_root.resolve(); cert_path=args.count1_certificate.resolve(); life=args.lifecycle_root.resolve(); out=args.output_root
    for p in (out,args.output_zip,args.output_installer):
        if p.exists() or p.is_symlink(): fail(f"fresh output collision: {p}")
    if not donor.is_dir() or not life.is_dir(): fail("donor/lifecycle root missing")
    cert=verify_certificate(cert_path,args.count1_certificate_sha256,args.count1_certificate_bytes)
    manifest=load_manifest(donor); donor_si=json_load(donor/'admission/source-inputs.json')
    old_ns=args.old_namespace
    if not old_ns:
        for value in (donor_si.get('capturePlanPath'), donor_si.get('bindingRef',{}).get('path')):
            if isinstance(value,str):
                m=re.search(r"[\\/]\.work[\\/]([^\\/]+)",value,re.I)
                if m: old_ns=m.group(1); break
    if not old_ns: fail("cannot derive donor namespace; pass --old-namespace")
    out.mkdir(parents=True)
    copy_stage(donor,out,manifest)
    verify_count1_v7_closure(out)
    copy_explicit(cert_path,out/'admission/count1-certificate.json')
    replacements=[(old_ns,args.namespace),("admission-count1-r5","admission-count20-r10"),("producer-count1-r5","producer-count20-r10"),("overlay-count1-r5","overlay-count20-r10"),("control-count1-r5","control-count20-r10"),("native\\count1-r5","native\\count20-r10"),("native/count1-r5","native/count20-r10"),("count1-r5","count20-r10"),("rectangle","profile-token"),("Rectangle","ProfileToken")]
    # Donor profile sources retain their own names; only namespace/count tokens
    # are rewritten first. Lifecycle files get a second controlled profile map.
    for p in sorted(out.rglob('*')):
        if p.is_file() and p.name not in ('stage-manifest.json','count1-certificate.json'):
            transform(p,replacements[:-2])
    copy_lifecycle(life,out,args.profile,args.namespace)
    adapt_count20_fault_seed(out)
    profile_repl=[("rectangle",args.profile),("Rectangle",args.profile.title()),("RECTANGLE",args.profile.upper()),("count20-r4","count20-r10")]
    for name in LIFECYCLE_FILES:
        p=out/'overlay'/name.replace('rectangle',args.profile)
        if p.exists(): transform(p,profile_repl)
    # Transform profile Count20 capture references to newly named script.
    for p in sorted((out/'overlay').glob('*.ps1')):
        if p.name.startswith('capture-') or p.name.startswith('dispatch-') or p.name.startswith('interactive-') or p.name.startswith('coordinator-') or p.name.startswith('all-owned-release-'):
            transform(p,[("rectangle",args.profile),("Rectangle",args.profile.title())])
    # Rebind exact lifecycle filenames inside every fresh overlay script. The
    # coordinator is profile-neutral, while dispatch/interactive/capture/
    # release children are profile-specific.
    filename_repl = [
        ("dispatch-rectangle-count20-v1.ps1", f"dispatch-{args.profile}-count20-v1.ps1"),
        ("interactive-task-rectangle-count20-v1.ps1", f"interactive-task-{args.profile}-count20-v1.ps1"),
        ("capture-rectangle-count20-v1.ps1", f"capture-{args.profile}-count20-v1.ps1"),
        ("all-owned-release-rectangle-r1.ps1", f"all-owned-release-{args.profile}-r1.ps1"),
    ]
    for p in sorted((out/'overlay').glob('*.ps1')):
        transform(p, filename_repl)
        replace_literals(p, [
            ("factory-rectangle-source-inputs-v1", f"factory-{args.profile}-source-inputs-v1"),
            ("factory-rectangle-source-inputs-v2", f"factory-{args.profile}-source-inputs-v2"),
            ("factory-rectangle-capture-dispatch-count", f"factory-{args.profile}-capture-dispatch-count"),
        ])
        text = read_bytes(p).decode("utf-8", errors="strict")
        for stale, _fresh in filename_repl:
            if stale in text:
                fail(f"stale lifecycle filename reference: {p.name}: {stale}")
        if p.name.startswith(("capture-", "dispatch-", "interactive-", "coordinator-", "all-owned-release-")):
            stale_kinds = ("factory-rectangle-source-inputs-v1", "factory-rectangle-source-inputs-v2")
            stale_dispatch = "factory-rectangle-capture-dispatch-count"
            if any(token in text for token in (*stale_kinds, stale_dispatch)):
                fail(f"stale rectangle semantic token in {p.name}")
    # Count20 namespace/lifecycle transforms alter tuple/context/binding bytes.
    # Repair measured Text serializer roots before graph/source-input reseal.
    # Lifecycle donor may still carry old V5 references; transform only fresh
    # output copies, then require complete V6 closure.
    for p in sorted(out.rglob('*.ps1')):
        replace_literals(p, [("FactoryProcessWaitV5", "FactoryProcessWaitV6")])
    verify_no_v5_closure(out)
    repair_profile_external_paths(out, args.profile)
    # Reseal graph edges before source-inputs and overlay lineage are emitted.
    reseal_candidate_graph(out)
    # Existing profile input docs retain profile semantics; only dynamic count,
    # namespace, and certificate lineage are changed.
    si_path=out/'admission/source-inputs.json'; si=json_load(si_path)
    si['kind']=f"factory-{args.profile}-source-inputs-v2"; si['count']=20; si['stagingStatus']='source-count20-staged-pending-root-measured-receipts'; si['count1CertificateRef']={'path':'admission/count1-certificate.json','sha256':'sha256:'+args.count1_certificate_sha256.lower(),'bytes':args.count1_certificate_bytes}
    si['count1CertificateHash']=args.count1_certificate_sha256.lower(); si['count1CertificateBytes']=args.count1_certificate_bytes; si['stagingNamespace']=args.namespace
    helper_hash, helper_bytes = sha_file(out / RELEASE_HELPER_REL)
    si['workerReleaseHelperHash'] = helper_hash
    si['workerReleaseHelperBytes'] = helper_bytes
    json_dump(si_path,si)
    reseal_binding(out)
    si=json_load(si_path)
    refresh_local_identity_refs(out, si)
    # Update overlay refs after adding lifecycle sources, with exact hashes.
    si['overlaySourceBindings']=overlay_rows(out); si['overlaySourceBindingsHash']=hashlib.sha256(json.dumps(si['overlaySourceBindings'],sort_keys=True,separators=(',',':')).encode()).hexdigest(); json_dump(si_path,si)
    source_sha,source_bytes=sha_file(si_path)
    manifest_out=make_manifest(out,args.profile,cert); json_dump(out/'stage-manifest.json',manifest_out)
    args.output_zip.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(args.output_zip,'x',compression=zipfile.ZIP_DEFLATED) as zf:
        for row in manifest_out['files']+[{'path':'stage-manifest.json'}]: zf.write(out/row['path'],row['path'])
    zip_sha,zip_bytes=sha_file(args.output_zip)
    # Template hash is donor plan template, not an execution claim.
    template_sha=sha_file(donor/'stage-manifest.json')[0]
    installer=make_installer(args.profile,args.namespace,zip_sha,cert['_sourceRef'],source_sha,template_sha)
    with args.output_installer.open('xb') as fh: fh.write(installer.encode())
    inst_sha,inst_bytes=sha_file(args.output_installer)
    receipt={'kind':'factory-mta-count20-stage-v1','profile':args.profile,'namespace':args.namespace,'donorRoot':str(donor),'lifecycleRoot':str(life),'count1Certificate':cert['_sourceRef'],'stageRoot':str(out),'stageFileCount':len(manifest_out['files']),'stageTotalBytes':sum(r['bytes'] for r in manifest_out['files']),'sourceInputsHash':source_sha,'sourceInputsBytes':source_bytes,'packageSha256':zip_sha,'packageBytes':zip_bytes,'installerSha256':inst_sha,'installerBytes':inst_bytes,'status':'source-only-pending-root-transport-preflight','nativeActions':0,'lockActions':0,'compilerActions':0}
    json_dump(args.output_zip.with_suffix(args.output_zip.suffix+'.receipt.json'),receipt)
    print(json.dumps(receipt,indent=2)); return 0

if __name__=='__main__': raise SystemExit(main())
