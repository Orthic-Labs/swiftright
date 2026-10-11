"""Append-only independent review packet packaging, local reads only."""
from pathlib import Path
import json,hashlib,argparse
REPO=Path(__file__).resolve().parents[6]
OUT=Path(__file__).resolve().parent
LANE=OUT.parent.parent
p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--fetch',required=True);p.add_argument('--expected-files',type=int,required=True);p.add_argument('--visual',required=True);a=p.parse_args()
report=OUT/f'single-{a.label}-r1.json';d=json.loads(report.read_bytes());fetch=LANE/a.fetch;f=json.loads(fetch.read_bytes());assert f['scpExit']==0 and len(f['files'])==a.expected_files
for path,h in f['files'].items():
 b=(REPO/path).read_bytes();assert hashlib.sha256(b).hexdigest()==h;d['files'][path]={'sha256':h,'bytes':len(b)}
d['fetchReceipt']={'path':str(fetch.relative_to(REPO)),'sha256':hashlib.sha256(fetch.read_bytes()).hexdigest()};d['visualObservation']=a.visual
if a.label=='custom-layout':
 mac=REPO/'factory/oracle/mac/seed-corrections-v1/evidence/swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258/run-001/capture.json';b=mac.read_bytes();d['files'][str(mac.relative_to(REPO))]={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)};d['MacExternalAX']=json.loads(b)['meta']['conditions']['channelStatus']['externalAX'];assert d['MacExternalAX']=='HELD';d['WindowsUIA']='observed owned Window root with empty children; no Color AX fabricated'
report.write_text(json.dumps(d,indent=2)+'\n')
readme=OUT/f'README-single-{a.label}-r1.md';assert not readme.exists();readme.write_text('CLEAR actual source/case/compile/exe/runtime/renderer/owned PID/HWND/WM_CLOSE/exit/sealed-stream/lock-release joins. Fetched raw bytes exact. Producer guards report no owned foreground activation; unchanged global foreground is not claimed. UIA channel availability & PW observations preserved; no semantic/parity/golden/controlled-occlusion qualification. Reviewer local Python/files/image inspection only.\n')
refs=dict(d['files'])
for path in [fetch,report,OUT/'review.py',OUT/'freeze_review.py',readme]:
 b=path.read_bytes();refs[str(path.relative_to(REPO))]={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)}
stage=OUT/f'stage-single-{a.label}-r1.json';assert not stage.exists();stage.write_text(json.dumps({'kind':'independent-single-seeded-native-review','files':[{'path':path,**x} for path,x in sorted(refs.items())]},indent=2)+'\n')
print(json.dumps({'report':hashlib.sha256(report.read_bytes()).hexdigest(),'stage':hashlib.sha256(stage.read_bytes()).hexdigest(),'refs':len(refs)}))
