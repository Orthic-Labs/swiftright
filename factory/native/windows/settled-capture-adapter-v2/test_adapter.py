import copy,importlib.util,json,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent;REPO=HERE.parents[3]
spec=importlib.util.spec_from_file_location('typed_adapter',HERE/'adapter.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
def load(path):return a.r.parse(path.read_bytes())
class Tests(unittest.TestCase):
 def test_real_failed_v2_never_settled_or_natural_worker(self):
  p=REPO/'factory/native/windows/padding-window-diagnosis-capture-v2/actual-single-r1/native-01'
  self.assertFalse(a.settled(load(p/'capture-outcome.json')));self.assertFalse(a.natural_worker(load(p/'uia-worker/worker-exit.json')))
 def test_real_stack_deadline_stays_failed(self):
  p=list((REPO/'factory/native/windows/stack-lifecycle-next-capture-v1/actual-single-r1').rglob('capture-outcome.json'))[0];self.assertFalse(a.settled(load(p)))
 def test_original_padding_projection_schema(self):
  p=REPO/'factory/native/windows/round1-seeded-native-v5/single-padding-frame-r1/replays/run-001/native-01'
  out=load(p/'capture-outcome.json');self.assertTrue(a.settled(out));projection=a.r.channels(load(p/'native.uia.json'),(p/'native.printwindow.png').read_bytes(),(p/'host.stdout.txt').read_bytes());self.assertEqual(len(projection['ax']),2)
  cap={'kind':'capture','version':'0.1','id':'fixture.preissued.capture','provenance':{'sourceHash':'sha256:'+'a'*64,'createdAt':'2026-10-11T00:00:00Z','producer':'explicit-test-fixture'},'case':{'id':'fixture.case','hash':'sha256:'+'b'*64},'platform':'windows','tuple':{'id':'fixture.candidate','sdk':'fixture.sdk','macosBuild':'fixture.mac','toolchains':{'windows':'fixture.toolchain'},'runtimeCommit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','rendererHash':'sha256:'+'c'*64,'hostHashes':{'windows':'sha256:'+'d'*64},'factoryVersion':'0.1','acceptanceConfigHash':'sha256:'+'e'*64},'meta':{'run':1,'host':{'id':'fixture.observed.host','hash':'sha256:'+'d'*64},'clock':{'clockId':'fixture.receipt.clock','correlationHash':'sha256:'+'f'*64},'conditions':{'frozenTupleBound':False,'nativeProviderClockQualified':False}},'layout':[],'ax':projection['ax'],'events':[],'anim':[],'text':[],'images':[dict(id='fixture.preissued.image',**projection['printWindow'])]}
  self.assertTrue(a.validate_capture(cap));bad=copy.deepcopy(cap);bad['images'][0]['captureScale']=2.5
  with self.assertRaises(ValueError):a.validate_capture(bad)
 def test_planned_identity_cannot_be_measurement(self):
  with self.assertRaisesRegex(ValueError,'planned-identities'):
   a.measured_identity({'kind':'factory-measured-capture-identity-v1','issuedMetadataHash':'a'*64,'run':1,'captureID':'preissued','imageID':'image'}, {'captureID':'preissued','imageID':'image'}, {},'sha256:'+'b'*64,'sha256:'+'a'*64,1)
 def test_missing_issued_ref_reports_hold(self):
  result=a.normalize({'roles':{},'runs':[]},lambda ref:b'');self.assertEqual(result['captures'],[]);self.assertEqual(result['typedStatus'],'held');self.assertIn('missing-ref:issuedMetadata',result['issues'])
 def test_kernel_and_raw_corruption_rejected(self):
  p=REPO/'factory/native/windows/round1-seeded-native-v5/single-padding-frame-r1/replays/run-001/native-01';out=load(p/'capture-outcome.json');out['preCleanupExitObservation']['kernelWaitResult']='0';self.assertFalse(a.settled(out));out=load(p/'capture-outcome.json');out['rawStreams'][0]['sealed']=False;self.assertFalse(a.settled(out))
 def test_raw_ref_corruption(self):
  payload=b'{}';result=a.normalize({'roles':{'issuedMetadata':{'path':'issued.json','sha256':a.r.digest(payload),'bytes':2}}},lambda ref:payload+b' ');self.assertEqual(result['captures'],[]);self.assertIn('raw-byte-join:issuedMetadata',result['issues'])
 def test_duplicate_json_and_nonfinite_bounds(self):
  with self.assertRaises(ValueError):a.r.parse(b'{"a":1,"a":2}')
  with self.assertRaises(ValueError):a.r.channels({'name':'x','automationId':'x','controlType':'ControlType.Window','enabled':True,'patterns':[],'offscreen':False,'bounds':[0,0,float('nan'),1],'children':[]},b'',b'')
 def test_worker_missing_final_proof_and_zero_string_rejected(self):
  with self.assertRaises(ValueError):a.final_worker({}, {}, {}, {},'sha256:'+'a'*64,'sha256:'+'b'*64,'sha256:'+'c'*64,'sha256:'+'d'*64)
 def test_sub100ns_timestamps_preserved(self):
  self.assertEqual(a.ticks('2026-10-11T00:00:00.0000002Z')-a.ticks('2026-10-11T00:00:00.0000001Z'),1)
if __name__=='__main__':unittest.main()
