from __future__ import annotations
import copy, unittest
from review import ReviewError, load_inputs, audit_payloads
class IndependentEnabledAXTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls): cls.mraw,cls.m,cls.rows,cls.payloads=load_inputs(); cls.result=audit_payloads(cls.mraw,cls.m,cls.rows,cls.payloads)
 def test_baseline(self):
  self.assertEqual(self.result["producerPacket"]["freshRuns"],20); self.assertEqual(self.result["observation"]["enabledTrueCount"],20); self.assertFalse(self.result["observation"]["paintCaptureClaim"])
 def test_manifest_mutation(self):
  with self.assertRaises(ReviewError): audit_payloads(self.mraw+b" ",self.m,self.rows,self.payloads)
 def test_raw_enabled_value_mutation(self):
  p=next(x for x in self.rows if x.endswith('/run-001/external-ax.raw.json')); q=dict(self.payloads); q[p]=q[p].replace(b'"value": true',b'"value": false',1)
  with self.assertRaises(ReviewError): audit_payloads(self.mraw,self.m,self.rows,q)
 def test_raw_enabled_type_mutation(self):
  p=next(x for x in self.rows if x.endswith('/run-001/external-ax.raw.json')); q=dict(self.payloads); q[p]=q[p].replace(b'"value": true',b'"value": "true"',1)
  with self.assertRaises(ReviewError): audit_payloads(self.mraw,self.m,self.rows,q)
 def test_owner_pid_mutation(self):
  p=next(x for x in self.rows if x.endswith('/run-001/owner-process.json')); q=dict(self.payloads); q[p]=q[p].replace(b'"pid": 55477',b'"pid": 99999',1)
  with self.assertRaises(ReviewError): audit_payloads(self.mraw,self.m,self.rows,q)
 def test_replay_count_missing_run(self):
  q=dict(self.payloads); p=next(x for x in q if x.endswith('/run-020/result.json')); del q[p]
  with self.assertRaises(ReviewError): audit_payloads(self.mraw,self.m,self.rows,q)
if __name__=='__main__': unittest.main(verbosity=2)
