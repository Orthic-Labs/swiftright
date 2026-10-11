#!/usr/bin/env python3
"""Resolve ten-block registry membership against immutable 108272-symbol catalogue."""
from __future__ import annotations
import copy, hashlib, json, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE_CATALOGUE=ROOT/'factory/catalogue/evidence/catalogue.json'
BASE_MANIFEST=ROOT/'factory/registry/manifest.json'
OUT_MANIFEST=HERE/'manifest-usr-v1.json'; OUT_PROV=HERE/'resolution-provenance.json'; OUT_EXPECTED=HERE/'expected-registry-membership.json'; OUT_REGISTRY=HERE/'registry-resolution.json'
EXPECTED_CATALOGUE_SHA='sha256:740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270'

def sha_bytes(b:bytes)->str:return 'sha256:'+hashlib.sha256(b).hexdigest()
def fsha(p:Path)->str:return sha_bytes(p.read_bytes())
def canon(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def main():
 cat=json.loads(BASE_CATALOGUE.read_text()); source=json.loads(BASE_MANIFEST.read_text())
 if cat.get('kind')!='catalogue' or cat.get('version')!='0.1' or len(cat.get('symbols',[]))!=108272: raise RuntimeError('base catalogue pin invalid')
 cat_hash=fsha(BASE_CATALOGUE); manifest_hash=fsha(BASE_MANIFEST)
 if cat_hash!=EXPECTED_CATALOGUE_SHA: raise RuntimeError('base catalogue hash changed')
 by_usr={}; by_path={}
 for item in cat['symbols']:
  usr=item.get('usr'); path=item.get('path')
  if not isinstance(usr,str) or not isinstance(path,str): raise RuntimeError('malformed catalogue symbol')
  if usr in by_usr: raise RuntimeError('duplicate catalogue USR '+usr)
  by_usr[usr]=item; by_path.setdefault(path,[]).append(item)
 resolved=copy.deepcopy(source); rows=[]; membership=[]
 for bi,block in enumerate(source['blocks']):
  out_block=resolved['blocks'][bi]; out_symbols=[]
  for si,selector in enumerate(block['symbols']):
   if selector.startswith('usr:'):
    usr=selector[4:]; matches=[by_usr[usr]] if usr in by_usr else []; mode='usr'
   else:
    path=selector[5:] if selector.startswith('path:') else selector; matches=by_path.get(path,[]); mode='path'
    if len(matches)==1: usr=matches[0]['usr']
    else: usr=''
   if len(matches)!=1: raise RuntimeError(f'{block["id"]} selector {selector!r} resolves {len(matches)} ways')
   item=matches[0]
   if item.get('status')=='hidden': raise RuntimeError(f'{block["id"]} selector {selector!r} resolves hidden USR')
   out='usr:'+item['usr']; out_symbols.append(out); rows.append({'blockIndex':bi,'blockId':block['id'],'symbolIndex':si,'inputSelector':selector,'selectorMode':mode,'outputSelector':out,'resolvedUsr':item['usr'],'cataloguePath':item['path'],'catalogueStatus':item.get('status'),'catalogueItemSha256':sha_bytes(canon(item))}); membership.append({'blockId':block['id'],'symbolIndex':si,'usr':item['usr']})
  out_block['symbols']=out_symbols
 OUT_MANIFEST.write_text(json.dumps(resolved,indent=2)+'\n')
 expected={'kind':'f2-public-source-binding-membership','version':1,'catalogue':{'path':str(BASE_CATALOGUE.relative_to(ROOT)),'sha256':cat_hash,'symbolCount':len(cat['symbols'])},'manifest':{'path':str(BASE_MANIFEST.relative_to(ROOT)),'sha256':manifest_hash},'blocks':membership}
 OUT_EXPECTED.write_text(json.dumps(expected,indent=2)+'\n')
 provenance={'kind':'f2-public-source-binding-resolution','version':1,'status':'resolved-against-pinned-base-catalogue; no status promotion','baseCatalogue':{'path':str(BASE_CATALOGUE.relative_to(ROOT)),'sha256':cat_hash,'symbolCount':len(cat['symbols'])},'baseManifest':{'path':str(BASE_MANIFEST.relative_to(ROOT)),'sha256':manifest_hash,'blockCount':len(source['blocks'])},'outputManifest':{'path':str(OUT_MANIFEST.relative_to(ROOT)),'sha256':fsha(OUT_MANIFEST)},'selectorCount':len(rows),'pathSelectorsResolved':sum(x['selectorMode']=='path' for x in rows),'usrSelectorsRevalidated':sum(x['selectorMode']=='usr' for x in rows),'resolutions':rows,'finalCandidate':{'status':'pending-final-F1-candidate; no alternate candidate exists in workspace'}}
 OUT_PROV.write_text(json.dumps(provenance,indent=2)+'\n')
 sys.path.insert(0,str(ROOT)); from factory.registry.registry import build_registry
 artifact=build_registry(cat,manifest=OUT_MANIFEST,catalogue_hash=cat_hash,created_at='2026-10-11T00:00:00Z',producer='factory/registry/public-source-binding-v1')
 OUT_REGISTRY.write_text(json.dumps(artifact,indent=2)+'\n')
 print(json.dumps({'catalogueSha256':cat_hash,'baseManifestSha256':manifest_hash,'outputManifestSha256':fsha(OUT_MANIFEST),'blocks':len(resolved['blocks']),'selectors':len(rows),'pathSelectors':provenance['pathSelectorsResolved'],'usrSelectors':provenance['usrSelectorsRevalidated'],'registrySha256':fsha(OUT_REGISTRY)},indent=2))
if __name__=='__main__':main()
