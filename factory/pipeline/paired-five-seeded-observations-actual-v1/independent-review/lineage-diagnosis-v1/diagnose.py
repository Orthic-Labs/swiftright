#!/usr/bin/env python3
"""Read-only path-namespace diagnosis for seeded-v1 raw/capture hash mismatch."""
import hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
BASE=ROOT/'factory/oracle/mac/seed-corrections-v1'
NATIVE=ROOT/'factory/native/macos/evidence/20261010-gate-seeded'
PROOF=ROOT/'factory/native/windows/round1-seeded-native-v2/root-mac-proof-actual-r1/proof-copy.json'
LINEAGE=ROOT/'factory/oracle/mac/seed-corrections-lineage-v2/lineage.json'
REPORT=ROOT/'factory/pipeline/paired-five-seeded-observations-actual-v1/report.json'
C514='514433100e30d808487ed3825ffb7d129bead8a7'
PROOFCOMMIT='7f95f113adcb9b61614afc83a75e714b9906cc4f'
CASES={'stack-overlay':'stack','custom-layout':'custom','padding-frame':'padding','preference-key':'preference','scroll-view':'scroll'}
def digest_bytes(b): return hashlib.sha256(b).hexdigest()
def digest(p): return 'sha256:'+digest_bytes(p.read_bytes())
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def git_bytes(ref,path):
 p=subprocess.run(['git','show',f'{ref}:{path}'],cwd=ROOT,capture_output=True)
 return p.stdout if p.returncode==0 else None
def git_hash(ref,path):
 b=git_bytes(ref,path); return digest_bytes(b) if b is not None else None
