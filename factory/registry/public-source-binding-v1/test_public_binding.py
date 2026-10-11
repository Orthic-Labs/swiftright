#!/usr/bin/env python3
import copy,json,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; sys.path.insert(0,str(ROOT)); from factory.registry.registry import RegistryBuildError,build_registry
CAT=json.loads((ROOT/'factory/catalogue/evidence/catalogue.json').read_text()); BASE=json.loads((ROOT/'factory/registry/manifest.json').read_text())
def rejected(man,cat=CAT):
 try: build_registry(cat,manifest=man,created_at='2026-10-11T00:00:00Z'); return False
 except RegistryBuildError:return True
def main():
 assert not rejected(BASE)
 x=copy.deepcopy(BASE); x['blocks'][0]['symbols'][0]='usr:missing'; assert rejected(x)
 x=copy.deepcopy(BASE); x['blocks'][0]['symbols'][0]='path:Foundation.SystemFormatStyle.DateOffset.currency(code:)'; assert rejected(x)
 x=copy.deepcopy(BASE); target=next(i for i in x['blocks'][0]['symbols'] if i.startswith('usr:'))[4:]; c=copy.deepcopy(CAT); next(i for i in c['symbols'] if i['usr']==target)['status']='hidden'; assert rejected(x,c)
 x=copy.deepcopy(BASE); x['blocks'][0]['symbols'][0]='usr:'+x['blocks'][0]['symbols'][1][4:]; assert rejected(x)
 print('public-source-binding-v1 tests: baseline pass; unresolved, ambiguous path, hidden status, & repeated-USR controls rejected')
if __name__=='__main__':main()
