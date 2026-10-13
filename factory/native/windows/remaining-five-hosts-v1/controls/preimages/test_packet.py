"""Synthetic mutations of real pinned source packet; no process/native provider tests."""
import copy,json,unittest
from verify_packet import snapshot,verify_package,LABELS
class SourceClosureTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.actual=snapshot()
 def test_all_five_real_source_joins(self):
  for label in LABELS:
   self.assertFalse(verify_package(label,self.actual)['qualificationGranted'])
 def fault(self,name,mutate):
  s=copy.copy(self.actual);self.assertTrue(verify_package('disabled',s)['sourceOnly']);mutate(s)
  with self.assertRaises((ValueError,KeyError,TypeError)):verify_package('disabled',s)
 def plan(self,s,change):
  p='disabled/package/plan.json';d=json.loads(s[p]);change(d);s[p]=json.dumps(d).encode()
 def test_extra_source(self):self.fault('extra',lambda s:s.update({'disabled/package/Sources/FactoryProbe/extra.swift':b'// synthetic'}))
 def test_missing_source(self):self.fault('missing',lambda s:s.pop('disabled/package/Sources/FactoryProbe/main.swift'))
 def test_equal_count_wrong_source(self):
  def change(s):s['disabled/package/Sources/FactoryProbe/wrong.swift']=s.pop('disabled/package/Sources/FactoryProbe/main.swift')
  self.fault('same-count',change)
 def test_raw_source_drift(self):self.fault('raw',lambda s:s.update({'disabled/package/Sources/FactoryProbe/Witness.swift':b'// synthetic drift'}))
 def test_source_binding_omitted(self):self.fault('omitted',lambda s:self.plan(s,lambda d:d['sourceBindings'].pop()))
 def test_case_drift(self):self.fault('case',lambda s:self.plan(s,lambda d:d['case'].update(hash='sha256:'+'0'*64)))
 def test_runtime_drift(self):self.fault('runtime',lambda s:self.plan(s,lambda d:d.update(runtimeSourceCommit='b'*40)))
 def test_bridge_drift(self):self.fault('bridge',lambda s:s.update({'dependencies/staged-bridge-inputs-r09/Package.swift':b'// synthetic drift'}))
 def test_foreign_request(self):self.fault('request',lambda s:self.plan(s,lambda d:d['compileRequest'].update(packagePath=r'D:\Claude\foreign')))
 def test_flag_drift(self):self.fault('flags',lambda s:self.plan(s,lambda d:d['compileRequest'].update(configuration='debug')))
 def test_tool_drift(self):self.fault('tool',lambda s:self.plan(s,lambda d:d['compileRequest'].update(compilerPath=r'C:\foreign\swift.exe')))
 def test_qualification_spoof(self):self.fault('spoof',lambda s:self.plan(s,lambda d:d.update(executionEligible=True,nativeParity='pass')))
 def test_provider_spoof(self):self.fault('provider',lambda s:self.plan(s,lambda d:d.update(providerRequirements=['nativeSwitchPainting'])))
 def test_module_origin_drift(self):self.fault('module',lambda s:s.update({'dependencies/module-origin-receipt.json':b'{}'}))
if __name__=='__main__':unittest.main()
