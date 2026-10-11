from pathlib import Path
import argparse,hashlib,json,base64,subprocess,datetime,os
H=Path(__file__).resolve().parent;R=H.parents[2];P=H/'packet';sha=lambda b:hashlib.sha256(b).hexdigest()
def verify():
 plan=json.loads((P/'source-plan.json').read_bytes())
 assert [v['name'] for v in plan['variants']]==['current','candidate']
 assert plan['runnerSha256']==sha((P/'run-pair.ps1').read_bytes())
 for v in plan['variants']:
  root=P/'variants'/v['name'];expected={b['path']:b for b in v['bindings']};actual={f.relative_to(root).as_posix():f for f in root.rglob('*') if f.is_file()}
  assert set(actual)==set(expected) and len(actual)==52
  for rel,f in actual.items():assert f.stat().st_size==expected[rel]['bytes'] and sha(f.read_bytes())==expected[rel]['sha256']
 diffs=[b['path'] for b,c in zip(plan['variants'][0]['bindings'],plan['variants'][1]['bindings']) if b!=c];assert diffs==['Sources/SwiftRightRuntime/Graph.swift']
 for key in ('toolArchive','sourceReview'):
  ref=plan[key];assert sha((R/ref['path']).read_bytes())==ref['sha256']
 return plan

def remote_roots():
 suffix=sha((P/'source-plan.json').read_bytes())[:12]
 return 'D:\\Claude\\factory-swiftright-copycost-input-'+suffix,'D:\\Claude\\factory-swiftright-copycost-run-'+suffix

def argv(script):return ['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','win','powershell','-NoProfile','-EncodedCommand',base64.b64encode(script.encode('utf-16le')).decode()]
def invoke(name,args,timeout=60):
 start=datetime.datetime.now(datetime.timezone.utc).isoformat();out=H/(name+'.stdout.bin');err=H/(name+'.stderr.bin')
 with out.open('wb') as o,err.open('wb') as e:
  proc=subprocess.Popen(args,cwd=H,stdout=o,stderr=e)
  try:code=proc.wait(timeout=timeout);timed=False
  except subprocess.TimeoutExpired:proc.kill();code=proc.wait();timed=True
 rec=dict(argv=args,cwd=str(H),startedAt=start,endedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),pid=proc.pid,returncode=code,timedOut=timed)
 for name2,f in (('stdout',out),('stderr',err)):rec[name2]=dict(path=f.relative_to(R).as_posix(),bytes=f.stat().st_size,sha256=sha(f.read_bytes()))
 (H/(name+'.json')).write_text(json.dumps(rec,indent=2)+'\n')
 if code:raise SystemExit(code)
 return rec

def main():
 a=argparse.ArgumentParser();a.add_argument('action',choices=['verify','upload','run']);mode=a.parse_args().action;plan=verify();input_root,run_root=remote_roots()
 if mode=='verify':
  print(json.dumps(dict(status='local-preparation-verified',sourceFiles=104,sourceTestMethodsEach=175,onlyDifference='Graph.swift',sourcePlanSha256=sha((P/'source-plan.json').read_bytes()),runnerSha256=plan['runnerSha256'],proposedInputRoot=input_root,proposedRunRoot=run_root,remoteInvocations=0,compilerInvocations=0),indent=2));return
 if os.environ.get('COPYCOST_SOURCE_REVIEW')!='ROOT-SOURCE-REVIEW-CLEAR':raise SystemExit('Held for root source review; no remote invocation')
 if mode=='upload':
  invoke('remote-init',argv("$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$p='"+input_root+"';if(Test-Path -LiteralPath $p){throw 'Fresh owned input root already exists'};[IO.Directory]::CreateDirectory($p)|Out-Null;Write-Output $p"))
  invoke('scp-packet',['scp','-r','-o','BatchMode=yes','-o','ConnectTimeout=10',str(P/'variants'),str(P/'source-plan.json'),str(P/'run-pair.ps1'),'win:'+input_root.replace('\\','/')+'/'])
  script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$root='ROOT';function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()};$p=Join-Path $root 'source-plan.json';if((Hash $p)-cne 'PLAN'){throw 'Plan bytes differ'};$plan=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;$runner=Join-Path $root 'run-pair.ps1';if((Hash $runner)-cne $plan.runnerSha256){throw 'Runner differs'};$rows=@();foreach($v in $plan.variants){$r=Join-Path $root ('variants\'+$v.name);if(@(Get-ChildItem -LiteralPath $r -Recurse -File).Count -ne 52){throw 'Source count differs'};foreach($b in $v.bindings){$f=Join-Path $r $b.path;if((Get-Item -LiteralPath $f).Length -ne $b.bytes -or (Hash $f)-cne $b.sha256){throw ('Source differs: '+$f)};$rows+=[ordered]@{variant=$v.name;path=$b.path;bytes=$b.bytes;sha256=$b.sha256}}};if(@(Get-ChildItem -LiteralPath $root -Recurse -File).Count -ne106){throw 'Packet count differs'};$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ($errors|Out-String)};foreach($t in $plan.toolBindings){if((Hash $t.originalPath)-cne $t.sha256 -or (Get-Item -LiteralPath $t.originalPath).Length-ne$t.bytes){throw 'Tool bytes differ'}};[ordered]@{utc=[DateTime]::UtcNow.ToString('o');inputRoot=$root;sourceFiles=$rows.Count;files=$rows;sourcePlanHash=(Hash $p);runnerHash=(Hash $runner);parserErrors=0;powershellVersion=$PSVersionTable.PSVersion.ToString();compilerInvocations=0;testInvocations=0}|ConvertTo-Json -Depth 12'''.replace('ROOT',input_root).replace('PLAN',sha((P/'source-plan.json').read_bytes()))
  invoke('remote-preflight',argv(script));return
 if os.environ.get('COPYCOST_CPU_RELEASE')!='ROOT-CPU-RELEASE':raise SystemExit('Held for root CPU release; no compiler invocation')
 # Async tool session may yield while local launcher waits; native runner owns900s per-process deadline.
 script="& '"+input_root+"\\run-pair.ps1' -InputRoot '"+input_root+"' -RunRoot '"+run_root+"' -ExecutionToken 'ROOT-CPU-RELEASE-AND-SOURCE-REVIEW-CLEAR'"
 invoke('run-dispatch',argv(script),timeout=1900)
if __name__=='__main__':main()
