#!/usr/bin/env python3
"""Run unchanged USR manifest against frozen final F1 candidate & compare membership."""
from __future__ import annotations
import argparse,hashlib,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('catalogue',type=Path); ap.add_argument('--output',type=Path,default=HERE/'final-candidate-resolution.json'); a=ap.parse_args(); cat=json.loads(a.catalogue.read_text()); expected=json.loads((HERE/'expected-registry-membership.json').read_text()); sys.path.insert(0,str(ROOT)); from factory.registry.registry import build_registry
 artifact=build_registry(cat,manifest=HERE/'manifest-usr-v1.json',created_at='2026-10-11T00:00:00Z',producer='factory/registry/public-source-binding-v1/final-candidate')
 got=[{'blockId':b['id'],'symbolIndex':i,'usr':u} for b in artifact['blocks'] for i,u in enumerate(b['symbols'])]
 want=expected['blocks']; status='stable-membership' if got==want else 'membership-drift-held'
 out={'kind':'f2-public-source-binding-final-candidate-comparison','version':1,'status':status,'candidate':{'path':str(a.catalogue),'sha256':sha(a.catalogue),'symbolCount':len(cat.get('symbols',[]))},'manifest':{'path':str((HERE/'manifest-usr-v1.json').relative_to(ROOT)),'sha256':sha(HERE/'manifest-usr-v1.json')},'expectedMembershipPath':str((HERE/'expected-registry-membership.json').relative_to(ROOT)),'expectedMembershipSha256':sha(HERE/'expected-registry-membership.json'),'actualMembershipCount':len(got),'expectedMembershipCount':len(want),'membershipEqual':got==want}
 a.output.write_text(json.dumps(out,indent=2)+'\n'); print(json.dumps(out,indent=2)); raise SystemExit(0 if status=='stable-membership' else 2)
if __name__=='__main__':main()
