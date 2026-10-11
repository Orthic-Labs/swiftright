from pathlib import Path
import json,hashlib,shutil,re
H=Path(__file__).resolve().parent; R=H.parents[2]
old=R/'factory/runtime-additions/taskid-windows-three-variants-v1'
sha=lambda b:hashlib.sha256(b).hexdigest()
p=json.loads((old/'source-plan.json').read_bytes())
packet=H/'packet';packet.mkdir(exist_ok=True)
shutil.copyfile(old/'source-plan.json',packet/'source-plan.json')
src=(old/'run-three-variants.ps1').read_text();(H/'runner-preimage.ps1').write_bytes((old/'run-three-variants.ps1').read_bytes())
new=re.sub(r'\$input\b','$ownedInputRoot',src,flags=re.I)
new=re.sub(r'(New-Item -ItemType Directory) -LiteralPath',r'\1 -Path',new)
# Preserve redirected native streams as original bytes rather than decoded/reencoded text.
new=new.replace("$p=$null;$stdout='';$stderr='';", "$p=$null;$stdout='';$stderr='';$stdoutFile=$null;$stderrFile=$null;")
new=new.replace('$stdoutTask=$p.StandardOutput.ReadToEndAsync();$stderrTask=$p.StandardError.ReadToEndAsync()', "$stdoutFile=[IO.File]::Create((Join-Path $outDir 'stdout.txt'));$stderrFile=[IO.File]::Create((Join-Path $outDir 'stderr.txt'))\n    $stdoutTask=$p.StandardOutput.BaseStream.CopyToAsync($stdoutFile);$stderrTask=$p.StandardError.BaseStream.CopyToAsync($stderrFile)")
new=new.replace('$stdout=$stdoutTask.GetAwaiter().GetResult();$stderr=$stderrTask.GetAwaiter().GetResult()', "$stdoutTask.GetAwaiter().GetResult();$stderrTask.GetAwaiter().GetResult()\n    $stdoutFile.Dispose();$stderrFile.Dispose();$stdoutFile=$null;$stderrFile=$null\n    $stdout=[IO.File]::ReadAllText((Join-Path $outDir 'stdout.txt'));$stderr=[IO.File]::ReadAllText((Join-Path $outDir 'stderr.txt'))")
new=new.replace("[IO.File]::WriteAllText((Join-Path $outDir 'stdout.txt'),$stdout,(New-Object Text.UTF8Encoding($false)))\n    [IO.File]::WriteAllText((Join-Path $outDir 'stderr.txt'),$stderr,(New-Object Text.UTF8Encoding($false)))", "$stdoutPath=Join-Path $outDir 'stdout.txt';$stderrPath=Join-Path $outDir 'stderr.txt'\n    if($stdoutFile){$stdoutFile.Dispose()};if($stderrFile){$stderrFile.Dispose()}\n    if(-not(Test-Path -LiteralPath $stdoutPath)){[IO.File]::WriteAllBytes($stdoutPath,[byte[]]@())}\n    if(-not(Test-Path -LiteralPath $stderrPath)){[IO.File]::WriteAllBytes($stderrPath,[byte[]]@())}")
(packet/'run-three-variants.ps1').write_text(new)
count=0
for v in p['variants']:
 root=R/v['localRoot']; dest=packet/'variants'/v['name']
 for b in v['bindings']:
  f=root/b['path'];data=f.read_bytes()
  assert len(data)==b['bytes'] and sha(data)==b['sha256'],str(f)
  out=dest/b['path'];out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data);count+=1
 t=(dest/'Tests/SwiftRightRuntimeTests/TaskIDTests.swift').read_text()
 assert 'Task.sleep(for: .milliseconds(40))' in t
 assert 'XCTAssertEqual(log.results, ["a"])' in t
 assert '.milliseconds(120)' in (dest/'Tests/SwiftRightRuntimeTests/RuntimeTests.swift').read_text()
assert count==135
rows=[dict(path=f.relative_to(packet).as_posix(),bytes=f.stat().st_size,sha256=sha(f.read_bytes())) for f in sorted(packet.rglob('*')) if f.is_file()]
(H/'packet-manifest.json').write_text(json.dumps(dict(schema='taskid-direct-scp-packet-v1',sourceFiles=count,files=rows),indent=2)+'\n')
(H/'runner-plumbing-repair.json').write_text(json.dumps(dict(schema='taskid-runner-plumbing-repair-v1',oldSha256=sha(src.encode()),newSha256=sha(new.encode()),changes=['New-Item -Path supported directory parameter','reserved automatic $input renamed ownedInputRoot','native stdout/stderr copied as bytes'],workloadChanges=0,bodyMilliseconds=40,settleMilliseconds=120),indent=2)+'\n')
print(json.dumps(dict(sourceFiles=count,totalFiles=len(rows),runnerSha256=sha(new.encode()))))
