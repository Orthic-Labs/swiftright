#!/usr/bin/env python3
"""Bounded source-only r4 -> r5 MTA staging packer.

It consumes only stage-manifest rows from an explicit frozen donor. It never
launches PowerShell, Python workers, compilers, or native hosts.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, stat, zipfile
from pathlib import Path
from typing import Any

MAX_FILES = 256
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024
HEX64 = re.compile(r"^[0-9a-f]{64}$")
REPO_ROOT = Path(__file__).resolve().parents[4]
MTA_CONTROL_ROOT = (REPO_ROOT / "factory/native/windows/pilot-rectangle-fixed-root-v2"
                    / "capture-count1-r12-sources/overlay")
MTA_CONTROL_FILES = (
    "final-exit-certificate-mta-v1.ps1",
    "test-mta-config-admission.ps1",
    "test-uia-mta-controls.ps1",
)
RELEASE_HELPER_SOURCE = (REPO_ROOT / "factory/pipeline/pilot-next-source-v1"
                         / "mta-release-diagnosis-r1/final-exit-certificate-v2.ps1")
RELEASE_HELPER_REL = Path("producer/dependencies/uia-worker/support/final-exit-certificate.ps1")


def fail(msg: str) -> None:
    raise SystemExit("mta-stage: " + msg)


def regular(path: Path, limit: int) -> os.stat_result:
    try:
        st = path.lstat()
    except OSError as exc:
        fail(f"cannot stat {path}: {exc}")
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        fail(f"non-regular or symlink input: {path}")
    if st.st_size > limit:
        fail(f"file exceeds {limit} bytes: {path} ({st.st_size})")
    return st


def read_bytes(path: Path, limit: int = MAX_FILE_BYTES) -> bytes:
    st = regular(path, limit)
    with path.open("rb") as fh:
        data = fh.read(limit + 1)
    if len(data) != st.st_size or len(data) > limit:
        fail(f"file changed or exceeds bound while reading: {path}")
    return data


def stream_hash(path: Path, limit: int = MAX_FILE_BYTES) -> tuple[str, int]:
    st = regular(path, limit)
    h = hashlib.sha256(); total = 0
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                fail(f"file grew beyond bound: {path}")
            h.update(chunk)
    if total != st.st_size:
        fail(f"file changed while hashing: {path}")
    return h.hexdigest(), total


def safe_rel(raw: str) -> Path:
    p = Path(raw)
    if not raw or p.is_absolute() or "\\" in raw or any(x in ("", ".", "..") for x in p.parts):
        fail(f"unsafe relative path: {raw!r}")
    return p


def json_load(path: Path) -> Any:
    data = read_bytes(path)
    try:
        return json.loads(data.decode("utf-8-sig"))
    except Exception as exc:
        fail(f"invalid JSON {path}: {exc}")


def json_dump(path: Path, obj: Any) -> None:
    text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    encoded = text.encode("utf-8")
    if len(encoded) > MAX_FILE_BYTES:
        fail(f"generated JSON exceeds bound: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        if path.is_symlink():
            fail(f"refusing symlink rewrite: {path}")
        tmp = path.with_name(path.name + ".rewrite")
        if tmp.exists() or tmp.is_symlink():
            fail(f"rewrite collision: {tmp}")
        with tmp.open("xb") as fh:
            fh.write(encoded)
        os.replace(tmp, path)
    else:
        with path.open("xb") as fh:
            fh.write(encoded)


def sha_file(path: Path) -> tuple[str, int]:
    return stream_hash(path)


def copy_explicit(src: Path, dst: Path) -> None:
    st = regular(src, MAX_FILE_BYTES)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        fail(f"fresh output collision: {dst}")
    with src.open("rb") as rf, dst.open("xb") as wf:
        total = 0
        while True:
            chunk = rf.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_FILE_BYTES:
                fail(f"source grew beyond bound: {src}")
            wf.write(chunk)
    if total != st.st_size:
        fail(f"source changed while copying: {src}")


def path_token_replace(text: str, replacements: list[tuple[str, str]]) -> str:
    """Replace exact supplied path tokens, longest first; no substring edits."""
    out = text
    for old, new in sorted(replacements, key=lambda x: len(x[0]), reverse=True):
        if not old or old == new:
            continue
        # Path tokens are bounded by path punctuation or string boundaries.
        pat = re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(old) + r"(?![A-Za-z0-9_.-])")
        # Replacement is literal: Windows paths may contain backslashes such
        # as ``\capture`` which regex replacement syntax would reinterpret.
        out, count = pat.subn(lambda _match, value=new: value, out)
        if count and count < 0:
            fail("replacement accounting failure")
    return out


def text_transform(path: Path, replacements: list[tuple[str, str]]) -> None:
    raw = read_bytes(path)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return
    transformed = path_token_replace(text, replacements)
    if transformed != text:
        tmp = path.with_name(path.name + ".replace")
        if tmp.exists():
            fail(f"replacement collision: {tmp}")
        data = transformed.encode("utf-8")
        if len(data) > MAX_FILE_BYTES:
            fail(f"transformed file exceeds bound: {path}")
        with tmp.open("xb") as fh:
            fh.write(data)
        os.replace(tmp, path)


def load_manifest(root: Path) -> dict[str, Any]:
    manifest_path = root / "stage-manifest.json"
    m = json_load(manifest_path)
    rows = m.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > MAX_FILES:
        fail("donor stage manifest has invalid file count")
    seen: set[str] = set(); total = 0
    for row in rows:
        rel = row.get("path") if isinstance(row, dict) else None
        if not isinstance(rel, str) or rel in seen:
            fail("donor stage manifest has duplicate/invalid path")
        safe_rel(rel); seen.add(rel)
        src = root / rel
        st = regular(src, MAX_FILE_BYTES)
        expected = row.get("bytes")
        if expected != st.st_size:
            fail(f"donor row byte mismatch: {rel}")
        if not isinstance(row.get("sha256"), str) or not HEX64.fullmatch(row["sha256"].lower()):
            fail(f"donor row hash invalid: {rel}")
        got, _ = sha_file(src)
        if got != row["sha256"].lower():
            fail(f"donor row hash mismatch: {rel}")
        total += st.st_size
    if total > MAX_TOTAL_BYTES:
        fail("donor stage exceeds 32 MiB")
    return m


def find_namespace(si: dict[str, Any]) -> str:
    probes = [si.get("capturePlanPath"), si.get("bindingRef", {}).get("path"), si.get("contextRef", {}).get("path")]
    for p in probes:
        if isinstance(p, str):
            hit = re.search(r"[\\/]\.work[\\/]([^\\/]+)", p, re.I)
            if hit:
                return hit.group(1)
    fail("cannot derive donor namespace")


def update_binding_file(stage: Path, profile: str) -> dict[str, Any]:
    p = stage / "producer" / "integration-bindings.json"
    binding = json_load(p)
    rows = binding.get("files")
    if not isinstance(rows, list) or not rows:
        fail("integration bindings has no files")
    seen = set(); mta = False
    for row in rows:
        rel = row.get("path") if isinstance(row, dict) else None
        if not isinstance(rel, str) or rel in seen:
            fail("invalid integration binding row")
        seen.add(rel); safe_rel(rel)
        local = stage / "producer" / rel
        if not local.exists():
            # Some bindings deliberately point at a support path outside producer;
            # those remain external and must be preserved for root admission.
            continue
        digest, size = sha_file(local)
        row["sha256"] = digest; row["bytes"] = size
        if rel.replace("\\", "/") == "dependencies/uia-worker/invoke-worker-mta.ps1":
            mta = True
    if not mta:
        fail("MTA worker binding missing")
    # Reseal worker contract against staged bytes before manifest/source-input
    # hashes are emitted. Renderer and worker helpers remain separate roles.
    contract_path = stage / "producer" / "dependencies/uia-worker/worker-contract.json"
    contract = json_load(contract_path)
    contract_rows = contract.get("sourceBindings") if isinstance(contract, dict) else None
    if not isinstance(contract_rows, list) or not contract_rows:
        fail("worker contract sourceBindings missing")
    contract_mta = False
    for row in contract_rows:
        rel = row.get("path") if isinstance(row, dict) else None
        if not isinstance(rel, str):
            fail("worker contract binding path missing")
        safe_rel(rel)
        local = contract_path.parent / rel
        if not local.exists():
            fail(f"worker contract source missing: {rel}")
        digest, size = sha_file(local)
        row["sha256"] = digest; row["bytes"] = size
        if rel.replace("\\", "/") == "invoke-worker-mta.ps1":
            contract_mta = True
    if not contract_mta:
        fail("worker contract is not MTA-bound")
    json_dump(contract_path, contract)
    for row in rows:
        if row.get("path") == "dependencies/uia-worker/worker-contract.json":
            digest, size = sha_file(contract_path)
            row["sha256"] = digest; row["bytes"] = size
    # Renderer & worker certificates must remain distinct producer roles.
    renderer = next((r for r in rows if r.get("path") == "support/final-exit-certificate.ps1"), None)
    worker = next((r for r in rows if r.get("path") == "dependencies/uia-worker/support/final-exit-certificate.ps1"), None)
    if not renderer or not worker or renderer.get("sha256") == worker.get("sha256"):
        fail("renderer/worker final-exit helpers are not distinct")
    json_dump(p, binding)
    return binding


def update_source_inputs(stage: Path, profile: str, namespace: str, roots: dict[str, str]) -> tuple[dict[str, Any], str, int]:
    p = stage / "admission" / "source-inputs.json"
    si = json_load(p)
    if not isinstance(si, dict):
        fail("source-inputs must be object")
    si["kind"] = f"factory-{profile}-source-inputs-v1"
    si["count"] = 1
    # Fresh local refs point into installer-created producer/admission/overlay roots.
    local_map = {
        "bindingRef": "admission/candidate-binding.json",
        "contextRef": "admission/context.json",
        "tupleRef": "admission/candidate-tuple.json",
        "recipeRef": "admission/recipe.json",
        "integrationBindingsRef": "producer/integration-bindings.json",
        "buildPreflightPath": "overlay/capture-build-preflight.ps1",
        "capturePlanPath": "producer/capture-plan.json",
        "uiaWorkerPath": "producer/dependencies/uia-worker/invoke-worker-mta.ps1",
    }
    # Hash/bytes all local refs after transformations, while retaining external
    # receipt/executable/runtime refs supplied by donor for root to validate.
    for field, rel in local_map.items():
        local = stage / rel
        if field.endswith("Ref"):
            if not local.exists():
                fail(f"missing source input {field}: {rel}")
            digest, size = sha_file(local)
            old = si.get(field) if isinstance(si.get(field), dict) else {}
            si[field] = {"bytes": size, "path": f"{roots[field] if field in roots else rel}", "sha256": "sha256:" + digest}
            # Preserve explicit source field aliases used by issuers.
            alias = field[:-3] + "Hash"
            if alias in si:
                si[alias] = digest
        else:
            digest, _ = sha_file(local)
            if field == "buildPreflightPath":
                si["buildPreflightHash"] = digest
                if field in roots:
                    si[field] = roots[field]
            elif field == "capturePlanPath":
                si["capturePlanHash"] = digest
                if field in roots:
                    si[field] = roots[field]
    # Canonical local fields used by existing guards.
    integ = json_load(stage / "producer" / "integration-bindings.json")
    idig, ibytes = sha_file(stage / "producer" / "integration-bindings.json")
    si["integrationBindingsHash"] = idig
    si["integrationBindingsRef"] = {"bytes": ibytes, "path": roots["integrationBindingsRef"], "sha256": "sha256:" + idig}
    udig, ubytes = sha_file(stage / "producer" / "dependencies/uia-worker/invoke-worker-mta.ps1")
    si["uiaWorkerHash"] = udig; si["uiaWorkerPath"] = roots["uiaWorkerPath"]
    si["workerContractHash"] = sha_file(stage / "producer" / "dependencies/uia-worker/worker-contract.json")[0]
    hdig, hbytes = sha_file(stage / RELEASE_HELPER_REL)
    si["workerReleaseHelperHash"] = hdig
    si["workerReleaseHelperPath"] = roots.get("workerReleaseHelperPath", RELEASE_HELPER_REL.as_posix())
    # Mark dynamic issuer binding explicitly; no native admission implied.
    si["stagingStatus"] = "source-staged-pending-root-measured-receipts"
    si["stagingNamespace"] = namespace
    # Rewrite all donor namespace tokens in remaining path strings only after
    # known local fields are set, keeping external measured paths explicit.
    json_dump(p, si)
    digest, size = sha_file(p)
    return si, digest, size


def reseal_candidate_graph(stage: Path) -> None:
    """Reseal tuple/context/binding edges after namespace/path transforms."""
    admission = stage / "admission"
    tuple_path = admission / "candidate-tuple.json"
    binding_path = admission / "candidate-binding.json"
    context_path = admission / "context.json"
    source_path = admission / "source-inputs.json"
    for path in (tuple_path, binding_path, context_path, source_path):
        if not path.is_file() or path.is_symlink():
            fail(f"candidate graph file missing: {path}")
    si = json_load(source_path)
    tuple_doc = json_load(tuple_path)
    context_digest, context_bytes = sha_file(context_path)
    tuple_inputs = tuple_doc.get("sourceInputs")
    if not isinstance(tuple_inputs, dict):
        fail("candidate tuple sourceInputs missing")
    context_ref = si.get("contextRef")
    if not isinstance(context_ref, dict) or not isinstance(context_ref.get("path"), str):
        fail("source-inputs contextRef missing")
    tuple_inputs["context"] = {
        "bytes": context_bytes,
        "path": context_ref["path"],
        "sha256": "sha256:" + context_digest,
    }
    json_dump(tuple_path, tuple_doc)
    tuple_digest, tuple_bytes = sha_file(tuple_path)
    binding = json_load(binding_path)
    tuple_ref = binding.get("canonicalTupleRef")
    if not isinstance(tuple_ref, dict):
        fail("candidate binding canonicalTupleRef missing")
    tuple_ref_path = si.get("tupleRef")
    if not isinstance(tuple_ref_path, dict) or not isinstance(tuple_ref_path.get("path"), str) or not tuple_ref_path["path"]:
        fail("source-inputs tupleRef path missing before binding reseal")
    tuple_ref.update({"bytes": tuple_bytes, "path": tuple_ref_path["path"], "sha256": "sha256:" + tuple_digest})
    json_dump(binding_path, binding)
    binding_digest, binding_bytes = sha_file(binding_path)
    si["contextHash"] = context_digest
    si["contextRef"] = {"bytes": context_bytes, "path": context_ref["path"], "sha256": "sha256:" + context_digest}
    si["tupleHash"] = tuple_digest
    si["tupleRef"] = {"bytes": tuple_bytes, "path": tuple_ref_path["path"], "sha256": "sha256:" + tuple_digest}
    si["bindingHash"] = binding_digest
    binding_ref = si.get("bindingRef")
    if not isinstance(binding_ref, dict) or not isinstance(binding_ref.get("path"), str):
        fail("source-inputs bindingRef missing")
    si["bindingRef"] = {"bytes": binding_bytes, "path": binding_ref["path"], "sha256": "sha256:" + binding_digest}
    json_dump(source_path, si)


def copy_mta_controls(stage: Path) -> None:
    """Stage pinned production MTA predicate controls from Rectangle r12."""
    for name in MTA_CONTROL_FILES:
        src = MTA_CONTROL_ROOT / name
        if not src.is_file() or src.is_symlink():
            fail(f"pinned MTA control missing: {src}")
        copy_explicit(src, stage / "overlay" / name)
    # Fresh Text/Circle stages use v2 worker config proof. Replace only this
    # owned stage row; frozen donor remains untouched.
    if not RELEASE_HELPER_SOURCE.is_file() or RELEASE_HELPER_SOURCE.is_symlink():
        fail(f"prospective worker release helper missing: {RELEASE_HELPER_SOURCE}")
    target = stage / RELEASE_HELPER_REL
    if not target.is_file() or target.is_symlink():
        fail(f"worker release helper target missing: {target}")
    tmp = target.with_name(target.name + ".v2-replace")
    if tmp.exists() or tmp.is_symlink():
        fail(f"worker release helper replacement collision: {tmp}")
    copy_explicit(RELEASE_HELPER_SOURCE, tmp)
    os.replace(tmp, target)


def make_stage_manifest(stage: Path, profile: str) -> dict[str, Any]:
    rows = []
    total = 0
    for rel_path in sorted(stage.rglob("*")):
        if not rel_path.is_file() or rel_path.name == "stage-manifest.json":
            continue
        rel = rel_path.relative_to(stage).as_posix()
        safe_rel(rel)
        digest, size = sha_file(rel_path)
        rows.append({"path": rel, "bytes": size, "sha256": digest})
        total += size
    if len(rows) > MAX_FILES or total > MAX_TOTAL_BYTES:
        fail(f"final stage bounds exceeded: files={len(rows)} bytes={total}")
    m = {"kind": f"factory-{profile}-mta-stage-v1", "compilerActions": 0, "files": rows,
         "limits": {"maxFiles": MAX_FILES, "maxFileBytes": MAX_FILE_BYTES, "maxTotalBytes": MAX_TOTAL_BYTES},
         "mtaWorkerPath": "producer/dependencies/uia-worker/invoke-worker-mta.ps1",
         "mtaControlPaths": [f"overlay/{name}" for name in MTA_CONTROL_FILES],
         "rendererHelperPath": "producer/support/final-exit-certificate.ps1",
         "workerHelperPath": "producer/dependencies/uia-worker/support/final-exit-certificate.ps1",
         "workerHelperConfigKind": "factory-uia-snapshot-worker-config-v2",
         "workerHelperSha256": sha_file(stage / RELEASE_HELPER_REL)[0]}
    json_dump(stage / "stage-manifest.json", m)
    return m


def make_controls(stage: Path, profile: str) -> None:
    ps = r'''param([Parameter(Mandatory=$true)][string]$StageRoot,[Parameter(Mandatory=$true)][string]$SourceInputsPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Fail([string]$m){throw ('mta-stage-closure: '+$m)}
if(-not(Test-Path -LiteralPath $StageRoot -PathType Container)){Fail 'stage root missing'}
$m=Get-Content -Raw -LiteralPath (Join-Path $StageRoot 'stage-manifest.json')|ConvertFrom-Json
if($m.files.Count -gt 256){Fail 'file count bound'}
$seen=@{};$total=0
foreach($r in $m.files){if($seen.ContainsKey($r.path)){Fail 'duplicate path'};$seen[$r.path]=$true;$p=Join-Path $StageRoot $r.path;$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0)){Fail ('unsafe row '+$r.path)};if($i.Length -ne $r.bytes -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){Fail ('row drift '+$r.path)};$total+=$i.Length;if($i.Length -gt 8388608){Fail ('file bound '+$r.path)}}
if($total -gt 33554432){Fail 'total bound'}
$si=Get-Content -Raw -LiteralPath $SourceInputsPath|ConvertFrom-Json
$mta=Join-Path $StageRoot 'producer/dependencies/uia-worker/invoke-worker-mta.ps1';$mtaI=Get-Item -LiteralPath $mta -Force;if($mtaI.Length -le 0){Fail 'MTA invoker missing'}
if([string]$si.uiaWorkerPath -notmatch 'invoke-worker-mta\.ps1$'){Fail 'source inputs not MTA-bound'}
$renderer=Join-Path $StageRoot 'producer/support/final-exit-certificate.ps1';$worker=Join-Path $StageRoot 'producer/dependencies/uia-worker/support/final-exit-certificate.ps1'
if((Get-FileHash $renderer).Hash -ceq (Get-FileHash $worker).Hash){Fail 'renderer helper replaced by worker helper'}
if((Get-FileHash -LiteralPath $worker).Hash.ToLowerInvariant() -cne '__V2_HELPER_HASH__'){Fail 'worker release helper is not prospective v2'}
if([string]$si.integrationBindingsRef.path -notmatch 'integration-bindings\.json$'){Fail 'integration binding ref'}
[ordered]@{status='mta-source-closure-pass';nativeActions=0;lockActions=0;compilerActions=0}|ConvertTo-Json -Depth 8
'''
    helper_hash, _ = sha_file(stage / RELEASE_HELPER_REL)
    ps = ps.replace('__V2_HELPER_HASH__', helper_hash)
    p = stage / "overlay" / "test-mta-stage-closure-v1.ps1"
    with p.open("xb") as fh: fh.write(ps.encode("utf-8"))


def make_installer(stage: Path, template: Path, profile: str, zip_sha: str, namespace: str, si_hash: str) -> str:
    # Preserve original installer provenance while replacing stale hardcoded
    # paths/hashes with fresh runtime values derived from staged source inputs.
    template_sha = sha_file(template)[0]
    worker_helper_sha = sha_file(stage / RELEASE_HELPER_REL)[0]
    issue = f"issue-{profile}-metadata-v1.ps1"
    guard = f"integration-fresh-{profile}-v1.ps1"
    # Keep rolling host roots exact: Text uses text-baseline, Circle uses
    # circle. No profile-specific host tree is created here.
    temp_root = (
        r"D:\Claude\swiftright\.factory-work\hosts\circle"
        if profile == "circle"
        else r"D:\Claude\swiftright\.factory-work\hosts\text-baseline"
    )
    ps = f'''# Derived from {template.name}; templateSha256={template_sha}
param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip=$PackagePath;$zipSha256='{zip_sha}';$temp='{temp_root}\\{namespace}\\count1-r5\\package';$control='D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{namespace}\\control-count1-r5';$namespaceRoot='D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{namespace}';$producerRoot=Join-Path $namespaceRoot 'producer-count1-r5';$admissionRoot=Join-Path $namespaceRoot 'admission-count1-r5';$overlayRoot=Join-Path $namespaceRoot 'overlay-count1-r5';$runRoot=Join-Path $namespaceRoot 'native\\count1-r5';$outputRoot=Join-Path $namespaceRoot 'native'
if(-not(Test-Path -LiteralPath $zip -PathType Leaf)){{throw 'fresh MTA package missing'}}
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne $zipSha256 -or (Test-Path -LiteralPath $temp)){{throw 'fresh pinned MTA package required'}}
Expand-Archive -LiteralPath $zip -DestinationPath $temp
$m=Get-Content -Raw -LiteralPath (Join-Path $temp 'stage-manifest.json')|ConvertFrom-Json
foreach($row in $m.files){{ $f=Join-Path $temp $row.path;$i=Get-Item -LiteralPath $f -Force;if($i.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $row.sha256){{throw ('stage drift '+$row.path)}} }}
foreach($s in @(Get-ChildItem -LiteralPath $temp -Filter '*.ps1' -File -Recurse)){{$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($s.FullName,[ref]$tokens,[ref]$errors)|Out-Null;if($null -ne $errors -and $errors.Count -gt 0){{throw ('PowerShell parse failure '+$s.FullName+': '+[string]$errors[0])}}}}
if(Test-Path -LiteralPath $namespaceRoot){{throw ('fresh destination collision '+$namespaceRoot)}};New-Item -ItemType Directory -Path $namespaceRoot -ErrorAction Stop|Out-Null;New-Item -ItemType Directory -Path $control -ErrorAction Stop|Out-Null
$stageSource=Join-Path $temp 'admission/source-inputs.json';$stageHash=(Get-FileHash -LiteralPath $stageSource).Hash.ToLowerInvariant();if($stageHash -ne '{si_hash}'){{throw 'source-inputs hash drift'}}
$closure=Join-Path $temp 'overlay/test-mta-stage-closure-v1.ps1';& $closure -StageRoot $temp -SourceInputsPath $stageSource | Set-Content -LiteralPath (Join-Path $control 'mta-closure.json') -Encoding UTF8
$mtaConfigControl=Join-Path $temp 'overlay/test-mta-config-admission.ps1';$uiaMtaControl=Join-Path $temp 'overlay/test-uia-mta-controls.ps1';$mtaFinal=Join-Path $temp 'overlay/final-exit-certificate-mta-v1.ps1';foreach($f in @($mtaConfigControl,$uiaMtaControl,$mtaFinal)){{if(-not(Test-Path -LiteralPath $f -PathType Leaf)){{throw ('MTA control source missing '+$f)}}}}
& $mtaConfigControl -OutputPath (Join-Path $control 'mta-config-controls.json')
& $uiaMtaControl -WorkerPath (Join-Path $temp 'producer/dependencies/uia-worker/worker.ps1') -InvokerPath (Join-Path $temp 'producer/dependencies/uia-worker/invoke-worker-mta.ps1') -SchemaPath (Join-Path $temp 'producer/dependencies/uia-worker/schema.ps1') | Set-Content -LiteralPath (Join-Path $control 'uia-mta-controls.json') -Encoding UTF8
foreach($d in @($producerRoot,$admissionRoot,$overlayRoot,$outputRoot)){{if(Test-Path -LiteralPath $d){{throw ('fresh destination collision '+$d)}}}}
New-Item -ItemType Directory -Path $producerRoot,$admissionRoot,$overlayRoot,$outputRoot -ErrorAction Stop|Out-Null
Copy-Item -Path (Join-Path $temp 'producer\\*') -Destination $producerRoot -Recurse;Copy-Item -Path (Join-Path $temp 'admission\\*') -Destination $admissionRoot -Recurse;Copy-Item -Path (Join-Path $temp 'overlay\\*') -Destination $overlayRoot -Recurse
$mta=Join-Path $producerRoot 'dependencies\\uia-worker\\invoke-worker-mta.ps1';$contractPath=Join-Path $producerRoot 'dependencies\\uia-worker\\worker-contract.json';$renderer=Join-Path $producerRoot 'support\\final-exit-certificate.ps1';$worker=Join-Path $producerRoot 'dependencies\\uia-worker\\support\\final-exit-certificate.ps1';foreach($f in @($mta,$contractPath,$renderer,$worker)){{if(-not(Test-Path -LiteralPath $f -PathType Leaf)){{throw ('installed worker closure missing '+$f)}}}};if((Get-FileHash $renderer).Hash -ceq (Get-FileHash $worker).Hash){{throw 'renderer/worker helper collision'}};if((Get-FileHash $worker).Hash.ToLowerInvariant() -cne '{worker_helper_sha}'){{throw 'prospective v2 worker release helper drift'}}
$wc=Get-Content -Raw -LiteralPath $contractPath|ConvertFrom-Json;if(-not $wc.sourceBindings -or @($wc.sourceBindings|Where-Object{{$_.path.Replace('\\','/') -ceq 'invoke-worker-mta.ps1'}}).Count -ne 1){{throw 'worker contract MTA binding missing'}};foreach($b in @($wc.sourceBindings)){{$wf=Join-Path (Split-Path -Parent $contractPath) $b.path;if(-not(Test-Path -LiteralPath $wf -PathType Leaf)){{throw ('worker contract row missing '+$b.path)}};if((Get-FileHash -LiteralPath $wf).Hash.ToLowerInvariant() -cne ([string]$b.sha256).ToLowerInvariant()){{throw ('worker contract drift '+$b.path)}}}}
$source=Join-Path $admissionRoot 'source-inputs.json';$sourceHash=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();if($sourceHash -ne '{si_hash}'){{throw 'installed source-inputs hash drift'}}
$si=Get-Content -Raw -LiteralPath $source|ConvertFrom-Json;$guard=Join-Path $overlayRoot '{guard}';if(-not(Test-Path -LiteralPath $guard)){{throw 'integration guard missing'}}
. $guard;& (Join-Path $overlayRoot 'test-profile-integration.ps1') -GuardPath $guard -Root $producerRoot -SourceInputsPath $source | Set-Content -LiteralPath (Join-Path $control 'integration-controls.json') -Encoding UTF8;Assert-FactoryIntegrationSources $producerRoot $si|Out-Null
$issueArgs=@{{Count=1;SourceInputsPath=$source;SourceInputsHash=$sourceHash;OutputPath=(Join-Path $admissionRoot 'issued-metadata.json');RunRoot=$runRoot;PlanPath=$si.planRef.path;PlanHash=$si.planHash;CompileReceiptPath=$si.compileRef.path;CompileReceiptHash=$si.compileReceiptHash;ExePath=$si.exeRef.path;ExeHash=$si.exeHash;RendererPath=$si.rendererRef.path;RendererHash=$si.rendererSha256;SerializerPath=$si.serializerRef.path;SerializerHash=$si.serializerControlSha256;TuplePath=$si.tupleRef.path;TupleHash=$si.tupleHash;BindingPath=$si.bindingRef.path;BindingHash=$si.bindingHash;RecipePath=$si.recipeRef.path;RecipeHash=$si.recipeHash}};& (Join-Path $overlayRoot '{issue}') @issueArgs
$issued=Join-Path $admissionRoot 'issued-metadata.json';$issuedHash=(Get-FileHash -LiteralPath $issued).Hash.ToLowerInvariant()
$sourceBindings=@(Get-ChildItem -LiteralPath $overlayRoot -File -Recurse|ForEach-Object{{$rel=$_.FullName.Substring($overlayRoot.Length).TrimStart('\\');[ordered]@{{path=$rel.Replace('\\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}}}})
$cfg=[ordered]@{{admissionRoot=$admissionRoot;compileReceiptHash=$si.compileReceiptHash;controlRoot=$control;count=1;exeHash=$si.exeHash;integrationGuardHash=(Get-FileHash -LiteralPath $guard).Hash.ToLowerInvariant();integrationGuardPath=$guard;issuedMetadataHash=$issuedHash;issuedMetadataPath=$issued;outputRoot=$outputRoot;overlayRoot=$overlayRoot;owner='pending-root-lock';package=$si.compiledHostPackagePath;producerRoot=$producerRoot;runRoot=$runRoot;serializerControlSha256=$si.serializerControlSha256;sourceInputsHash=$sourceHash;sourceInputsPath=$source;sourceBindings=$sourceBindings}}
$cfgPath=Join-Path $control 'config-template.json';$cfg|ConvertTo-Json -Depth 32|Set-Content -LiteralPath $cfgPath -Encoding UTF8;$cfgHash=(Get-FileHash -LiteralPath $cfgPath).Hash.ToLowerInvariant()
& (Join-Path $overlayRoot 'coordinator-count1-v3.ps1') -Template $cfgPath -TemplateHash $cfgHash -PreflightOnly
[ordered]@{{status='source-package-preflight-passed';profile='{profile}';templateSha256='{template_sha}';packageSha256=$zipSha256;sourceInputsHash=$sourceHash;issuedMetadataHash=$issuedHash;namespace='{namespace}';nativeActions=0;lockActions=0;compilerActions=0}}|ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Encoding UTF8
'''
    return ps


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", choices=("text", "circle"), required=True)
    ap.add_argument("--donor-root", type=Path, required=True)
    ap.add_argument("--installer-template", type=Path, required=True)
    ap.add_argument("--output-root", type=Path, required=True)
    ap.add_argument("--output-zip", type=Path, required=True)
    ap.add_argument("--output-installer", type=Path, required=True)
    ap.add_argument("--namespace", required=True, help="fresh Windows namespace token, e.g. text-mta-r11-v5")
    ap.add_argument("--old-namespace", help="exact donor .work namespace; defaults from source-inputs")
    ap.add_argument("--new-count-token", default="count1-r5")
    args = ap.parse_args()
    donor = args.donor_root.resolve()
    template = args.installer_template.resolve()
    for out in (args.output_root, args.output_zip, args.output_installer):
        if out.exists() or out.is_symlink():
            fail(f"fresh output collision: {out}")
    if not donor.is_dir(): fail("donor root is not directory")
    if not template.is_file() or template.is_symlink(): fail("installer template invalid")
    manifest = load_manifest(donor)
    donor_si = json_load(donor / "admission/source-inputs.json")
    old_ns = args.old_namespace or find_namespace(donor_si)
    stage = args.output_root
    stage.mkdir(parents=True)
    for row in manifest["files"]:
        rel = safe_rel(row["path"]); copy_explicit(donor / rel, stage / rel)
    # Add pinned MTA config/schema controls before token transforms & manifest
    # sealing. These controls execute production predicates only; they launch
    # no workers or native hosts.
    copy_mta_controls(stage)
    replacements = [
        (old_ns, args.namespace),
        ("admission-count1-r4", "admission-count1-r5"),
        ("producer-count1-r4", "producer-count1-r5"),
        ("overlay-count1-r4", "overlay-count1-r5"),
        ("control-count1-r4", "control-count1-r5"),
        ("native\\count1-r4", "native\\count1-r5"),
        ("native/count1-r4", "native/count1-r5"),
        ("count1-r4", args.new_count_token),
    ]
    for p in sorted(stage.rglob("*")):
        if p.is_file() and p.name != "stage-manifest.json":
            text_transform(p, replacements)
    # Namespace transforms change tuple/binding/context bytes; reseal graph
    # edges before integration/source-input hashes are emitted.
    reseal_candidate_graph(stage)
    # Update integration binding rows after all source transformations.
    update_binding_file(stage, args.profile)
    # Fresh roots are explicit path values used by source inputs/issuer. Paths are
    # never discovered from staged content.
    roots = {
      "bindingRef": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\admission-count1-r5\\candidate-binding.json",
      "contextRef": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\admission-count1-r5\\context.json",
      "tupleRef": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\admission-count1-r5\\candidate-tuple.json",
      "recipeRef": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\admission-count1-r5\\recipe.json",
      "integrationBindingsRef": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\producer-count1-r5\\integration-bindings.json",
      "uiaWorkerPath": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\producer-count1-r5\\dependencies\\uia-worker\\invoke-worker-mta.ps1",
      "workerReleaseHelperPath": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\producer-count1-r5\\dependencies\\uia-worker\\support\\final-exit-certificate.ps1",
      "capturePlanPath": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\producer-count1-r5\\capture-plan.json",
      "buildPreflightPath": f"D:\\Claude\\swiftright\\factory\\native\\windows\\.work\\{args.namespace}\\overlay-count1-r5\\capture-build-preflight.ps1",
    }
    si, si_hash, si_bytes = update_source_inputs(stage, args.profile, args.namespace, roots)
    make_controls(stage, args.profile)
    final_manifest = make_stage_manifest(stage, args.profile)
    # Stage manifest changed after source inputs/controls; recompute package file list.
    zip_path = args.output_zip
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "x", compression=zipfile.ZIP_DEFLATED) as zf:
        for row in final_manifest["files"] + [{"path":"stage-manifest.json"}]:
            rel = row["path"]; src = stage / rel; regular(src, MAX_FILE_BYTES)
            zf.write(src, rel)
    zip_sha, zip_bytes = sha_file(zip_path)
    installer = make_installer(stage, template, args.profile, zip_sha, args.namespace, si_hash)
    with args.output_installer.open("xb") as fh: fh.write(installer.encode("utf-8"))
    receipt = {"kind":"factory-mta-stage-r5-source-only-v1","profile":args.profile,"namespace":args.namespace,
      "donorRoot":str(donor),"installerTemplate":str(template),"installerTemplateSha256":sha_file(template)[0],
      "stageRoot":str(stage),"stageFileCount":len(final_manifest["files"]),"stageTotalBytes":sum(r["bytes"] for r in final_manifest["files"]),
      "sourceInputsHash":si_hash,"sourceInputsBytes":si_bytes,"packageSha256":zip_sha,"packageBytes":zip_bytes,
      "mtaWorkerPath":"producer/dependencies/uia-worker/invoke-worker-mta.ps1",
      "rendererHelperPath":"producer/support/final-exit-certificate.ps1",
      "workerHelperPath":"producer/dependencies/uia-worker/support/final-exit-certificate.ps1",
      "status":"source-only-pending-root-transport-and-preflight","nativeActions":0,"lockActions":0,"compilerActions":0}
    installer_sha, installer_bytes = sha_file(args.output_installer)
    receipt["installerSha256"] = installer_sha; receipt["installerBytes"] = installer_bytes
    receipt_path = args.output_zip.with_suffix(args.output_zip.suffix + ".receipt.json")
    if receipt_path.exists() or receipt_path.is_symlink():
        fail(f"fresh output collision: {receipt_path}")
    json_dump(receipt_path, receipt)
    print(json.dumps(receipt, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
