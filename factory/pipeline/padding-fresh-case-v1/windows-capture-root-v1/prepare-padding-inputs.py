#!/usr/bin/env python3
"""Materialize explicit fresh Padding Count1/20 source inputs; no execution."""
from __future__ import annotations
import argparse, hashlib, json, os, stat
from pathlib import Path
MAX_FILE=64*1024*1024; MAX_JSON=2*1024*1024; MAX_TOTAL=128*1024*1024
class Hold(ValueError): pass
def regular(p:Path, label:str, limit:int=MAX_FILE):
    st=p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size>limit: raise Hold(f'{label} invalid/bounded')
    return st
def digest(p:Path,label:str,limit:int=MAX_FILE):
    st=regular(p,label,limit); h=hashlib.sha256(); n=0
    with p.open('rb') as f:
      while True:
        b=f.read(1024*1024)
        if not b: break
        n+=len(b)
        if n>limit: raise Hold(f'{label} grew')
        h.update(b)
    if n!=st.st_size: raise Hold(f'{label} changed')
    return h.hexdigest(),n
def readj(p:Path,label:str):
    h,n=digest(p,label,MAX_JSON)
    try: v=json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e: raise Hold(f'{label} JSON invalid') from e
    if not isinstance(v,dict): raise Hold(f'{label} object required')
    return v,h,n
def ref(p:Path,label:str,limit:int=MAX_FILE):
    h,n=digest(p,label,limit); return {'path':str(p.resolve()),'sha256':h,'bytes':n}
def main():
  ap=argparse.ArgumentParser()
  for n in ('case','manifest','tuple','plan','compile-receipt','exe','renderer','serializer','binding','recipe','runtime-tree','context','build-preflight','capture-plan','integration-bindings','helper-manifest','compiled-host-package','output'):
    ap.add_argument('--'+n,dest=n.replace('-','_'),required=True,type=Path)
  ap.add_argument('--count',required=True,type=int,choices=(1,20)); args=ap.parse_args()
  if not args.compiled_host_package.is_dir() or args.compiled_host_package.is_symlink(): raise Hold('compiled host package directory required')
  try:
    case,caseh,caseb=readj(args.case,'case'); man,manh,manb=readj(args.manifest,'manifest'); tup,tuph,tupb=readj(args.tuple,'tuple')
    plan,planh,planb=readj(args.plan,'plan'); rec,rech,recb=readj(args.compile_receipt,'compile receipt')
    if not isinstance(case.get('id'),str) or not isinstance(tup.get('candidateID'),str): raise Hold('fresh case/tuple identity missing')
    tv=tup.get('tuple',tup)
    if not isinstance(tv,dict): raise Hold('tuple body missing')
    source_hash=str(man.get('sourceHash',''))
    if not source_hash: raise Hold('manifest sourceHash missing')
    if man.get('case',{}).get('id') != case['id']: raise Hold('manifest/case id drift')
    if plan.get('case',{}).get('id') not in (None,case['id']): raise Hold('plan/case id drift')
    if rec.get('exitCode') not in (None,0): raise Hold('compile receipt failed')
    refs={
      'case':ref(args.case,'case',MAX_JSON),'manifest':ref(args.manifest,'manifest',MAX_JSON),
      'tuple':ref(args.tuple,'tuple',MAX_JSON),'plan':ref(args.plan,'plan',MAX_JSON),
      'compileReceipt':ref(args.compile_receipt,'compile receipt',MAX_JSON),'executable':ref(args.exe,'executable'),
      'renderer':ref(args.renderer,'renderer'),'serializer':ref(args.serializer,'serializer',MAX_FILE),
      'binding':ref(args.binding,'candidate binding',MAX_JSON),'recipe':ref(args.recipe,'recipe',MAX_JSON),
      'runtimeTree':ref(args.runtime_tree,'runtime source tree',MAX_JSON),
      'buildPreflight':ref(args.build_preflight,'build preflight',MAX_JSON),'capturePlan':ref(args.capture_plan,'capture plan',MAX_JSON),
      'integrationBindings':ref(args.integration_bindings,'integration bindings',MAX_JSON),'context':ref(args.context,'source context',MAX_JSON),'helperManifest':ref(args.helper_manifest,'helper manifest',MAX_JSON),
    }
    out=args.output.resolve()
    if out.exists(): raise Hold('output exists')
    out.parent.mkdir(parents=True,exist_ok=True)
    doc={'kind':'factory-padding-source-inputs-v2','status':'fresh-source-bound-prelaunch','count':args.count,
      'caseID':case['id'],'caseHash':str(man.get('case',{}).get('hash','sha256:'+caseh)),'sourceHash':source_hash,'tupleID':str(tv.get('id',tup.get('candidateID'))),
      'runtimeSourceCommit':str(tv.get('runtimeCommit',man.get('runtimeSourceCommit',''))),'windowsHostHash':str(tv.get('hostHashes',{}).get('windows','')),
      'compiledHostPackagePath':str(args.compiled_host_package.resolve()),
      'rendererPath':str(args.renderer.resolve()),'rendererSha256':refs['renderer']['sha256'],
      'serializerControlSha256':refs['serializer']['sha256'],'exeHash':refs['executable']['sha256'],
      'planHash':refs['plan']['sha256'],'compileReceiptHash':refs['compileReceipt']['sha256'],
      'caseRef':refs['case'],'manifestRef':refs['manifest'],'tupleRef':refs['tuple'],'planRef':refs['plan'],
      'compileRef':refs['compileReceipt'],'exeRef':refs['executable'],'rendererRef':refs['renderer'],'serializerRef':refs['serializer'],
      'bindingRef':refs['binding'],'recipeRef':refs['recipe'],'runtimeSourceTreeRef':refs['runtimeTree'],
      'candidateTupleHash':tuph,'tupleHash':tuph,'candidateBindingHash':refs['binding']['sha256'],'bindingHash':refs['binding']['sha256'],'recipeHash':refs['recipe']['sha256'],
      'contextRef':refs['context'],'buildPreflightPath':refs['buildPreflight']['path'],'buildPreflightHash':refs['buildPreflight']['sha256'],'capturePlanPath':refs['capturePlan']['path'],'capturePlanHash':refs['capturePlan']['sha256'],'integrationBindingsRef':refs['integrationBindings'],'integrationBindingsHash':refs['integrationBindings']['sha256'],'helperManifestPath':refs['helperManifest']['path'],'helperManifestHash':refs['helperManifest']['sha256'],
      'freshIDsRequired':True,'historicalCaseReuse':False,'nativeActions':0,'lockActions':0,'refs':refs}
    raw=(json.dumps(doc,indent=2,sort_keys=True)+'\n').encode();
    if len(raw)>MAX_JSON: raise Hold('output manifest too large')
    out.write_bytes(raw)
  except (OSError,Hold) as e:
    raise SystemExit(f'HOLD: {e}')
if __name__=='__main__': main()
