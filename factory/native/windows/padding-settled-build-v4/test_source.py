import unittest,copy,json
from verify_source import snapshot,verify
class PacketTests(unittest.TestCase):
 def setUp(self):self.s=snapshot();verify(self.s)
 def change(self,fn):
  fn(self.s)
  with self.assertRaises((ValueError,KeyError)):verify(self.s)
 def plan(self,fn):
  p=json.loads(self.s['package/plan.json']);fn(p);self.s['package/plan.json']=json.dumps(p).encode()
 def test_positive(self):self.assertEqual(verify(self.s)['canonicalBridgeMembers'],10)
 def test_serializer(self):self.change(lambda s:s.update({'serializer-control/main.swift':b'// synthetic'}))
 def test_payload(self):self.change(lambda s:s.update({'package/Sources/FactoryProbe/MetricsPayload.swift':b'// synthetic'}))
 def test_extra_source(self):self.change(lambda s:s.update({'package/Sources/FactoryProbe/unbound.swift':b'// synthetic'}))
 def test_witness(self):self.change(lambda s:s.update({'package/Sources/FactoryProbe/Witness.swift':b'// synthetic'}))
 def test_bridge(self):self.change(lambda s:s.update({'dependencies/SwiftRightBridge/Package.swift':b'// synthetic'}))
 def test_old_stage(self):self.change(lambda s:self.plan(lambda d:d.update(stage=r'D:\Claude\sr0-r09')))
 def test_runtime(self):self.change(lambda s:self.plan(lambda d:d.update(runtimePackagePath=r'D:\Claude\foreign')))
 def test_renderer(self):self.change(lambda s:self.plan(lambda d:d.update(rendererSha256='0'*64)))
 def test_request(self):self.change(lambda s:self.plan(lambda d:d['compileRequest'].update(configuration='debug')))
 def test_promotion(self):self.change(lambda s:self.plan(lambda d:d.update(executionEligible=True)))
if __name__=='__main__':unittest.main()
