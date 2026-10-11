"""Pure archive replay controls; no captures or external-file reads."""
import copy, importlib.util, json, sys, unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('destructor_archive_wrapper',HERE/'archive_wrapper.py')
w=importlib.util.module_from_spec(spec);sys.modules[spec.name]=w;spec.loader.exec_module(w)

class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.replay=w.Replay(force_archive=True)
        cls.actual=cls.replay.verify_all()
        cls.receipt=json.loads(cls.replay.read(cls.replay.original.RAW/'SwiftUI-arm64.receipt.json'))

    def test_exact_42(self):
        self.assertEqual(len(self.actual['rows']),42)
        self.assertEqual(self.actual,json.loads((HERE.parent/'effective-access-evidence.json').read_bytes()))

    def test_force_archive_never_external_path_read_or_stat(self):
        old_read=Path.read_bytes; old_stat=Path.stat
        def read(path,*a,**k):
            self.assertTrue(path.is_relative_to(w.ROOT),str(path));return old_read(path,*a,**k)
        def stat(path,*a,**k):
            self.assertFalse(str(path).startswith(('/Applications/','/Users/')),str(path));return old_stat(path,*a,**k)
        with patch.object(Path,'read_bytes',read),patch.object(Path,'stat',stat):
            self.assertEqual(w.verify_all(force_archive=True),self.actual)

    def test_source_byte_drift(self):
        replay=w.Replay(force_archive=True)
        def reader(path,*,force_archive=False):
            raw=replay.resolve(path,force_archive=force_archive)
            if '.swiftinterface' in path: raw=bytes([raw[0]^1])+raw[1:]
            return raw
        with self.assertRaisesRegex(ValueError,'reader-hash'):w.verify_all(reader,True)

    def test_tool_byte_drift(self):
        replay=w.Replay(force_archive=True)
        def reader(path,*,force_archive=False):
            raw=replay.resolve(path,force_archive=force_archive)
            if path.endswith('swift-frontend'):raw=bytes([raw[0]^1])+raw[1:]
            return raw
        with self.assertRaisesRegex(ValueError,'reader-hash'):w.verify_all(reader,True)

    def test_source_size_drift(self):
        replay=w.Replay(force_archive=True)
        src=self.replay.source('SwiftUI')
        with self.assertRaisesRegex(ValueError,'reader-size'):replay.read(str(src),w.digest(src.raw),len(src.raw)+1)
        with self.assertRaisesRegex(ValueError,'reader-size'):replay.read(str(src),w.digest(src.raw),True)

    def test_real_receipt_faults(self):
        faults={
            'path':lambda r:r['inputs'][0].update(path=r['inputs'][0]['path'].replace('/Applications/','/Applications/./')),
            'sourceHash':lambda r:r['inputs'][0].update(sha256='sha256:'+'0'*64),
            'sourceSize':lambda r:r['inputs'][0].update(bytes=r['inputs'][0]['bytes']+1),
            'toolPath':lambda r:r['tool'].update(path='/tmp/other-frontend'),
            'toolHash':lambda r:r['tool'].update(sha256='sha256:'+'0'*64),
            'flag':lambda r:r['argv'].append('-target-variant'),
            'target':lambda r:r['argv'].__setitem__(r['argv'].index('-target')+1,'x86_64-apple-macosx27.0'),
            'rawPath':lambda r:r['stdout'].update(path='/tmp/raw'),
            'rawSize':lambda r:r['stdout'].update(bytes=r['stdout']['bytes']+1),
            'rawHash':lambda r:r['stdout'].update(sha256='sha256:'+'0'*64),
            'cwd':lambda r:r.update(cwd='/tmp'),
            'booleanExit':lambda r:r.update(exitCode=False),
        }
        for label,change in faults.items():
            with self.subTest(label=label):
                receipt=copy.deepcopy(self.receipt);change(receipt)
                with self.assertRaises(ValueError):self.replay.verify_receipt('SwiftUI',receipt)

    def test_exact_cursor_source_pair(self):
        seed=json.loads(self.replay.read(self.replay.original.SEED,self.replay.original.SEED_HASH))
        fields=copy.deepcopy(seed['rows'][0]['cursor']['fields']);src=self.replay.source(fields['modulename'])
        self.assertTrue(self.replay.cursor_source_identity(fields,src))
        fields['filepath']=str(src)
        self.assertFalse(self.replay.cursor_source_identity(fields,src))
        fields=copy.deepcopy(seed['rows'][0]['cursor']['fields'])
        self.assertFalse(self.replay.cursor_source_identity(fields,w.SourceFact(str(src)+'.wrong',src.raw)))

    def test_raw_archive_byte_drift(self):
        replay=w.Replay(force_archive=True)
        rawpath=replay.original.RAW/'SwiftUI-arm64.receipt.json'
        archived=HERE.parent/replay.raw_rows[str(rawpath)]['archivePath']
        old=Path.read_bytes
        def read(path,*a,**k):
            raw=old(path,*a,**k)
            return bytes([raw[0]^1])+raw[1:] if path==archived else raw
        with patch.object(Path,'read_bytes',read):
            with self.assertRaisesRegex(ValueError,'repository-byte-pin'):replay.read(rawpath)

    def test_unused_archive_members_corrupt(self):
        old=Path.read_bytes
        for name in ['SwiftUI.swiftinterface','SwiftUICore.swiftinterface','independent-access-review.json']:
            target=HERE.parent/'raw-arm64-v2'/name
            def read(path,*a,**k):
                raw=old(path,*a,**k)
                return bytes([raw[0]^1])+raw[1:] if path==target else raw
            with self.subTest(member=name),patch.object(Path,'read_bytes',read):
                with self.assertRaisesRegex(ValueError,'repository-byte-pin'):w.Replay(force_archive=True)

    def test_archive_coverage_and_shape_faults(self):
        old=Path.iterdir
        archive=HERE.parent/'raw-arm64-v2'
        def extra(path):
            entries=list(old(path))
            return iter(entries+[path/'unexpected.json']) if path==archive else iter(entries)
        with patch.object(Path,'iterdir',extra):
            with self.assertRaisesRegex(ValueError,'repository-archive-coverage'):w.Replay(force_archive=True)
        for label in ['duplicateFilename','missingMember','wrongTotal','wrongSize','escapedPath']:
            replay=w.Replay(force_archive=True)
            replay.archive_manifest=copy.deepcopy(replay.archive_manifest)
            rows=replay.archive_manifest['rows']
            if label=='duplicateFilename':rows[1]['archivePath']=rows[0]['archivePath']
            elif label=='missingMember':rows.pop()
            elif label=='wrongTotal':replay.archive_manifest['totalBytes']+=1
            elif label=='wrongSize':rows[0]['bytes']+=1
            else:rows[0]['archivePath']='../outside'
            with self.subTest(fault=label),self.assertRaises(ValueError):replay.verify_archive()

    def test_unknown_semantic_path_and_force_type(self):
        with self.assertRaises(ValueError):self.replay.resolve('/Applications/./missing',force_archive=True)
        with self.assertRaises(ValueError):w.Replay(force_archive=1)

if __name__=='__main__':unittest.main()
