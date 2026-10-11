import hashlib,json,unittest
from pathlib import Path
ROOT=Path(__file__).parent
class SourcePacket(unittest.TestCase):
 def test_exact_inputs(self):
  d=json.loads((ROOT/'input-pins.json').read_text()); self.assertEqual(d['seed'],14577611000270672472); self.assertEqual(len(d['rows']),5)
  for r in d['rows']:
   p=ROOT/r['source']['path']; self.assertEqual('sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),r['source']['sha256'])
 def test_logical_compiler_binding(self):
  s=(ROOT/'capture_origin.py').read_text();
  for token in ("mode == 'xcrun'", "'logicalCompilerName': 'swiftc'", 'realToolAfter', 'realToolDrift', '_safe_drain', 'groupMissing', 'os.killpg') : self.assertIn(token,s)
  self.assertNotIn('logical_path = Path(rout.decode().strip().splitlines()[-1]).resolve()',s)
 def test_receipt_guards(self):
  s=(ROOT/'verify_receipt.py').read_text();
  for token in ('logical xcrun argv','logical direct argv','owned compiler pid/group','source drift','real compiler before hash','compiler exit','output argv binding') : self.assertIn(token,s)
if __name__=='__main__': unittest.main()
