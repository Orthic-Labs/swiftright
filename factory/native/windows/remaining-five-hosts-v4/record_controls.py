"""Bounded offline Python source controls; no Swift/Dell/native actions."""
from pathlib import Path
import subprocess,json,hashlib,os
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent
controls=OUT/'controls';controls.mkdir(exist_ok=True)
argv=[str(ROOT/'factory/.venv/bin/python'),'-m','unittest','discover','-s',str(OUT),'-p','test_packet.py','-v']
env=dict(os.environ);env['PYTHONPATH']=str(OUT)+os.pathsep+str(ROOT)
start=datetime.now(timezone.utc).isoformat();p=subprocess.Popen(argv,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
a,b=p.communicate(timeout=60);finish=datetime.now(timezone.utc).isoformat()
(controls/'final.stdout.bin').write_bytes(a);(controls/'final.stderr.bin').write_bytes(b)
h=lambda raw:'sha256:'+hashlib.sha256(raw).hexdigest()
(controls/'final-process.json').write_text(json.dumps({'kind':'offline-source-closure-controls','syntheticFaultsOnly':True,'argv':argv,'cwd':str(ROOT),
 'pid':p.pid,'startedAt':start,'finishedAt':finish,'exitCode':p.returncode,'toolPath':str(Path(argv[0]).resolve()),'toolHash':h(Path(argv[0]).resolve().read_bytes()),
 'stdoutHash':h(a),'stderrHash':h(b),'compilerRuns':0,'nativeRuns':0},indent=2)+'\n')
if p.returncode:raise SystemExit(p.returncode)
import sys
sys.path.insert(0,str(OUT))
from verify_packet import snapshot,verify_package,LABELS
s=snapshot();(controls/'actual-five-source-joins.json').write_text(json.dumps([verify_package(x,s) for x in LABELS],indent=2)+'\n')
files=[p for p in OUT.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='root-stage-manifest.json']
(OUT/'root-stage-manifest.json').write_text(json.dumps({'kind':'remaining-five-hosts-source-stage-v4','compilerRuns':0,'nativeRuns':0,
 'files':[{'path':str(p.relative_to(ROOT)),'hash':h(p.read_bytes()),'bytes':p.stat().st_size} for p in sorted(files)]},indent=2)+'\n')
print(h((OUT/'root-stage-manifest.json').read_bytes()))
