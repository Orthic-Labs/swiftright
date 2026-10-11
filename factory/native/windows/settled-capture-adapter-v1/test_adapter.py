import copy,importlib.util,json,unittest
from pathlib import Path,PureWindowsPath
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[3]
spec=importlib.util.spec_from_file_location('settled_adapter',ROOT/'adapter.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def ref(p):
 p=Path(p);raw=p.read_bytes();return {'path':str(p.relative_to(REPO)),'sha256':m.digest(raw),'bytes':len(raw)}
def reader(r):return (REPO/r['path']).read_bytes()
def fixture():
 base=REPO/'factory/native/windows/round1-seeded-native-v5/single-padding-frame-r1';run=base/'replays/run-001';native=run/'native-01';package=REPO/'factory/native/windows/round1-seeded-hosts-v1/padding-frame/package';build=package.parent/'build-actual-v2-r1'
 names={'plan':run/'plan.json','observation':run/'native-observation.json','outcome':native/'capture-outcome.json','owned':native/'owned-process.json','close':native/'owned-close.json','pixels':native/'native.pixels.json','dispatch':run/'dispatch.json','compile':build/'observation.json','launch':native/'launch-observation.json','exe':build/'FactoryProbe.exe','macSourceProof':REPO/'factory/native/windows/round1-seeded-native-v5/proof/source-join.json'}
 bindings={k:ref(v) for k,v in names.items()};plan=m.parse((run/'plan.json').read_bytes());obs=m.parse((run/'native-observation.json').read_bytes())
 contract=REPO/'factory/native/windows/round1-seeded-native-v5/contract.json';bindings['driverContract']=ref(contract);host=next(h for h in m.parse(contract.read_bytes())['hosts'] if h['label']=='padding-frame');bindings['driverSource']={b['path']:ref(REPO/Path(*PureWindowsPath(b['path']).parts[3:])) for b in host['bindings']}
 bindings['case']=ref(REPO/'factory/oracle/mac/seed-origin-actual-v1/input-snapshot/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.json');bindings['recipe']=ref(REPO/'factory/recipes/data/swiftui.padding-frame.json')
 bindings['source']={b['path']:ref(package/b['path']) for b in plan['sourceBindings']};bindings['raw']={b['path']:ref(native/b['path']) for b in obs['files']};bindings['uiaMode']='parent-retained'
 return {'batch':ref(base/'batch.json'),'runs':[bindings]}
class Tests(unittest.TestCase):
 def test_actual_single_exposes_settled_channels_without_minting_capture(self):
  r=m.inspect(fixture(),reader);self.assertTrue(r['rows'][0]['settled'],r);self.assertTrue(r['rows'][0]['channels']['ax']);self.assertIsNone(r['canonicalCapture']);self.assertFalse(r['qualified']);self.assertIn('missing-prelaunch-issued-capture-metadata',r['issues']);self.assertIn('missing/bad ref run1:renderer',r['rows'][0]['issues'])
 def test_reader_corruption_rejected(self):
  x=fixture();wanted=x['runs'][0]['raw']['native.uia.json']['path']
  r=m.inspect(x,lambda ref:reader(ref)+b' ' if ref['path']==wanted else reader(ref));self.assertFalse(r['rows'][0]['settled']);self.assertIsNone(r['rows'][0]['channels'])
 def test_original_failure_not_rescued_by_release_kernel0(self):
  x=fixture();wanted=x['runs'][0]['outcome'];doc=m.parse(reader(wanted));doc['primaryError']='Owned renderer child deadline';doc['preCleanupExitObservation']['kernelWaitResult']=258;raw=json.dumps(doc).encode();replacement={'path':wanted['path'],'sha256':m.digest(raw),'bytes':len(raw)};x['runs'][0]['outcome']=replacement
  r=m.inspect(x,lambda ref:raw if ref['path']==wanted['path'] else reader(ref));self.assertFalse(r['rows'][0]['settled']);self.assertIn('original native deadline/natural kernel0 failure',r['rows'][0]['issues'])
 def test_numeric_kernel_wait_and_stream_status(self):
  p=fixture();out=m.parse(reader(p['runs'][0]['outcome']));self.assertTrue(m.kernel(out['cleanup'],True));out['cleanup']['kernelWaitResult']='0';self.assertFalse(m.kernel(out['cleanup'],True));s=out['rawStreams'][0];self.assertTrue(m.stream(s));s['closure']['flushCompleted']=False;self.assertFalse(m.stream(s))
 def test_failed_repeat_batch_is_not_partial20(self):
  paths=list((REPO/'factory/native/windows/round1-seeded-native-v2').glob('repeat-*/batch.json'))
  failed=[p for p in paths if m.parse(p.read_bytes()).get('status')!='completed-20-observational'];self.assertTrue(failed)
  r=m.inspect({'batch':ref(failed[0]),'runs':[]},reader);self.assertEqual(r['rows'],[]);self.assertIn('complete Count1/20 batch required',r['issues'])
 def test_actual_stack_original_failure(self):
  base=REPO/'factory/native/windows/stack-lifecycle-next-capture-v1/actual-single-r1'
  paths=list(base.rglob('capture-outcome.json'));self.assertEqual(len(paths),1);out=m.parse(paths[0].read_bytes());self.assertNotEqual(out['primaryError'],'');self.assertEqual(out['preCleanupExitObservation']['kernelWaitResult'],258);self.assertFalse(m.kernel(out['cleanup'],True))
 def test_no_unsafe_reader_path(self):
  r=m.inspect({'batch':{'path':'../bad','sha256':'sha256:'+'a'*64}},lambda r:self.fail('reader called'));self.assertIn('unsafe ref batch',r['issues'])
if __name__=='__main__':unittest.main()
