import importlib.util,tempfile,unittest
from pathlib import Path
p=Path(__file__).parent/'capture_origin.py'; spec=importlib.util.spec_from_file_location('origin',p); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class Argv0(unittest.TestCase):
 def test_logical_symlink_preserved_real_separate(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); real=root/'swiftc-real'; logical=root/'swiftc-logical'; real.write_bytes(b'tool'); logical.symlink_to(real)
   lp,rp=m.logical_and_real(str(logical)); self.assertEqual(str(lp),str(logical)); self.assertEqual(rp,real); self.assertNotEqual(str(lp),str(rp))
if __name__=='__main__': unittest.main()
