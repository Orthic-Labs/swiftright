#!/usr/bin/env python3
"""Read-only r2 wrapper delta/busy-r1 audit; review output only."""
from pathlib import Path
import json,hashlib,re
repo=Path('/Volumes/D/claude/swiftright');lane=repo/'factory/native/windows/seed-stack-lifecycle-capture-v1';review=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
checks=[]
def check(label,value):
 if not value:raise AssertionError(label)
 checks.append(label)
r1=lane/'root-single-lifecycle-r1.ps1';r2=lane/'root-wait-single-lifecycle-r2.ps1';padding=repo/'factory/native/windows/round1-seeded-native-v5/root-wait-single-padding-r1.ps1';before=r1.read_bytes();after=r2.read_bytes();old=b"'single-stack-lifecycle-r1'";new=b"'single-stack-lifecycle-r2'"
check('r2 exact parent-specified SHA',sha(r2)=='3450c6ba3a4590830619f10b08610f899fde32756457f4e7d02787c82c3b32a9')
check('exact single quoted old runroot',before.count(old)==1)
expected=before.replace(old,new);prefix=after[:-len(expected)]
check('body exactly admitted r1 except one literal',after[len(prefix):]==expected)
allowed=b"$ErrorActionPreference='Stop'\nwhile($true){try{$owner=[IO.File]::ReadAllText('D:\\Claude\\desktop.lock').Trim();if($owner -ceq 'free'){break}}catch{};Start-Sleep -Seconds 3}\n"
check('prefix exact explicit readonly wait grammar',prefix==allowed)
check('prefix copied approved padding wrapper',padding.read_bytes().startswith(prefix))
check('prefix only read exact desktoplock/free guard',prefix.count(b'ReadAllText')==1 and prefix.count(b'D:\\Claude\\desktop.lock')==1 and b"-ceq 'free'" in prefix and b'catch{};Start-Sleep -Seconds 3' in prefix)
check('prefix no mutation/window/task/delete/kill/deadline/output/retry verbs',not re.search(rb'(?i)Write|Set-Content|Add-Content|New-Item|Remove|Delete|Move|Copy|Kill|Terminate|Stop-Process|ScheduledTask|Window|Activate|Foreground|Focus|Deadline|AddSeconds|AddMinutes|Write-Host|Write-Output|Invoke|Start-Process',prefix))
text=expected.decode();invocations=[line for line in text.splitlines() if line.startswith('& ')]
check('one unchanged actual driver invocation',len(invocations)==1 and "& (Join-Path $PSScriptRoot 'run-batch.ps1')" in invocations[0])
check('Count1 stack fresh r2 runroot',"-Case 'stack-overlay'" in invocations[0] and "-Count 1 " in invocations[0] and "-RunRoot (Join-Path $PSScriptRoot 'single-stack-lifecycle-r2')" in invocations[0] and not (lane/'single-stack-lifecycle-r2').exists())
check('compile/exe measured pins unchanged',"-CompileReceiptHash 'e041c9a5aa53a6f0453ee074252fc59eb2e4f28e2cf50db1673eed5d8b01c890'" in invocations[0] and "-ExeHash '5babb498a060380b391a508a13091dd4fbe599670b1197337f096e9f44060b86'" in invocations[0])
check('all hash/control/deadline/driver body bytes unchanged',hashlib.sha256(after[len(prefix):].replace(new,old)).hexdigest()==sha(r1))
manifest=load(lane/'root-stage-manifest.json');check('diagnostic capture frozen source/dependency pins intact',all(sha(repo/e['path'])==e['sha256'].removeprefix('sha256:') for e in manifest['files']))
producer=repo/'factory/native/windows/seed-stack-lifecycle-host-v1';check('diagnostic producer frozen source intact',all(sha(repo/e['path'])==e['sha256'].removeprefix('sha256:') for e in load(producer/'root-stage-manifest.json')['files']))
busy=lane/'single-stack-lifecycle-r1';files=sorted(p for p in busy.rglob('*') if p.is_file());check('busy r1 exact two forensic files',len(files)==2 and sorted(str(p.relative_to(busy)) for p in files)==['batch.json','replays/run-001/dispatch.json'])
batch=load(busy/'batch.json');dispatch=load(busy/'replays/run-001/dispatch.json')
check('busy r1 failed single no retry',batch['status']=='hold-batch-error' and batch['requested']==batch['attempted']==1 and batch['retry'] is False and batch['rows'][0]['status']=='hold-desktop-busy' and batch['error']=='First failed dispatch/lock abort; no retries')
check('busy r1 dispatch bytes joined',len(batch['rows'])==1 and batch['rows'][0]['dispatchHash']==sha(busy/'replays/run-001/dispatch.json'))
check('busy r1 no lock acquired/released/retained',dispatch['status']=='hold-desktop-busy' and all(dispatch[k] is False for k in ['lockAcquired','lockReleased','lockRetainedForUnconfirmedOwnedExit']) and dispatch['error']=='' and dispatch['cleanupErrors']==[])
check('busy r1 no task/window launch',dispatch['taskRetained'] is False and dispatch['windowedDispatch'] is False and not any(p.name in ['config.json','task-result.json','owned-process.json'] or p.name.startswith('native-') for p in busy.rglob('*')))
check('busy observations all nonfree/unacquired',len(dispatch['waitObservations'])>0 and all(x['acquired'] is False and x['state']=='r8-11b lead' for x in dispatch['waitObservations']))
check('busy compile/exe pins preserved for r2',batch['compileReceiptHash']=='e041c9a5aa53a6f0453ee074252fc59eb2e4f28e2cf50db1673eed5d8b01c890' and batch['exeHash']=='5babb498a060380b391a508a13091dd4fbe599670b1197337f096e9f44060b86')
check('busy holds unchanged no evidence promotion',all(x['nativeParity']=='hold' and x['frozenTupleBound'] is False and x['closureBinding'] is None and x['nativeRepetitionQualified'] is False for x in [batch,dispatch]))
report={'kind':'independent-readonly-lifecycle-wait-r2-review-v1','status':'CLEAR_FOR_ROOT_DISPATCH','checks':checks,'checkCount':len(checks),'r1BodySha256':sha(r1),'r2WrapperSha256':sha(r2),'prefixSha256':hashlib.sha256(prefix).hexdigest(),'prefixBytes':len(prefix),'bodyChange':'exactly one single quoted RunRoot literal r1 -> r2','busyR1Status':'hold-desktop-busy','busyR1NativeLaunched':False,'busyR1LockAcquired':False,'busyR1LockReleased':False,'busyObservationCount':len(dispatch['waitObservations']),'freshR2RunRootObserved':True,'readOnlyReview':True,'remoteNativeCompilerGitActions':0,'nativeParity':'hold','frozenTupleBound':False,'evidence':[{'path':str(p.relative_to(repo)),'sha256':'sha256:'+sha(p),'bytes':p.stat().st_size} for p in [r1,r2,padding]+files]}
(review/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'checks':len(checks),'reportSha256':sha(review/'report.json'),'prefixBytes':len(prefix),'busyObservations':len(dispatch['waitObservations'])}))
