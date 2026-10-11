import hashlib,json,unittest
from pathlib import Path
ROOT=Path(__file__).parent
class SourcePacket(unittest.TestCase):
 def test_exact_five_seed_inputs(self):
  d=json.loads((ROOT/'input-pins.json').read_text()); self.assertEqual(d['seed'],14577611000270672472); self.assertEqual({x['block'] for x in d['rows']},{'stack-overlay','padding-frame','scroll-view','custom-layout','preference-key'})
  for r in d['rows']:
   p=ROOT/r['source']['path']; self.assertEqual('sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),r['source']['sha256']); self.assertEqual(json.loads((ROOT/r['case']['path']).read_text())['seed'],d['seed'])
 def test_compiler_receipt_guards_present(self):
  s=(ROOT/'capture_origin.py').read_text();
  for token in ('compiler_build','sourceDrift','startedAtUtc','endedAtUtc','outputBinary','xcrunHash','start_new_session') : self.assertIn(token,s)
 def test_receipt_verifier_controls(self):
  s=(ROOT/'verify_receipt.py').read_text();
  for token in ('argv/compiler mismatch','compiler tool hash','source drift','output argv mismatch','compiler exit','resolver exit') : self.assertIn(token,s)
if __name__=='__main__': unittest.main()
