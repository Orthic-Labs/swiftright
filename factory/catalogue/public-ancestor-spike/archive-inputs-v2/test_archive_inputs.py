import copy,json,unittest
from pathlib import Path
import verify_archive_inputs as v
HERE=Path(__file__).resolve().parent; BASE=json.loads((HERE/'archive-input-mapping.json').read_text())
class V2Guards(unittest.TestCase):
 def reject(self,fn):
  d=copy.deepcopy(BASE);fn(d)
  with self.assertRaises(ValueError):v.check(d)
 def test_baseline(self):self.assertEqual(v.check(BASE)['entries'],93)
 def test_base_pin(self):self.reject(lambda d:d['baseMapping'].update(sha256='0'*64))
 def test_source_pin(self):self.reject(lambda d:d['sourceScope'].update(mainEvidenceSha256='0'*64))
 def test_semantic_hash(self):self.reject(lambda d:d['entries'][0].update(sha256='0'*64))
 def test_archive_hash(self):self.reject(lambda d:d['entries'][0]['archive'].update(sha256='0'*64))
 def test_missing_archive(self):self.reject(lambda d:d['entries'][0]['archive'].update(path='factory/catalogue/public-ancestor-spike/archive-inputs-v2/archive/missing'))
 def test_duplicate_semantic(self):self.reject(lambda d:d['entries'].append(copy.deepcopy(d['entries'][0])))
 def test_duplicate_archive(self):self.reject(lambda d:d['entries'][1]['archive'].update(path=d['entries'][0]['archive']['path']))
 def test_escape(self):self.reject(lambda d:d['entries'][0]['archive'].update(path='../outside'))
 def test_gzip_whole(self):
  e=next(x for x in BASE['entries'] if x['archive']['compression']=='gzip')
  self.reject(lambda d: next(x for x in d['entries'] if x['semanticPath']==e['semanticPath'])['archive'].update(decompressedSha256='0'*64))
if __name__=='__main__':unittest.main()
