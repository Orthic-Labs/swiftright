import pathlib,json,hashlib
p=pathlib.Path(__file__).resolve().parent;root=p.parents[2];mapping=json.loads((p/'mapping-v4.json').read_text())
def pin(f):b=f.read_bytes();return {'path':str(f.relative_to(root)),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
raw={'kind':'v4-exact-input-pins','mapping':pin(p/'mapping-v4.json'),'inputs':mapping['inputs'],'priorMappingPreserved':mapping['preservation']['v3Mapping']};(p/'raw-pins-v4.json').write_text(json.dumps(raw,indent=2)+'\n')
files=[pin(f) for f in sorted(p.rglob('*')) if f.is_file() and '__pycache__' not in f.parts and f.name not in ['stage-manifest-v4.json','SHA256SUMS-v4.txt']]
m={'kind':'v4-source-candidate-stage','files':files,'fileCount':len(files),'totalBytes':sum(r['bytes'] for r in files),'inputRefs':mapping['inputs'],'counts':mapping['componentCounts'],'registryPromotion':False};(p/'stage-manifest-v4.json').write_text(json.dumps(m,indent=2)+'\n');(p/'SHA256SUMS-v4.txt').write_text(''.join(r['sha256']+'  '+r['path']+'\n' for r in files+[pin(p/'stage-manifest-v4.json')]));print(json.dumps({'stage':pin(p/'stage-manifest-v4.json'),'mapping':pin(p/'mapping-v4.json'),'files':len(files),'bytes':m['totalBytes']}))
