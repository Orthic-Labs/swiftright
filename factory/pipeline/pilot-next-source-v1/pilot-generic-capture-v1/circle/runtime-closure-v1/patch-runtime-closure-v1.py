#!/usr/bin/env python3
"""Emit fresh Circle capture/integration/issuer sources using source-input runtimeProof."""
from __future__ import annotations
import argparse, hashlib, json, stat
from pathlib import Path
MAX = 64 * 1024 * 1024
CHUNK = 1024 * 1024
OLD_CAPTURE = """$runtimeVerifier=Join-Path $captureRoot 'support\\verify-runtime-source.ps1'
if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Runtime verifier drift'}
. $runtimeVerifier"""
NEW_CAPTURE = """$runtimeClosure=Join-Path $captureRoot 'support\\circle-runtime-closure-v1.ps1'
if(-not (Test-Path -LiteralPath $runtimeClosure -PathType Leaf)){throw 'Circle runtime closure helper missing'}
. $runtimeClosure
$runtimeAssets=Assert-CircleRuntimeClosure $plan $sourceDocument $packagePath $captureRoot
$runtimeVerifier=[string]$runtimeAssets.runtimeVerifierPath
$hostInputs=[string]$runtimeAssets.hostInputsPath
. $runtimeVerifier
. $hostInputs"""
OLD_CLOSE = "if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash -or (Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Owned close source verifier drift'}"
NEW_CLOSE = "if((Get-CircleHash $runtimeVerifier) -cne [string]$runtimeAssets.runtimeVerifierHash -or (Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Owned close source verifier drift'}"
OLD_POST_HOST = "if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input helper drift after capture'}"
NEW_POST_HOST = "if((Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Host input helper drift after capture'}"
OLD_HOST = """$hostInputs=Join-Path $captureRoot 'support\\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs"""
NEW_HOST = """$hostInputs=[string]$runtimeAssets.hostInputsPath
if((Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Host input guard drift'}
. $hostInputs"""
OLD_ISSUER = "if($source.caseID -notlike ($CircleCasePrefix+'*') -or $source.recipeHash -cne $CircleCanonicalRecipeHashBare){throw 'Issuer Circle case/recipe canonical join mismatch'}"
NEW_ISSUER = OLD_ISSUER + "\nif($null -eq $source.runtimeProof){throw 'Issuer runtime proof block missing'}\nforeach($field in @('runtimeSourceCommit','runtimeSourceTreeHash','runtimeSourceReceiptHash')){if([string]::IsNullOrWhiteSpace([string]$source.runtimeProof.$field)){throw ('Issuer runtime proof field missing: '+$field)}}\nif($source.runtimeSourceCommit -cne $source.runtimeProof.runtimeSourceCommit){throw 'Issuer runtime source commit proof mismatch'}\nforeach($field in @('runtimeSourceTreeRef','runtimeSourceReceiptRef','runtimeVerifierRef','hostInputsRef')){if($null -eq $source.runtimeProof.$field){throw ('Issuer runtime proof reference missing: '+$field)};[void](Ref ([string]$source.runtimeProof.$field.path) ([string]$source.runtimeProof.$field.sha256).Substring(7))}"
OLD_PLAN = "if($plan.kind -ne 'factory-circle-compiler-plan-v1'"
NEW_PLAN = "if($plan.runtimeSourceCommit -ne $source.runtimeProof.runtimeSourceCommit -or $plan.runtimeSourceTreeHash -ne $source.runtimeProof.runtimeSourceTreeHash -or $plan.runtimeSourceReceiptHash -ne $source.runtimeProof.runtimeSourceReceiptHash){throw 'Issuer runtime proof/plan mismatch'}\n" + OLD_PLAN

def read(path: Path) -> tuple[str, int, str]:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > MAX: raise RuntimeError(f'bounded regular source required: {path}')
    h = hashlib.sha256(); chunks=[]; total=0
    with path.open('rb') as f:
        while chunk := f.read(CHUNK):
            total += len(chunk)
            if total > MAX: raise RuntimeError(f'source grew beyond bound: {path}')
            h.update(chunk); chunks.append(chunk)
    if total != st.st_size: raise RuntimeError(f'source changed while read: {path}')
    return b''.join(chunks).decode('utf-8'), total, h.hexdigest()

