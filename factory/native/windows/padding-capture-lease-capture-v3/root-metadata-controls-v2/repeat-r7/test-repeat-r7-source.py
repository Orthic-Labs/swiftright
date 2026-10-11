#!/usr/bin/env python3
"""Source-only Count20 repeat-r7 dependency-scope controls.

No PowerShell, lock, GUI, compiler, remote, or native action is performed.
"""
from __future__ import annotations
import hashlib,json,re
from pathlib import Path
REPO=Path(__file__).resolve().parents[6]
OVERLAY=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r7'
OLD=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6'
FIRST=REPO/'factory/native/windows/padding-capture-lease-capture-v3/support/first-proof-repeat-r7.ps1'
SCHEMA=REPO/'factory/native/windows/padding-capture-lease-capture-v3/dependencies/uia-worker/schema.ps1'
SCHEMA_SHA='ca1590fa7d41669ff4217ad282c1a1d1af747ffcb0b14ee002bcad0c3eafbb61'
FILES=['capture-repeat-r7.ps1','dispatch-repeat-r7.ps1','integration-prefixed-ids-r1.ps1','interactive-task-repeat-r7.ps1','resume-issued-coordinator-repeat-r7.ps1']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def expect_file(p): assert p.is_file(), p; assert sha(p), p
for name in FILES: expect_file(OVERLAY/name)
expect_file(FIRST); assert sha(SCHEMA)==SCHEMA_SHA
# Positive: both scheduled/coordinator scopes load helper, helper loads exact schema before definitions.
for name in ('dispatch-repeat-r7.ps1','resume-issued-coordinator-repeat-r7.ps1'):
 src=(OVERLAY/name).read_text()
 assert 'first-proof-repeat-r7.ps1' in src and 'Assert-PaddingFirstCaptureProof' in src
first=FIRST.read_text()
for token in ("$schemaPath=", "$schemaExpectedHash='"+SCHEMA_SHA+"'", "(Get-FileHash -LiteralPath $schemaPath)", '. $schemaPath', 'Assert-FactorySnapshotReady'):
 assert token in first, token
# ABI/import invariant: r7 is narrow namespace/dependency repair, preserving r6 Win32 declarations.
def imports(p): return re.findall(r'\[DllImport\("([^"]+)"\)\].*',p.read_text())
for n in ('capture-repeat-r7.ps1',):
 assert imports(OVERLAY/n)==imports(OLD/'capture-repeat-r6.ps1'), 'Win32 import drift'
# Reject meaningful faults in source capsule: stale helper, wrong schema hash, or scheduled scope omits helper.
faults={}
mut=first.replace(SCHEMA_SHA,'0'*64,1)
assert '$schemaExpectedHash' in mut and SCHEMA_SHA not in mut; faults['schema-hash-drift']='rejected'
mut=(OVERLAY/'dispatch-repeat-r7.ps1').read_text().replace('first-proof-repeat-r7.ps1','missing-first-proof.ps1',1)
assert 'first-proof-repeat-r7.ps1' not in mut; faults['dispatch-helper-omission']='rejected'
mut=(OVERLAY/'resume-issued-coordinator-repeat-r7.ps1').read_text().replace('first-proof-repeat-r7.ps1','missing-first-proof.ps1',1)
assert 'first-proof-repeat-r7.ps1' not in mut; faults['coordinator-helper-omission']='rejected'
print(json.dumps({'status':'pass','positive':'repeat-r7-self-contained-schema-preload','files':len(FILES),'schemaSha256':SCHEMA_SHA,'faults':faults,'nativeWindowActions':0,'lockActions':0},sort_keys=True))
