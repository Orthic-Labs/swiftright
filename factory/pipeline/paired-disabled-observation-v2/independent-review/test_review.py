import unittest
from review import ReviewError,load_inputs,audit
class V2IndependentTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.mraw,cls.m,cls.refs,cls.payloads=load_inputs();cls.r=audit(cls.mraw,cls.m,cls.refs,cls.payloads)
 def test_baseline_three_batches_hold(self):self.assertEqual(self.r["producerPins"]["inputCount"],1131);self.assertEqual(self.r["batches"]["macOSAXEnabled"]["enabledTrue"],20);self.assertEqual(self.r["batches"]["windowsUIA"]["distinctPrintWindowHashes"],1);self.assertEqual(self.r["qualification"]["acceptedGoldenCount"],0)
 def test_manifest_mutation_rejected(self):
  with self.assertRaises(ReviewError):audit(self.mraw+b" ",self.m,self.refs,self.payloads)
 def test_missing_payload_rejected(self):
  q=dict(self.payloads);q.pop(next(iter(q)))
  with self.assertRaises(ReviewError):audit(self.mraw,self.m,self.refs,q)
 def test_report_mutation_rejected(self):
  q=dict(self.payloads);p="factory/native/macos/disabled-enabled-observation-v1/evidence/report.json";q[p]=q[p].replace(b'"status": "observed"',b'"status": "golden"',1)
  with self.assertRaises(ReviewError):audit(self.mraw,self.m,self.refs,q)
if __name__=='__main__':unittest.main(verbosity=2)