def inspect():
 proof=read(PROOF); lineage=read(LINEAGE); report=read(REPORT)
 proof_cases={x['block']:x for x in proof['cases']}; line_cases={x['block']:x for x in lineage['cases']}
 counters={'proofLineageOracleRawMatch':0,'proofOracleCaptureMatch':0,'reportNativeRawMatch':0,'reportNativeCaptureMatch':0,'reportNativeProofRawMismatch':0,'reportNativeProofCaptureMismatch':0}
 example=None; case_results=[]
 for block,report_key in CASES.items():
  pc=proof_cases[block]; lc=line_cases[block]; report_case=report['cases'][report_key]['macFresh100']; native_root=NATIVE/pc['case']['id']
  rows={x['run']:x for x in report_case['runs']}; proof_rows={x['run']:x for x in pc['runs']}; line_rows={x['run']:x for x in lc['rawInstrumentedJoins']}
  assert set(rows)==set(proof_rows)==set(line_rows)==set(range(1,21))
  for i in range(1,21):
   linrow=line_rows[i]; prow=proof_rows[i]; rr=rows[i]
   oracle_raw=BASE/linrow['rawPath']; oracle_capture=oracle_raw.parent/'capture.json'
   native_raw=native_root/f'run-{i:03d}/instrumented.raw.json'; native_capture=native_root/f'run-{i:03d}/capture.json'
   oh,och,nh,nch=map(digest,(oracle_raw,oracle_capture,native_raw,native_capture))
   summary=read(native_root/'summary.json'); sr=next(x for x in summary['runs'] if x['run']==i)
   assert oh==linrow['rawSha256']==linrow['summaryInstrumentedRawHash']==prow['rawHash']
   assert och==prow['captureHash']
   assert nh==sr['instrumented']['rawHash']
   assert nch==sr['captureHash']==rr['captureSha256']
   counters['proofLineageOracleRawMatch']+=oh==prow['rawHash']
   counters['proofOracleCaptureMatch']+=och==prow['captureHash']
   counters['reportNativeRawMatch']+=nh==sr['instrumented']['rawHash']
   counters['reportNativeCaptureMatch']+=nch==rr['captureSha256']
   counters['reportNativeProofRawMismatch']+=nh!=prow['rawHash']
   counters['reportNativeProofCaptureMismatch']+=nch!=prow['captureHash']
   if example is None:
    example={'block':block,'run':i,'proofLineageRawPath':linrow['rawPath'],'oracleEvidencePath':str(oracle_raw.relative_to(ROOT)),'oracleRawSha256':oh,'proofRawSha256':prow['rawHash'],'lineageRawSha256':linrow['rawSha256'],'nativeReportPath':str(native_raw.relative_to(ROOT)),'nativeRawSha256':nh,'proofLineageCapturePath':str(oracle_capture.relative_to(ROOT)),'proofCaptureSha256':prow['captureHash'],'oracleCaptureSha256':och,'nativeCapturePath':str(native_capture.relative_to(ROOT)),'nativeCaptureSha256':nch}
  case_results.append({'block':block,'runs':20,'oracleProofLineageRawMatches':20,'nativeReportRawMatches':20,'nativeVsProofRawMismatches':20})
 assert counters=={'proofLineageOracleRawMatch':100,'proofOracleCaptureMatch':100,'reportNativeRawMatch':100,'reportNativeCaptureMatch':100,'reportNativeProofRawMismatch':100,'reportNativeProofCaptureMismatch':100},counters
 native_path='factory/native/macos/evidence/20261010-gate-seeded/swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258/run-001/instrumented.raw.json'
 oracle_path='factory/oracle/mac/seed-corrections-v1/evidence/swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258/run-001/instrumented.raw.json'
 native_capture_path=native_path.replace('instrumented.raw.json','capture.json')
 oracle_capture_path=oracle_path.replace('instrumented.raw.json','capture.json')
 historical={
  'nativeRaw':{ref:git_hash(ref,native_path) for ref in (C514,'HEAD')},
  'oracleRaw':{ref:git_hash(ref,oracle_path) for ref in (C514,'HEAD')},
  'nativeCapture':{ref:git_hash(ref,native_capture_path) for ref in (C514,'HEAD')},
  'oracleCapture':{ref:git_hash(ref,oracle_capture_path) for ref in (C514,'HEAD')},
  'lineageFile':{ref:git_hash(ref,'factory/oracle/mac/seed-corrections-lineage-v2/lineage.json') for ref in (C514,'HEAD')},
  'proofCopy':{C514:git_hash(C514,'factory/native/windows/round1-seeded-native-v2/root-mac-proof-actual-r1/proof-copy.json'),PROOFCOMMIT:git_hash(PROOFCOMMIT,'factory/native/windows/round1-seeded-native-v2/root-mac-proof-actual-r1/proof-copy.json'),'HEAD':git_hash('HEAD','factory/native/windows/round1-seeded-native-v2/root-mac-proof-actual-r1/proof-copy.json')},
  'proofCopyIntroducedBy':PROOFCOMMIT
 }
 assert historical['nativeRaw'][C514]==historical['nativeRaw']['HEAD']=='f22329aca15b951798f76923b0381d8d67c62aa8c8b028647ce245e25f03e46b'
 assert historical['oracleRaw'][C514]==historical['oracleRaw']['HEAD']=='040794666447c49109f1c9100230aa3276d5c56d2a35d6c80041b8997cb7771f'
 assert historical['nativeCapture'][C514]==historical['nativeCapture']['HEAD']=='13bd35e618567ca2e2f30ebc3359773ea7675d3cef786909fd12a9a610ef3082'
 assert historical['oracleCapture'][C514]==historical['oracleCapture']['HEAD']=='684ee57a1335fc8cfce293d536d6be7f36f647b5c0010830880a8647b3e5a044'
 assert historical['lineageFile'][C514]==historical['lineageFile']['HEAD']
 assert historical['proofCopy'][C514] is None and historical['proofCopy'][PROOFCOMMIT]==historical['proofCopy']['HEAD']
 return {'kind':'seeded-actual-v1-lineage-namespace-diagnosis','version':1,'decision':'wrong-source-namespace-join; no raw-file drift between 51443310 and HEAD','counts':counters,'example':example,'cases':case_results,'history':historical,'explanation':'proof-copy/lineage rawPath values resolve under factory/oracle/mac/seed-corrections-v1, where all 100 raw+capture hashes match. F9 actual-v1 builder selects factory/native/macos/evidence/20261010-gate-seeded, a distinct same-case/source capture set; all 100 current files and summaries match each other but differ from proof/lineage. Current native files equal their 51443310 committed bytes and remain unchanged at HEAD. proof-copy was added later in 7f95f113; this is namespace selection, not post-514 file drift.'}
if __name__=='__main__': print(json.dumps(inspect(),sort_keys=True,indent=2))
