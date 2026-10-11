from pathlib import Path
import datetime,hashlib,json,os,subprocess,shutil
ROOT=Path('/Volumes/D/claude/swiftright')
PACK=ROOT/'factory/runtime-additions/additive-copy-cost-v1'
OUT=PACK/'actual-r4'
CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/additive-copy-cost-root-r4-20261011')
CACHE.mkdir(exist_ok=False)
assert CACHE.resolve().is_relative_to(Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory'))
assert CACHE.stat().st_dev != ROOT.stat().st_dev, 'Scratch must use internal disk'
TOOL=Path('/usr/bin/swiftc')
PROBE=PACK/'actual-r3-controls.swift'
PLAN=PACK/'proposed-actual-r3-source-plan.json'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def snapshot(path):
 return [{'path':str(p.relative_to(path)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(path.rglob('*')) if p.is_file()]
roots={'current':ROOT/'factory/native/windows/module-origin-37429120-20261011/runtime/Sources/SwiftRightRuntime','candidate':PACK/'runtime-candidate-sources/SwiftRightRuntime'}
source_before={key:snapshot(path) for key,path in roots.items()}
inputs_before={'toolSha256':sha(TOOL),'probeSha256':sha(PROBE),'planSha256':sha(PLAN),'trees':source_before}
(OUT/'inputs-before.json').write_text(json.dumps(inputs_before,indent=2)+'\n')
plan=json.loads(PLAN.read_text())
for key,path in roots.items():
 assert sha(path/'Graph.swift')==plan['sourcePins'][key+'GraphSha256']
 assert sha(path/'Controls.swift')==plan['sourcePins'][key+'ControlsSha256']
 copied=CACHE/key/'Sources';copied.mkdir(parents=True)
 for row in source_before[key]:
  target=copied/row['path'];target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((path/row['path']).read_bytes());assert sha(target)==row['sha256']
 assert snapshot(copied)==source_before[key]
(CACHE/'R3Probe.swift').write_bytes(PROBE.read_bytes())
assert sha(CACHE/'R3Probe.swift')==inputs_before['probeSha256']
records=[]
def run(label,argv,cwd,deadline):
 assert Path(cwd).resolve().is_relative_to(CACHE.resolve())
 if label.endswith('-run'):assert Path(argv[0]).resolve().is_relative_to(CACHE.resolve())
 started=now();timedout=False
 with (OUT/(label+'.stdout.bin')).open('wb') as out,(OUT/(label+'.stderr.bin')).open('wb') as err:
  p=subprocess.Popen(argv,cwd=cwd,stdout=out,stderr=err)
  try:code=p.wait(timeout=deadline)
  except subprocess.TimeoutExpired:
   timedout=True;p.kill();code=p.wait(timeout=10)
 r={'label':label,'argv':argv,'cwd':str(cwd),'pid':p.pid,'startedAt':started,'endedAt':now(),'exitCode':code,'timedOut':timedout,'deadlineSeconds':deadline,'executableSha256':sha(Path(argv[0])),'stdoutSha256':sha(OUT/(label+'.stdout.bin')),'stderrSha256':sha(OUT/(label+'.stderr.bin'))}
 records.append(r);(OUT/'processes.json').write_text(json.dumps(records,indent=2)+'\n')
 if code or timedout:raise RuntimeError('Actual process failed: '+label)
run('compiler-version',[str(TOOL),'--version'],CACHE,20)
outputs={}
for key in ['current','candidate']:
 sources=[str(p) for p in sorted((CACHE/key/'Sources').glob('*.swift'))]
 assert len(sources)==len(source_before[key])
 exe=CACHE/key/'controls'
 argv=[str(TOOL),'-O','-parse-as-library','-module-name','SwiftRightRuntime','-module-cache-path',str(CACHE/'module-cache'),*sources,str(CACHE/'R3Probe.swift'),'-o',str(exe)]
 run(key+'-compile',argv,CACHE,180)
 before_exe=sha(exe);run(key+'-run',[str(exe)],CACHE,20);assert sha(exe)==before_exe
 outputs[key]=(OUT/(key+'-run.stdout.bin')).read_bytes()
 (OUT/'binaries').mkdir(exist_ok=True);(OUT/'binaries'/(key+'-controls')).write_bytes(exe.read_bytes())
 assert sha(OUT/'binaries'/(key+'-controls'))==before_exe
 assert snapshot(CACHE/key/'Sources')==source_before[key]
inputs_after={'toolSha256':sha(TOOL),'probeSha256':sha(PROBE),'planSha256':sha(PLAN),'trees':{key:snapshot(path) for key,path in roots.items()}}
(OUT/'inputs-after.json').write_text(json.dumps(inputs_after,indent=2)+'\n');assert inputs_after==inputs_before
assert outputs['current']==outputs['candidate'], 'Outputs differ'
rows=dict(line.split('=',1) for line in outputs['current'].decode().splitlines())
for key in ['styleIndependentEqual','styleIndependentUnequal','defaultStyleNil','additionsIndependentEqual','additionsIndependentUnequal','shapeIndependentUnequal','copyRetainedOriginal','plainImageSizingNil','resizedImageSizingPresent','toggleStyleEqual','toggleStyleUnequal','toggleLabelsHidden']:assert rows[key]=='true', (key,rows[key])
assert rows['customFontFamily']=='ProbeFamily'
receipt={'kind':'root-actual-internal-macos-controls','internalScratch':str(CACHE),'internalDevice':CACHE.stat().st_dev,'repositoryDevice':ROOT.stat().st_dev,'inputsBeforeSha256':sha(OUT/'inputs-before.json'),'inputsAfterSha256':sha(OUT/'inputs-after.json'),'immutableInputs':inputs_before==inputs_after,'processes':records,'outputsEqual':True,'rows':rows,'performanceClaim':False,'productionChanged':False,'sourceOnlyCandidate':True}
(OUT/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':'controls-passed','receiptSha256':sha(OUT/'receipt.json'),'processes':len(records),'rows':len(rows)}))
