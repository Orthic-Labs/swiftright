from pathlib import Path
import copy, json, subprocess
root=Path('/Volumes/D/claude/swiftright')
out=root/'.factory-work/rounded-seed-faults-r1'
out.mkdir(exist_ok=False)
src=root/'factory/pipeline/pilot-delivery-five-v1/text-shape-image/rounded-stroke-host-v1/centered-delivery-v1/package/case.json'
assert src.stat().st_size < 65536
baseline=json.loads(src.read_text())
rows=[]
for name, expected in [('block','recipe seed block differs'),('inputs','recipe seed inputs differ'),('recipe-id','recipe seed id differs')]:
    value=copy.deepcopy(baseline)
    if name=='block': value['block']='swiftui.other'
    elif name=='inputs': value['inputs']['color-scheme']='dark'
    else: value['recipe']['id']='swiftui.other.recipe'
    path=out/(name+'.json');path.write_text(json.dumps(value)+'\n')
    p=subprocess.run([str(root/'factory/.venv/bin/python'),str(root/'factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-final-build-v1.py'),'--host','rounded-stroke-circular','--seed-case-artifact',str(path)],capture_output=True,timeout=12)
    assert len(p.stdout)+len(p.stderr)<65536
    (out/(name+'.stdout.bin')).write_bytes(p.stdout)
    (out/(name+'.stderr.bin')).write_bytes(p.stderr)
    assert p.returncode!=0 and expected.encode() in p.stderr
    rows.append({'fault':name,'exitCode':p.returncode,'expectedProductionRejection':expected})
target=root/'factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-stroke-circular-compile-r1/recipe-seed-controls.json'
with target.open('x') as f: f.write(json.dumps({'kind':'factory-recipe-seed-production-controls-v1','rows':rows,'nativeActions':0},indent=2)+'\n')
print(json.dumps({'rejected':len(rows),'productionFinalizerInvoked':True,'nativeActions':0}))
