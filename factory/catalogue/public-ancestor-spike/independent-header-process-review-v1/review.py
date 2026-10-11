from pathlib import Path
import copy,hashlib,json,importlib.util,sys,contextlib,io,re
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[4]; HERE=Path(__file__).resolve().parent
BASE=ROOT/'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1'; V2=BASE/'developer-spatial-symbols-process-v2'; SF=BASE/'swift-foundation'
refs={}
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):refs[str(p)]={'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size};return refs[str(p)]
def module(p,name):s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
v=module(V2/'verify_process_receipts.py','verify');cap=module(SF/'capture_swift_foundation.py','capture'); ext=module(BASE/'developer-spatial-symbols/capture_external_indexes.py','ext');ev=json.loads((V2/'process-evidence-v2.json').read_text());sf=json.loads((SF/'swift-foundation-index-evidence.json').read_text());rows=[]
for p in [V2/'verify_process_receipts.py',V2/'capture_process_receipts.py',V2/'test_process_receipts.py',V2/'process-evidence-v2.json',V2/'archive-manifest.json',SF/'capture_swift_foundation.py',SF/'verify_swift_foundation.py',SF/'swift-foundation-index-evidence.json']:ref(p)
for row in ev['modules']:
 rpath=ROOT/row['receipt'];ref(rpath);r=json.loads(rpath.read_text());req=Path(r['request']['path']);source=Path(r['source']['path']);raw=Path(r['process']['stdout']['path']);err=Path(r['process']['stderr']['path']);args=json.loads(re.search(r'key.compilerargs:\s*(\[.*?\])',req.read_text(),re.S).group(1));h=ext.parse_headers(source);mt,removed,fwd=ext.transform(h['main']);it,ri,fi=ext.transform(h['ignorable']);expected=[str(source),*mt,*it,'-sdk',str(cap.SDK),'-target',cap.TARGET];assert args==expected
 assert type(r['process']['returncode']) is int and r['process']['returncode']==0
 for key,p in [('source',source),('request',req)]:assert r[key]['sha256']==sha(p) and r[key]['bytes']==p.stat().st_size;ref(p)
 for key,p in [('stdout',raw),('stderr',err)]:assert r['process'][key]['sha256']==sha(p) and r['process'][key]['bytes']==p.stat().st_size;ref(p)
 old=BASE/'developer-spatial-symbols/raw'/raw.name;assert sha(old)==sha(raw);ref(old)
 for key,t in r['toolchain'].items():p=Path(t['path']);assert sha(p)==t['sha256'] and p.stat().st_size==t['bytes'];ref(p)
 assert args.count('-target')==1 and '-target-variant' not in args and '-target-arch-variant' not in args
 rows.append({'module':row['module'],'actualExitIsStrictIntZero':True,'liveSourceHashMatches':True,'fullHeaderFlagsTransformedExact':True,'productionTarget':'arm64-apple-macosx27.0','targetVariantAbsent':True,'rawV1EqualsV2':True,'timestampsRecorded':True,'receipt':ref(rpath)})
for row in sf['modules']:
 source=Path(row['source']['path']);main,tokens,ign,it=cap.parse_headers(source);mt,_,_=cap.transform(tokens);it,_,_=cap.transform(it);expected=[str(source),*mt,*it,'-sdk',str(cap.SDK),'-target',cap.TARGET];request=ROOT/row['request']['path'];actual=json.loads(re.search(r'key.compilerargs:\s*(\[.*?\])',request.read_text(),re.S).group(1));assert actual==expected==row['headerFlags']['compilerArgs']
 p=row['process'];assert p['argv']==['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(request)] and p['cwd']==str(ROOT);assert type(p['exit']) is int and p['exit']==0
 for key in ['stdout','stderr']:assert sha(ROOT/p[key]['path'])==p[key]['sha256'];ref(ROOT/p[key]['path'])
 assert sha(Path(row['source']['path']))==row['source']['sha256'];ref(Path(row['source']['path']));ref(ROOT/row['request']['path']);ref(ROOT/row['request']['preimagePath'])
 assert row['headerFlags']['compilerArgs'].count('-target')==1 and '-target-variant' not in row['headerFlags']['compilerArgs'] and '-target-arch-variant' not in row['headerFlags']['compilerArgs']
 for tool in sf['toolchain'].values():assert sha(Path(tool['path']))==tool['sha256'];ref(Path(tool['path']))
assert len(rows)==4
manifest=json.loads((V2/'archive-manifest.json').read_text());assert len(manifest['entries'])==manifest['entryCount']
for item in manifest['entries']:
 p=V2/item['path'];assert sha(p)==item['sha256'] and p.stat().st_size==item['bytes'];ref(p)
fixtures=HERE/'fixtures';fixtures.mkdir(exist_ok=True)
def validate(d,label):
 p=fixtures/(label+'.evidence.json');p.write_text(json.dumps(d)+'\n');old=sys.argv;sys.argv=['verify','--evidence',str(p)];stream=io.StringIO()
 try:
  with contextlib.redirect_stdout(stream),contextlib.redirect_stderr(stream):v.main()
  accepted=True;error=None
 except Exception as e:accepted=False;error=str(e)
 finally:sys.argv=old
 return {'fault':label,'accepted':accepted,'error':error,'productionVerifierInvokedInProcess':True,'captureProcessesLaunched':0}
results=[validate(ev,'baseline')];original=json.loads((ROOT/ev['modules'][0]['receipt']).read_text())
for label,mut in [('booleanExit',lambda r:r['process'].update(returncode=False)),('floatExit',lambda r:r['process'].update(returncode=0.0)),('nonzeroExit',lambda r:r['process'].update(returncode=1)),('booleanEpochs',lambda r:r['process'].update(startedAtEpochNs=False,finishedAtEpochNs=True)),('fabricatedTimestampStrings',lambda r:r['process'].update(startedAt='fabricated',finishedAt='fabricated')),('wrongToolHash',lambda r:r['toolchain']['sourcekitLsp'].update(sha256='sha256:'+'0'*64)),('wrongSourceHash',lambda r:r['source'].update(sha256='sha256:'+'0'*64)),('wrongArgv',lambda r:r['process'].update(argv=['fake'])),('wrongCwd',lambda r:r['process'].update(cwd='/tmp')),('wrongRequestHash',lambda r:r['request'].update(sha256='sha256:'+'0'*64))]:
 r=copy.deepcopy(original);mut(r);p=fixtures/(label+'.receipt.json');p.write_text(json.dumps(r)+'\n');d=copy.deepcopy(ev);d['modules'][0]['receipt']=str(p.relative_to(ROOT));results.append(validate(d,label))
source=Path(original['source']['path']);changed=bytearray(source.read_bytes());changed[-1]^=1;p=fixtures/'changed-source.swiftinterface';p.write_bytes(changed);r=copy.deepcopy(original);r['source']['path']=str(p);rp=fixtures/'actualSourceBytesDrift.receipt.json';rp.write_text(json.dumps(r)+'\n');d=copy.deepcopy(ev);d['modules'][0]['receipt']=str(rp.relative_to(ROOT));results.append(validate(d,'actualSourceBytesDrift'))
for label,mut in [('wrongTarget',lambda d:d.update(target='x86_64-apple-macosx27.0')),('wrongSDK',lambda d:d.update(sdk='/tmp/fake.sdk')),('duplicateModule',lambda d:d['modules'].append(copy.deepcopy(d['modules'][0])))]:
 d=copy.deepcopy(ev);mut(d);results.append(validate(d,label))
r={'kind':'independent-header-process-review-v1','reviewScope':'read-only existing captures/code; pure validator faults in owned directory only','capturesRerun':0,'subprocessesLaunchedByReview':0,'producerEdits':0,'swiftFoundation':{'genuineCompletedProcessMetadata':True,'processCount':2,'timestampsRecorded':False,'fullHeaderFlagRequestArgvCwdJoinsExact':True,'timingClaimAllowed':False,'exitMetadataFabricated':False,'sourceEvidence':'capture_module assigns result=subprocess.run then process.exit=result.returncode & writes result.stdout/stderr; no fabricated exit constant','scope':'Raw header index facts only; no nominal eligibility inference'},'developerSpatialSymbolsV2':{'genuineCompletedProcessMetadata':True,'processCount':4,'rows':rows,'immediateReceiptsBeforeParsing':True,'archiveManifestAllEntriesMatch':True,'rawV1EqualsV2':True,'actualCurrentBytesJoinsClear':True,'executionBoundary':'Producer CompletedProcess metadata is genuine; xcrun backend resolution/environment/PID are not independently recorded; static expected tool bytes match current files.','productionVerifierGuardsClear':False,'faults':results,'findings':['Boolean/float zero returncodes accepted by ==0 guard.','Boolean epochs &fabricated nonempty timestamp strings accepted.','Recorded tool hashes ignored by production verifier.','Actual source bytes can drift at same length with original recorded source hash &remain accepted.','Wrong SDK metadata &duplicate module entries accepted.','Existing five fault controls cover only status/target/link/missingreceipt/nonzeroexit.'],'scope':'Actual recorded process joins clear independently; production automatic acceptance remains held until guard faults repaired. No nominal eligibility inference.'},'references':sorted(refs.values(),key=lambda x:x['path'])}
(HERE/'report.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'actualProcessesReviewed':6,'faultResults':results,'reportHash':sha(HERE/'report.json')},indent=2))
if __name__=='__main__':pass
