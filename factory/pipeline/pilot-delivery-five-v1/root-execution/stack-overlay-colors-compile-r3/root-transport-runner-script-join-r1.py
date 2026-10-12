from pathlib import Path
import argparse, hashlib, json, subprocess, sys

p=argparse.ArgumentParser()
p.add_argument('--script',type=Path,required=True)
p.add_argument('--remote-script',required=True)
p.add_argument('--remote-receipt',required=True)
p.add_argument('--archive',type=Path,required=True)
p.add_argument('--deadline',type=int,required=True)
p.add_argument('--compiler-budget',action='store_true')
p.add_argument('--transport-pins',type=Path,default=Path('factory/pipeline/root-transport-supervision-root-v1/controls-stage-pins-r4.json'))
a=p.parse_args()
assert 1 <= a.deadline <= 1100
assert a.script.is_file() and not a.script.is_symlink() and a.script.stat().st_size <= 2097152
assert a.transport_pins.is_file() and not a.transport_pins.is_symlink() and a.transport_pins.stat().st_size <= 2097152
pins=json.loads(a.transport_pins.read_text())
rows={r['name']:r for r in pins['files']}
helper='Sr0RootControlSuiteJobV1.cs' if a.compiler_budget else 'Sr0RootTransportJobV1.cs'
wrapper='run-control-suite-job-v1.ps1' if a.compiler_budget else 'run-root-transport-job-v1.ps1'
sha=hashlib.sha256(a.script.read_bytes()).hexdigest()
subprocess.run(['scp','-q',str(a.script),'win:'+a.remote_script.replace('\\','/')],check=True,timeout=15)
argv=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8','win','powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',pins['stage']+'\\'+wrapper,'-HelperPath',pins['stage']+'\\'+helper,'-HelperSha256',rows[helper]['sha256'],'-ScriptPath',a.remote_script,'-ScriptSha256',sha,'-OutputPath',a.remote_receipt,'-DeadlineSeconds',str(a.deadline)]
a.archive.mkdir()
(a.archive/'invocation.json').open('x').write(json.dumps({'argv':argv,'scriptSha256':sha,'budgetBytes':1073741824 if a.compiler_budget else 268435456},indent=2)+'\n')
r=subprocess.run(argv,timeout=a.deadline+45)
for suf in ('','.stdout.bin','.stderr.bin'):
 subprocess.run(['scp','-q','win:'+(a.remote_receipt+suf).replace('\\','/'),str(a.archive/('transport.json'+suf))],check=True,timeout=15)
receipt=json.loads((a.archive/'transport.json').read_text(encoding='utf-8-sig'))
assert receipt['scriptSha256']==sha, 'transport receipt belongs to another script invocation'
assert receipt['scriptPath']==a.remote_script, 'transport receipt script path mismatch'
print(json.dumps(receipt))
assert receipt['selfOnly'] and receipt['childTerminal'] and receipt['childExitIdentity'] and receipt['streamsSealed']
sys.exit(r.returncode)
