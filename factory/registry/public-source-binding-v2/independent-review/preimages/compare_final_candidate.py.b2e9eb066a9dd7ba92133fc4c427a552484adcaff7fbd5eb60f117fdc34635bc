#!/usr/bin/env python3
"""Run unchanged USR manifest against one supplied F1 candidate.

Caller must provide versioned output path; pending receipt stays immutable.
"""
from __future__ import annotations
import argparse,hashlib,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]; V1=ROOT/'factory/registry/public-source-binding-v1'
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def repo_path(p):
 p=Path(p).resolve()
 try:return str(p.relative_to(ROOT))
 except ValueError:return str(p)
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('catalogue',type=Path); ap.add_argument('--output',type=Path,required=True,help='new versioned receipt; never pending final-candidate-resolution.json'); a=ap.parse_args()
 candidate=Path(a.catalogue).resolve(); raw=candidate.read_bytes(); cat=json.loads(raw.decode('utf-8'))
 if not isinstance(cat,dict) or cat.get('kind')!='catalogue' or cat.get('version')!='0.1' or not isinstance(cat.get('symbols'),list):
  raise SystemExit('candidate must be a UTF-8 v0.1 catalogue with symbols array')
 expected=json.loads((V1/'expected-registry-membership.json').read_text()); manifest=json.loads((V1/'manifest-usr-v1.json').read_text()); sys.path.insert(0,str(ROOT)); from factory.registry.registry import build_registry
 expected_block_count=len(manifest['blocks'])
 artifact=build_registry(cat,manifest=V1/'manifest-usr-v1.json',created_at='2026-10-11T00:00:00Z',producer='factory/registry/public-source-binding-v2/final-candidate')
 got=[{'blockId':b['id'],'symbolIndex':i,'usr':u} for b in artifact['blocks'] for i,u in enumerate(b['symbols'])]
 want=expected['blocks']; membership_equal=got==want; block_count_equal=len(artifact['blocks'])==expected_block_count
 status='stable-membership' if membership_equal and block_count_equal else 'membership-drift-held'
 out={'kind':'f2-public-source-binding-final-candidate-comparison','version':1,'status':status,'candidate':{'path':repo_path(candidate),'absolutePath':str(candidate),'sha256':sha(candidate),'kind':cat['kind'],'schemaVersion':cat['version'],'symbolCount':len(cat['symbols'])},'manifest':{'path':repo_path(V1/'manifest-usr-v1.json'),'sha256':sha(V1/'manifest-usr-v1.json'),'selectorCount':sum(len(b['symbols']) for b in manifest['blocks']),'blockCount':expected_block_count},'expectedMembershipPath':repo_path(V1/'expected-registry-membership.json'),'expectedMembershipSha256':sha(V1/'expected-registry-membership.json'),'actualBlockCount':len(artifact['blocks']),'expectedBlockCount':expected_block_count,'actualMembershipCount':len(got),'expectedMembershipCount':len(want),'membershipEqual':membership_equal,'blockCountEqual':block_count_equal}
 output=Path(a.output).resolve(); output.parent.mkdir(parents=True,exist_ok=True); output.write_text(json.dumps(out,indent=2)+'\n'); print(json.dumps(out,indent=2)); raise SystemExit(0 if status=='stable-membership' else 2)
if __name__=='__main__':main()
