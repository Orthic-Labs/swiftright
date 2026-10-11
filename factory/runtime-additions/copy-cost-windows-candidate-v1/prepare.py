from pathlib import Path
import hashlib,json,re
H=Path(__file__).resolve().parent;R=H.parents[2];sha=lambda b:hashlib.sha256(b).hexdigest()
current=R/'factory/native/windows/module-origin-37429120-20261011/runtime'
candidate=R/'factory/runtime-additions/additive-copy-cost-v1/runtime-candidate-sources/SwiftRightRuntime'
files=sorted([current/'Package.swift']+list((current/'Sources').rglob('*.swift'))+list((current/'Tests').rglob('*.swift')))
assert len(files)==52
assert sum(len(re.findall(r'func\s+test\w+\s*\(',p.read_text())) for p in (current/'Tests').rglob('*.swift'))==175
assert sha((candidate/'Graph.swift').read_bytes())=='775526e1f667f656adb5c7946e880a7079e9462d5d9815edc9a8a2d4dc4bba93'
assert set(p.name for p in candidate.glob('*.swift'))==set(p.name for p in (current/'Sources/SwiftRightRuntime').glob('*.swift'))
assert [p.name for p in candidate.glob('*.swift') if p.read_bytes()!=(current/'Sources/SwiftRightRuntime'/p.name).read_bytes()]==['Graph.swift']
packet=H/'packet';packet.mkdir(exist_ok=False);variants=[]
for name in ('current','candidate'):
 dest=packet/'variants'/name;rows=[]
 for p in files:
  rel=p.relative_to(current).as_posix();data=(candidate/'Graph.swift').read_bytes() if name=='candidate' and rel=='Sources/SwiftRightRuntime/Graph.swift' else p.read_bytes()
  out=dest/rel;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data);rows.append(dict(path=rel,bytes=len(data),sha256=sha(data)))
 variants.append(dict(name=name,bindings=rows,packageFileCount=len(rows),bindingsSha256=sha(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()),localRoot=dest.relative_to(R).as_posix()))
for p in (packet/'variants/current/Tests').rglob('*.swift'):assert p.read_bytes()==(packet/'variants/candidate/Tests'/p.relative_to(packet/'variants/current/Tests')).read_bytes()
assert '.milliseconds(40)' in (packet/'variants/current/Tests/SwiftRightRuntimeTests/TaskIDTests.swift').read_text()
assert '.milliseconds(120)' in (packet/'variants/current/Tests/SwiftRightRuntimeTests/RuntimeTests.swift').read_text()
test=(packet/'variants/current/Tests/SwiftRightRuntimeTests/PerformanceTests.swift').read_text()
for m in ('isOptimized ? 2 : 80','isOptimized ? 4 : 100','isOptimized ? 15 : 250'):assert m in test
old=R/'factory/runtime-additions/taskid-windows-direct-scp-v1/packet/run-three-variants.ps1'
(H/'runner-preimage-taskid.ps1').write_bytes(old.read_bytes());s=old.read_text()
s=s.replace('RUN-NOW-PERFORMANCE-PAIR-COMPLETE','ROOT-CPU-RELEASE-AND-SOURCE-REVIEW-CLEAR')
s=s.replace('Execution is held until compilerbridge_review performance pair confirmation','Execution requires root CPU release & source review')
s=s.replace('factory-swiftright-taskid-three-input-','factory-swiftright-copycost-input-').replace('factory-swiftright-taskid-three-run-','factory-swiftright-copycost-run-')
s=s.replace('taskid-windows-three-variants-source-plan-v1','copy-cost-windows-candidate-source-plan-v1').replace('taskid-windows-three-variants-receipt-v1','copy-cost-windows-candidate-receipt-v1')
s=s.replace("if(@($plan.variants).Count -ne 3){throw 'Exactly three variants required'}", "if(@($plan.variants).Count -ne 2 -or (($plan.variants.name -join ',') -cne 'current,candidate')){throw 'Exact current/candidate pair required'}")
start=s.index('if($plan.commonPins.filter');end=s.index('\n\nfunction Hash',start)
s=s[:start]+"if($plan.commonPins.configuration -cne 'release' -or $plan.commonPins.fullSuite -ne $true -or [int]$plan.commonPins.sourceTestMethodCount -ne 175 -or [int]$plan.commonPins.taskBodySleepMilliseconds -ne 40 -or [int]$plan.commonPins.settleSleepMilliseconds -ne 120){throw 'Exact full release pair workload pins required'}"+s[end:]
s=s.replace("filter=$plan.commonPins.filter", "filter=$null").replace("fullSuite=$false", "fullSuite=$true")
s=s.replace(",'--filter',$plan.commonPins.filter",'')
s=s.replace("$receipt.environment=[ordered]", "foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256 -or (Get-Item -LiteralPath $t.originalPath).Length -ne $t.bytes){throw ('Pinned compiler differs: '+$t.originalPath)}}\n  $receipt.toolBindingsBefore=$plan.toolBindings\n  $receipt.environment=[ordered]")
s=s.replace("$_.Extension -ieq '.exe'", "$_.Extension -in '.exe','.dll'")
s=s.replace("originalFailureNotFixedClaim=($name -eq 'original')", "TaskIDOutcomePreservedWithoutRetry=$true;candidateIsScratchOnly=($name -eq 'candidate')")
s=s.replace("$receipt.finishedAt=[DateTime]::UtcNow.ToString('o')", "foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256){$receipt.error='Compiler bytes changed during pair'}}\n  $receipt.toolBindingsAfter=$plan.toolBindings\n  $receipt.finishedAt=[DateTime]::UtcNow.ToString('o')")
s=s.replace('declaredTreeSha256=$v.declaredTreeSha256;', 'sourceTreeManifestSha256=$v.bindingsSha256;')
s=s.replace("foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256){$receipt.error='Compiler bytes changed during pair'}}", "try{foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256){throw 'Compiler bytes changed during pair'}}}catch{$receipt.error=[string]$_}")
s=s.replace('function BindingRows', "function ToolRows([object[]]$expected){\n $rows=@()\n foreach($t in @($expected)){\n  $f=Get-Item -LiteralPath $t.originalPath;$actualHash=Hash $t.originalPath\n  if($actualHash -cne $t.sha256 -or [int64]$f.Length -ne [int64]$t.bytes){throw ('Pinned compiler differs: '+$t.originalPath)}\n  $rows += [ordered]@{originalPath=$f.FullName;bytes=[int64]$f.Length;sha256=$actualHash;creationTimeUtc=$f.CreationTimeUtc.ToString('o');lastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')}\n }\n return @($rows)\n}\n"+'function BindingRows')
s=s.replace("foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256 -or (Get-Item -LiteralPath $t.originalPath).Length -ne $t.bytes){throw ('Pinned compiler differs: '+$t.originalPath)}}\n  $receipt.toolBindingsBefore=$plan.toolBindings", '$receipt.toolBindingsBefore=@(ToolRows $plan.toolBindings)')
s=s.replace("try{foreach($t in @($plan.toolBindings)){if((Hash $t.originalPath) -cne $t.sha256){throw 'Compiler bytes changed during pair'}}}catch{$receipt.error=[string]$_}\n  $receipt.toolBindingsAfter=$plan.toolBindings", 'try{$receipt.toolBindingsAfter=@(ToolRows $plan.toolBindings)}catch{$receipt.error=[string]$_}')
s=s.replace('if($errorText){throw $errorText}\nWrite-Output', 'if($receipt.error){throw $receipt.error}\nWrite-Output')
(packet/'run-pair.ps1').write_text(s)
archive=R/'factory/runtime-additions/taskid-windows-direct-scp-v1/native-artifact-archive.json';ad=json.loads(archive.read_text());tools=[]
receipt=json.loads((archive.parent/'results/receipt.json').read_text(encoding='utf-8-sig'))
for n in ('swift','swiftc'):
 f=archive.parent/'results'/(n+'.exe');tools.append(dict(originalPath=receipt['toolchain'][n+'Path'],sha256=sha(f.read_bytes()),bytes=f.stat().st_size,repositoryPath=f.relative_to(R).as_posix()))
