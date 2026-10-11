"""SSH JSON/stdin upload & bounded dispatch; every generated path is additive."""
import base64,datetime,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
INPUT=r'D:\Claude\factory-swiftright-perfphase-input-v4-20261011'
RUN=r'D:\Claude\factory-swiftright-perfphase-pair-v2-20261011'
def command(script):return ['ssh','-o','BatchMode=yes','win','powershell','-NoProfile','-EncodedCommand',base64.b64encode(script.encode('utf-16le')).decode()]
if sys.argv[1]=='upload':
 payload={'root':INPUT,'files':{n:base64.b64encode((HERE/n).read_bytes()).decode() for n in ['run-pair.ps1','config.json','PerformancePhaseDiagnosisTests.swift']}}
 script='$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";$lines=@();while(($line=[Console]::In.ReadLine()) -ne "END"){if($null -eq $line){throw "Transport truncated"};$lines+=$line};$d=($lines -join "")|ConvertFrom-Json;if(Test-Path -LiteralPath $d.root){throw "Fresh input required"};New-Item -ItemType Directory -Path $d.root|Out-Null;foreach($p in $d.files.PSObject.Properties){[IO.File]::WriteAllBytes((Join-Path $d.root $p.Name),[Convert]::FromBase64String($p.Value))};$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $d.root "run-pair.ps1"),[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ConvertTo-Json;throw "Parser rejection"};Get-ChildItem -LiteralPath $d.root -File|ForEach-Object{[pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}}|ConvertTo-Json'
else:
 script='$ErrorActionPreference="Stop";& "'+INPUT+'\\run-pair.ps1" -InputRoot "'+INPUT+'" -RunRoot "'+RUN+'"'
 payload=None
started=datetime.datetime.now(datetime.timezone.utc).isoformat();r=subprocess.run(command(script),input="\n".join(json.dumps(payload)[i:i+6000] for i in range(0,len(json.dumps(payload)),6000))+"\nEND\n" if payload else None,capture_output=True,text=True,timeout=2000)
receipt={'schema':'ssh-performance-phase-dispatch-v1','action':sys.argv[1],'argv':command(script),'startedAt':started,'endedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'inputRoot':INPUT,'runRoot':RUN}
(HERE/(sys.argv[1]+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n');print(r.returncode,r.stdout,r.stderr[-1000:]);sys.exit(r.returncode)
