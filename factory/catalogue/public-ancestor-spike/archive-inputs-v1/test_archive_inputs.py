#!/usr/bin/env python3
import copy, json, tempfile, unittest
from pathlib import Path
import verify_archive_inputs as v

HERE=Path(__file__).resolve().parent
BASE=json.loads((HERE/'archive-input-mapping.json').read_text())

class ArchiveInputGuards(unittest.TestCase):
    def assertReject(self, mut):
        d=copy.deepcopy(BASE); mut(d)
        with self.assertRaises(ValueError): v.check(d)
    def test_accepted_baseline(self):
        self.assertEqual(v.check(BASE)['entries'],30)
    def test_wrong_semantic_hash(self): self.assertReject(lambda d: d['entries'][0].update(sha256='0'*64))
    def test_wrong_archive_hash(self): self.assertReject(lambda d: d['entries'][0]['archive'].update(sha256='0'*64))
    def test_missing_archive(self): self.assertReject(lambda d: d['entries'][0]['archive'].update(path='archive/inputs/missing'))
    def test_duplicate_semantic_rejected(self):
        def f(d): d['entries'].append(copy.deepcopy(d['entries'][0]))
        self.assertReject(f)
    def test_duplicate_archive_alias_rejected(self):
        def f(d): d['entries'][1]['archive']['path']=d['entries'][0]['archive']['path']
        self.assertReject(f)
    def test_gzip_whole_hash_rejected(self):
        e=next(x for x in BASE['entries'] if x['archive']['compression']=='gzip')
        self.assertReject(lambda d: next(x for x in d['entries'] if x['semanticPath']==e['semanticPath'])['archive'].update(decompressedSha256='0'*64))
    def test_sdk_must_remain_directory_only(self): self.assertReject(lambda d: d['directoryPrerequisites'][0].update(archive={'path':'archive/inputs/x'}))
    def test_noncanonical_escape_rejected(self): self.assertReject(lambda d: d['entries'][0]['archive'].update(path='../outside'))

if __name__=='__main__': unittest.main()
