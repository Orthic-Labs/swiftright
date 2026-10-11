from pathlib import Path
import tempfile,sys,json,importlib.util
ROOT=Path(__file__).resolve().parents[4];sys.path.insert(0,str(ROOT))
from factory.gate.test_mac_origin_admission import OriginFixture
spec=importlib.util.spec_from_file_location('guard',Path(__file__).parent/'source-snapshot-v4/mac_origin_admission.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
rows=[]
for name in ['nested-unhashable-hash','reader-error','missing-origin','top-level-origin-only']:
 with tempfile.TemporaryDirectory() as p:
  f=OriginFixture(Path(p));assert not g.mac_origin_admission_issues(f.capture,f.reader);reader=f.reader
  if name=='nested-unhashable-hash':
   f.receipt['compiler']['sourceBefore']['Witness.swift']['sha256']=[];f.refresh_receipt()
  if name=='reader-error':
   def reader(ref):raise OSError('isolated unavailable input')
  if name=='missing-origin':f.capture.pop('meta')
  if name=='top-level-origin-only':f.capture['macOrigin']=f.capture.pop('meta')['conditions']['macOrigin']
  issues=g.mac_origin_admission_issues(f.capture,reader);assert issues
  report=g.mac_origin_admission_report(f.capture,reader);assert report['status']=='BLOCKED' and report['originQualified'] is False and report['parityGranted'] is False
  rows.append({'fault':name,'issues':issues,'reportStatus':report['status']})
print(json.dumps({'kind':'isolated-public-boundary-controls-v4','synthetic':True,'faults':rows,'nativeCompilerRuns':0},indent=2))
