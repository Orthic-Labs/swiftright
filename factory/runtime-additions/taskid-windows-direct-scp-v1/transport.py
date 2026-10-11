from pathlib import Path
import subprocess,hashlib,json,datetime,base64,sys
H=Path(__file__).resolve().parent
REMOTE_INPUT=r'D:\Claude\factory-swiftright-taskid-three-input-direct-scp-v2-20261011-1207'
REMOTE_RUN=r'D:\Claude\factory-swiftright-taskid-three-run-direct-scp-v2-20261011-1207'
sha=lambda b:hashlib.sha256(b).hexdigest()
def ps(s):return ['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','win','powershell','-NoProfile','-EncodedCommand',base64.b64encode(s.encode('utf-16le')).decode()]
def call(name,argv,timeout=60):
 out=H/(name+'.stdout.bin');err=H/(name+'.stderr.bin');start=datetime.datetime.now(datetime.timezone.utc).isoformat()
 with out.open('wb') as o,err.open('wb') as e:
  p=subprocess.Popen(argv,stdout=o,stderr=e,cwd=H)
  try:code=p.wait(timeout=timeout);timed=False
  except subprocess.TimeoutExpired:p.kill();code=p.wait();timed=True
 rec=dict(argv=argv,cwd=str(H),startedAt=start,endedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),pid=p.pid,returncode=code,timedOut=timed,stdout=dict(path=str(out),bytes=out.stat().st_size,sha256=sha(out.read_bytes())),stderr=dict(path=str(err),bytes=err.stat().st_size,sha256=sha(err.read_bytes())))
 (H/(name+'.json')).write_text(json.dumps(rec,indent=2)+'\n');print(name,code,out.read_text(errors='replace')[:2000],err.read_text(errors='replace')[:1000],flush=True)
 if code:raise SystemExit(code)
 return rec
if (sys.argv[1] if len(sys.argv)>1 else '')=='upload':
 call('remote-init-v2',ps(f"$ErrorActionPreference='Stop';$p='{REMOTE_INPUT}';if(Test-Path -LiteralPath $p){{throw 'Fresh input root already exists'}};[IO.Directory]::CreateDirectory($p)|Out-Null;Write-Output $p"))
 call('scp-packet-v2',['scp','-r','-o','BatchMode=yes','-o','ConnectTimeout=10',str(H/'packet/variants'),str(H/'packet/source-plan.json'),str(H/'packet/run-three-variants.ps1'),'win:'+REMOTE_INPUT.replace('\\','/')+'/'])
 runner=sha((H/'packet/run-three-variants.ps1').read_bytes());plan=sha((H/'packet/source-plan.json').read_bytes())
 script=r'''$ErrorActionPreference='Stop';$root='ROOT';function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()};$planPath=Join-Path $root 'source-plan.json';if((Hash $planPath)-cne 'PLANHASH'){throw 'Plan differs'};$runner=Join-Path $root 'run-three-variants.ps1';if((Hash $runner)-cne 'RUNHASH'){throw 'Runner differs'};$plan=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json;$rows=@();foreach($v in $plan.variants){$r=Join-Path $root ('variants\'+$v.name);$files=@(Get-ChildItem -LiteralPath $r -Recurse -File);if($files.Count -ne 45){throw 'Not 45 files'};foreach($b in $v.bindings){$f=Join-Path $r $b.path;if((Get-Item -LiteralPath $f).Length-ne $b.bytes -or (Hash $f)-cne $b.sha256){throw ('Binding differs '+$v.name+' '+$b.path)};$rows+=[ordered]@{variant=$v.name;path=$b.path;bytes=$b.bytes;sha256=$b.sha256}}};if(@(Get-ChildItem -LiteralPath $root -Recurse -File).Count -ne 137){throw 'Unexpected packet file'};$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ($errors|Out-String)};$newItem=Get-Command New-Item;if(-not $newItem.Parameters.ContainsKey('Path')){throw 'New-Item Path unavailable'};$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe';$swiftc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swiftc.exe';[ordered]@{schema='taskid-direct-scp-remote-preflight-v1';utc=[DateTime]::UtcNow.ToString('o');inputRoot=$root;sourceFiles=$rows.Count;files=$rows;sourcePlanHash=(Hash $planPath);runnerHash=(Hash $runner);powershellVersion=$PSVersionTable.PSVersion.ToString();parserErrors=0;newItemLiteralPathSupported=$newItem.Parameters.ContainsKey('LiteralPath');newItemPathSupported=$newItem.Parameters.ContainsKey('Path');swiftPath=$swift;swiftHash=(Hash $swift);swiftcPath=$swiftc;swiftcHash=(Hash $swiftc);compilerExecutions=0;testExecutions=0}|ConvertTo-Json -Depth 12'''.replace('ROOT',REMOTE_INPUT).replace('PLANHASH',plan).replace('RUNHASH',runner)
 call('remote-preflight-v2',ps(script))
elif (sys.argv[1] if len(sys.argv)>1 else '')=='run':
 s=f"& '{REMOTE_INPUT}\\run-three-variants.ps1' -InputRoot '{REMOTE_INPUT}' -RunRoot '{REMOTE_RUN}' -ExecutionToken 'RUN-NOW-PERFORMANCE-PAIR-COMPLETE'"
 # SSH runs asynchronously; poll local PID independently, retain raw streams directly.
 out=(H/'run-dispatch.stdout.bin').open('wb');err=(H/'run-dispatch.stderr.bin').open('wb');argv=ps(s);p=subprocess.Popen(argv,stdout=out,stderr=err,cwd=H);out.close();err.close()
 (H/'run-dispatch-start.json').write_text(json.dumps(dict(argv=argv,cwd=str(H),pid=p.pid,startedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),remoteInputRoot=REMOTE_INPUT,remoteRunRoot=REMOTE_RUN),indent=2)+'\n');print('owned SSH pid',p.pid,flush=True)
 code=p.wait()
 rec=json.loads((H/'run-dispatch-start.json').read_text());rec.update(endedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),returncode=code)
 for name in ('stdout','stderr'):
  f=H/('run-dispatch.'+name+'.bin');rec[name]=dict(path=str(f),bytes=f.stat().st_size,sha256=sha(f.read_bytes()))
 (H/'run-dispatch-finished.json').write_text(json.dumps(rec,indent=2)+'\n');print('finished',code,flush=True)
elif (sys.argv[1] if len(sys.argv)>1 else '')=='fetch':
 results=H/'results';results.mkdir(exist_ok=True)
 call('scp-receipt',['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+REMOTE_RUN.replace('\\','/')+'/receipt.json',str(results)])
 receipt=json.loads((results/'receipt.json').read_text(encoding='utf-8-sig'))
 for v in receipt['variants']:
  dest=results/v['name'];dest.mkdir(exist_ok=True)
  call('scp-process-'+v['name'],['scp','-r','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+REMOTE_RUN.replace('\\','/')+'/'+v['name']+'/process',str(dest)])
  for i,e in enumerate(v['testRunner']):
   call('scp-runner-'+v['name']+'-'+str(i),['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+e['path'].replace('\\','/'),str(dest/('test-runner-'+str(i)+'.exe'))])
 for n in ('swift','swiftc'):
  path=receipt['toolchain'][n+'Path']
  call('scp-tool-'+n,['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+path.replace('\\','/'),str(results/(n+'.exe'))])
