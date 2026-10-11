import hashlib,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[4]
H=ROOT/'factory/runtime-additions/copy-cost-windows-candidate-v1'
def descriptor(p):
 if p.is_symlink(): raise ValueError('symlink')
 b=p.read_bytes()
 if len(b)>=100_000_000: raise ValueError('oversized staged blob')
 return {'path':str(p.relative_to(ROOT)),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
old=H/'stage-manifest.json'
assert hashlib.sha256(old.read_bytes()).hexdigest()=='74586acc7446f39208c3668189dd3c23bb7db3a3b65dd4ca0657a70fe551eb5f'
for r in json.loads(old.read_text())['files']:
 assert descriptor(ROOT/r['path'])==r, r['path']
out=H/'execution/final-stage-manifest.json'
paths=[ROOT/r['path'] for r in json.loads(old.read_text())['files']]+[old]
paths += [p for p in H.iterdir() if p.is_file() and p.name.startswith(('remote-init.','scp-packet.','remote-preflight.'))]
paths += [p for p in (H/'execution').rglob('*') if p.is_file() and p!=out and '__pycache__' not in p.parts and p.suffix!='.pyc']
rows=[descriptor(p) for p in sorted(set(paths))]
plan=json.loads((H/'packet/source-plan.json').read_text())
j={'schema':'copy-cost-windows-actual-execution-stage-v1','preparationStageSha256':hashlib.sha256(old.read_bytes()).hexdigest(),'sourcePlanSha256':hashlib.sha256((H/'packet/source-plan.json').read_bytes()).hexdigest(),'runnerSha256':plan['runnerSha256'],'files':rows,'fileCount':len(rows),'totalBytes':sum(r['bytes'] for r in rows),'toolArchiveReference':plan['toolArchive'],'toolBindings':plan['toolBindings'],'actualFullReleaseInvocations':2,'retries':0,'productionEdits':False,'causalCertification':False}
out.write_text(json.dumps(j,indent=2)+'\n')
print(json.dumps({'manifest':descriptor(out),'files':len(rows),'bytes':j['totalBytes'],'receipt':descriptor(H/'execution/results/receipt.json'),'verification':descriptor(H/'execution/verified-capture.json'),'verifier':descriptor(H/'execution/verify_capture.py')},indent=2))
