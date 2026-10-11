#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent
CAT=ROOT/'factory/catalogue/evidence/catalogue.json'; BASE=ROOT/'factory/registry/manifest.json'; OUT=HERE/'manifest-usr-v1.json'; PROV=HERE/'resolution-provenance.json'; EXPECT=HERE/'expected-registry-membership.json'; REG=HERE/'registry-resolution.json'
EXPECTED_CAT='sha256:740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270'
def sha(b):
 if isinstance(b,str):b=b.encode()
 return 'sha256:'+hashlib.sha256(b).hexdigest()
def main():
 d=json.loads(CAT.read_text()); base=json.loads(BASE.read_text()); out=json.loads(OUT.read_text()); p=json.loads(PROV.read_text()); e=json.loads(EXPECT.read_text()); reg=json.loads(REG.read_text())
 assert sha(CAT.read_bytes())==EXPECTED_CAT and len(d['symbols'])==108272
 assert sha(BASE.read_bytes())==p['baseManifest']['sha256']; assert sha(OUT.read_bytes())==p['outputManifest']['sha256']; assert p['selectorCount']==65 and p['pathSelectorsResolved']==0 and p['usrSelectorsRevalidated']==65
 assert len(out['blocks'])==10 and out['blocks']==base['blocks']
 by={x['usr']:x for x in d['symbols']}; allrows=[]
 for b in out['blocks']:
  for s in b['symbols']:
   assert s.startswith('usr:') and s[4:] in by and by[s[4:]].get('status')!='hidden'; allrows.append({'blockId':b['id'],'symbolIndex':len([x for x in allrows if x['blockId']==b['id']]),'usr':s[4:]})
 assert len(allrows)==65
 assert [{'blockId':x['blockId'],'symbolIndex':x['symbolIndex'],'usr':x['usr']} for x in e['blocks']]==allrows
 assert [(x['blockId'],x['outputSelector']) for x in p['resolutions']]==[(b['id'],s) for b in out['blocks'] for s in b['symbols']]
 assert reg['kind']=='block-registry' and len(reg['blocks'])==10
 print('public-source-binding-v1 verification: pinned 108272 catalogue, exact ten blocks, 65 non-hidden USRs, provenance & production registry pass; final F1 candidate pending')
if __name__=='__main__':main()
