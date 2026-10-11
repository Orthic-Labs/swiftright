#!/usr/bin/env python3
"""Offline verifier for append-only compiler/source lineage supplement."""
import argparse,hashlib,json,sys
from pathlib import Path
BLOCKS=('stack-overlay','padding-frame','scroll-view','custom-layout','preference-key')
def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def fail(x): raise ValueError(x)
def validate(root):
 root=Path(root).resolve(); base=root.parent/'seed-corrections-v1'; root.joinpath('policy/source-policy.json').is_file() or fail('missing policy')
 pol=json.loads((root/'policy/source-policy.json').read_text()); sha(root/'policy/capture.py')==pol['scriptSha256'] or fail('policy hash')
 pol['actualProcessReceipt']['argvRecorded'] is False or fail('false process proof')
 pins={x['block']:x for x in json.loads((base/'input-pins.json').read_text())['rows']}
 top=json.loads((root/'lineage.json').read_text()); top['seed']==14577611000270672472 and set(pins)==set(BLOCKS) or fail('seed/cases')
 for b in BLOCKS:
  d=json.loads((root/'cases'/b/'lineage.json').read_text()); w=root/'cases'/b/'Witness.swift'; a=root/'cases'/b/'CaptureHost.adapted.swift'; binary=base/f'binaries/{b}/capture-host'
  sha(w)==d['sourceWitness']['sha256']==pins[b]['source']['declared']==d['sourceWitness']['summarySourceHash'] or fail(f'{b} witness')
  sha(a)==d['adaptedCaptureHost']['sha256']==d['adaptedCaptureHost']['summaryCompiledAdapterHash'] or fail(f'{b} adapter')
  d['adaptedCaptureHost']['summaryAdapterSourceHash']==pol['adapterSource']['sha256'] or fail(f'{b} original adapter hash')
  sha(binary)==d['binary']['sha256']==d['binary']['summaryBinaryHash'] or fail(f'{b} binary')
  for pkey in ('stdoutPath','stderrPath'):
   p=root/d['buildOutput'][pkey]; p.is_file() or fail(f'{b} build output'); sha(p)==d['buildOutput'][pkey.replace('Path','Sha256')] or fail(f'{b} build hash')
  len(d['rawInstrumentedJoins'])==20 or fail(f'{b} raw count')
  for r in d['rawInstrumentedJoins']:
   p=base/r['rawPath']; p.is_file() or fail(f'{b} raw missing'); sha(p)==r['rawSha256']==r['summaryInstrumentedRawHash'] or fail(f'{b} raw hash')
  d['compileProcessProof'].startswith('MISSING:') or fail(f'{b} process proof')
 return {'status':'PASS','seed':14577611000270672472,'cases':5,'rawRuns':100,'compileProcessProof':'MISSING and explicitly held','sourceBinaryRawJoins':'verified'}
if __name__=='__main__':
 ap=argparse.ArgumentParser(); ap.add_argument('root',nargs='?',default=Path(__file__).parent); a=ap.parse_args()
 try: print(json.dumps(validate(a.root),sort_keys=True,indent=2))
 except Exception as e: print('FAIL:',e,file=sys.stderr); raise SystemExit(1)