def write(path: Path, data: str) -> tuple[int, str]:
    if path.exists() or path.is_symlink(): raise RuntimeError(f'fresh output required: {path}')
    path.parent.mkdir(parents=True, exist_ok=True); raw=data.encode('utf-8')
    with path.open('xb') as f: f.write(raw)
    return len(raw), hashlib.sha256(raw).hexdigest()

def patch(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1: raise RuntimeError(f'exact {label} anchor required')
    return text.replace(old, new, 1)

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--capture-input', required=True, type=Path); ap.add_argument('--capture-output', required=True, type=Path)
    ap.add_argument('--integration-input', required=True, type=Path); ap.add_argument('--integration-output', required=True, type=Path)
    ap.add_argument('--issuer-input', required=True, type=Path); ap.add_argument('--issuer-output', required=True, type=Path)
    ap.add_argument('--helper-output', required=True, type=Path)
    ns=ap.parse_args()
    cap, cap_n, cap_h=read(ns.capture_input); integ, integ_n, integ_h=read(ns.integration_input); issuer, issuer_n, issuer_h=read(ns.issuer_input)
    cap=patch(cap, OLD_CAPTURE, NEW_CAPTURE, 'capture runtime verifier'); cap=patch(cap, OLD_HOST, NEW_HOST, 'capture host input proof'); cap=patch(cap, OLD_CLOSE, NEW_CLOSE, 'owned close source proof'); cap=patch(cap, OLD_POST_HOST, NEW_POST_HOST, 'post-capture host input proof')
    # Integration validates runtimeProof before plan/receipt joins, never an absent plan field.
    anchor="function Assert-FactoryIntegrationSources([string]$Root,[object]$SourceInputs){\n"
    insertion="""function Assert-CircleRuntimeProofFields([object]$SourceInputs){
 if($null -eq $SourceInputs.runtimeProof){throw 'Circle runtime proof block missing'}
 $p=$SourceInputs.runtimeProof
 foreach($field in @('runtimeSourceCommit','runtimeSourceTreeHash','runtimeSourceReceiptHash')){if([string]::IsNullOrWhiteSpace([string]$p.$field)){throw ('Circle runtime proof field missing: '+$field)}}
 if($p.runtimeSourceCommit -cne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' -or $p.runtimeSourceTreeHash -cne 'sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e' -or $p.runtimeSourceReceiptHash -cne 'sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7'){throw 'Circle runtime measured proof mismatch'}
 foreach($field in @('runtimeSourceTreeRef','runtimeSourceReceiptRef','runtimeVerifierRef','hostInputsRef')){if($null -eq $p.$field){throw ('Circle runtime proof reference missing: '+$field)};[void](Assert-CircleRef $p.$field ('runtime proof '+$field))}
 return $true
}
"""
    integ=patch(integ, anchor, insertion+anchor, 'integration proof helper')
    integ=patch(integ, " foreach($field in @('caseID','caseHash'", " Assert-CircleRuntimeProofFields $SourceInputs|Out-Null\n foreach($field in @('caseID','caseHash'", 'integration proof call')
    issuer=patch(issuer, OLD_ISSUER, NEW_ISSUER, 'issuer case anchor'); issuer=patch(issuer, OLD_PLAN, NEW_PLAN, 'issuer plan anchor')
    helper, helper_n, helper_h=read(Path(__file__).with_name('circle-runtime-closure-v1.ps1'))
    cap_n2, cap_h2=write(ns.capture_output, cap); integ_n2, integ_h2=write(ns.integration_output, integ); issuer_n2, issuer_h2=write(ns.issuer_output, issuer); helper_n2, helper_h2=write(ns.helper_output, helper)
    print(json.dumps({'status':'staged-source-only','capture':{'bytes':cap_n2,'sha256':cap_h2},'integration':{'bytes':integ_n2,'sha256':integ_h2},'issuer':{'bytes':issuer_n2,'sha256':issuer_h2},'helper':{'bytes':helper_n2,'sha256':helper_h2},'nativeActions':0,'compilerActions':0},sort_keys=True))
    return 0
if __name__ == '__main__': raise SystemExit(main())