for b in ad['files']:
 if b['category']=='compiler':tools.append(dict(originalPath=b['path'],sha256=b['sha256'],bytes=b['bytes'],repositoryPath=(archive.parent/b['localPath']).relative_to(R).as_posix(),chunks=b['chunks']))
report=R/'factory/runtime-additions/additive-copy-cost-v1/independent-review/report-r4.json'
plan=dict(schema='copy-cost-windows-candidate-source-plan-v1',status='prepared-no-remote-or-compiler-execution',currentRoot=current.relative_to(R).as_posix(),candidateSourceRoot=candidate.relative_to(R).as_posix(),onlySourceDifference='Sources/SwiftRightRuntime/Graph.swift',candidateGraphSha256=sha((candidate/'Graph.swift').read_bytes()),variants=variants,commonPins=dict(configuration='release',fullSuite=True,sourceTestMethodCount=175,taskBodySleepMilliseconds=40,settleSleepMilliseconds=120,performanceBoundsMilliseconds=[2,4,15],order=['current','candidate'],eachVariantExactlyOnce=True,retries=0,originalTestBytesPreserved=True),toolBindings=tools,toolArchive=dict(path=archive.relative_to(R).as_posix(),sha256=sha(archive.read_bytes())),sourceReview=dict(path=report.relative_to(R).as_posix(),sha256=sha(report.read_bytes())),runnerSha256=sha(s.encode()),executionHold='Root CPU release & independent source review required; preparation only')
(packet/'source-plan.json').write_text(json.dumps(plan,indent=2)+'\n')
rows=[dict(path=p.relative_to(R).as_posix(),bytes=p.stat().st_size,sha256=sha(p.read_bytes())) for p in sorted(packet.rglob('*')) if p.is_file()]
(H/'packet-manifest.json').write_text(json.dumps(dict(schema='copy-cost-windows-candidate-packet-v1',sourceFileCount=104,fileCount=len(rows),files=rows),indent=2)+'\n')
print('prepared',len(rows),'packet files;175 test methods per variant; Graph-only diff; no execution')
