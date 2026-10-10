"""Synthetic accepted receipt plus isolated production-verifier fault controls."""
import copy
import importlib.util
import json
from pathlib import Path, PureWindowsPath
import shutil
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('module_guard', HERE / 'verify_module_origin.py')
guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
INPUT = HERE.parent / 'module-origin-37429120-20261011'

class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(INPUT / 'runtime', self.root / 'runtime')
        for name in ('runtime-source-receipt.json', 'runtime-source.tar'):
            shutil.copyfile(INPUT / name, self.root / name)
        self.run = self.root / 'module-provenance-run'; self.run.mkdir()
        self.compiler = self.root / 'synthetic-swift.exe'; self.compiler.write_bytes(b'synthetic compiler fixture; never executed')
        self.compiler_patch = patch.object(guard, 'EXPECTED_COMPILER_HASH', guard.sha(self.compiler))
        self.compiler_patch.start(); self.addCleanup(self.compiler_patch.stop)
        shutil.copyfile(HERE / 'module-origin-build.ps1', self.run / 'module-origin-build.ps1')
        snapshot = json.loads((INPUT / 'runtime-source-receipt.json').read_text())
        rows = [{**r, 'bytes': (self.root / 'runtime' / r['path']).stat().st_size} for r in snapshot['completeSnapshotBindings']]
        module_root = self.resolve(guard.EXPECTED_MODULE_ROOT); module_root.mkdir(parents=True)
        (self.run / 'module-archive').mkdir()
        bindings = []
        for name in guard.EXPECTED_MODULE_NAMES:
            actual = module_root / name; actual.write_bytes(('synthetic module fixture '+name).encode())
            copied = self.run / 'module-archive' / name; shutil.copyfile(actual, copied)
            bindings.append({'sourcePath': guard.EXPECTED_MODULE_ROOT+'\\'+name, 'relativeSourcePath': name,
                'archivePath': guard.EXPECTED_RUN+'\\module-archive\\'+name, 'sha256': guard.sha(actual), 'bytes': actual.stat().st_size})
        output = {}
        for stream in ('stdout', 'stderr'):
            p = self.run / ('build.'+stream+'.txt'); p.write_text('synthetic successful compiler output fixture')
            output[stream] = {'path': guard.EXPECTED_RUN+'\\'+p.name, 'sha256': guard.sha(p), 'bytes': p.stat().st_size}
        start = '2026-10-11T20:00:00+00:00'
        self.receipt = {'kind':'factory-windows-module-origin', 'version':2, 'status':'success', 'error':'',
            'runRoot':guard.EXPECTED_RUN, 'sourceRoot':guard.EXPECTED_SOURCE, 'sourceReceipt':guard.EXPECTED_RECEIPT,
            'sourceReceiptBeforeHash':guard.EXPECTED_RECEIPT_HASH, 'sourceReceiptAfterHash':guard.EXPECTED_RECEIPT_HASH,
            'sourceArchive':{'path':guard.EXPECTED_ARCHIVE,'beforeHash':guard.EXPECTED_ARCHIVE_HASH,
                'afterHash':guard.EXPECTED_ARCHIVE_HASH,'bytes':(self.root / 'runtime-source.tar').stat().st_size},
            'sourceCommit':guard.EXPECTED_COMMIT,'sourceTreeHash':guard.EXPECTED_SOURCE_TREE,'completeSnapshotHash':guard.EXPECTED_COMPLETE,
            'sourceBefore':rows,'sourceAfter':copy.deepcopy(rows),
            'compiler':{'path':guard.EXPECTED_COMPILER,'beforeHash':guard.EXPECTED_COMPILER_HASH,'afterHash':guard.EXPECTED_COMPILER_HASH},
            'helper':{'sha256':guard.sha(HERE / 'module-origin-build.ps1'),'archivePath':guard.EXPECTED_RUN+'\\module-origin-build.ps1'},
            'command':{'executable':guard.EXPECTED_COMPILER,'arguments':guard.EXPECTED_ARGS,'launchArguments':' '.join(guard.EXPECTED_ARGS),
                'workingDirectory':guard.EXPECTED_SOURCE,'configuration':'release','testRunnerExecuted':False},
            'process':{'pid':1234,'path':guard.EXPECTED_COMPILER,'argv':guard.EXPECTED_ARGS,'workingDirectory':guard.EXPECTED_SOURCE,'startedAt':start,'observedExecutable':guard.EXPECTED_COMPILER,'observedCommandLine':'"'+guard.EXPECTED_COMPILER+'" '+' '.join(guard.EXPECTED_ARGS)},
            'startedAt':start,'finishedAt':'2026-10-11T20:00:02+00:00','buildExitCode':0,'timedOut':False,'testRunnerExecuted':False,
            'ownedProcessCleanup':{'attempted':False,'verifiedExit':True,'action':'child-exited-naturally'},
            'moduleSearchRoot':guard.EXPECTED_MODULE_ROOT,'moduleCollection':'immediately-after-successful-owned-compiler-exit',
            'moduleBindings':bindings,'output':output}
        (self.run/'owned-process.json').write_text(json.dumps(self.receipt['process']))
        self.receipt_file = self.run / 'module-provenance-receipt.json'

    def resolve(self, value):
        if value == guard.EXPECTED_COMPILER: return self.compiler
        return self.root.joinpath(*PureWindowsPath(value).relative_to(PureWindowsPath(guard.EXPECTED_ROOT)).parts)

    def verify(self, receipt=None):
        self.receipt_file.write_text(json.dumps(self.receipt if receipt is None else receipt))
        return guard.verify_receipt(self.receipt_file, resolve_path=self.resolve)

    def test_valid_synthetic_positive(self):
        self.assertTrue(self.verify()['accepted'])

    def test_receipt_faults_from_valid_positive(self):
        self.assertTrue(self.verify()['accepted'])
        faults = [
            (('sourceCommit',),guard.EXPECTED_COMMIT[:-1]), (('sourceTreeHash',),'sha256:'+'0'*64),
            (('sourceReceiptBeforeHash',),'sha256:'+'0'*64), (('completeSnapshotHash',),'sha256:'+'0'*64),
            (('sourceBefore',),[]), (('sourceAfter',),[]),
            (('compiler','path'),r'C:\wrong\swift.exe'), (('compiler','afterHash'),'sha256:'+'0'*64),
            (('command','arguments'),['build','--build-tests']), (('command','launchArguments'),'build'),
            (('command','workingDirectory'),guard.EXPECTED_RUN), (('process','path'),guard.EXPECTED_RUN),
            (('process','argv'),['test']), (('process','workingDirectory'),guard.EXPECTED_RUN),
            (('process','observedExecutable'),'wrong'), (('process','observedCommandLine'),'wrong'), (('process','pid'),True), (('process','startedAt'),'2026-10-11T20:00:01Z'),
            (('finishedAt',),'2026-10-11T19:59:59Z'), (('finishedAt',),'2026-10-11T21:00:00Z'),
            (('startedAt',),'2026-10-11T20:00:00'), (('ownedProcessCleanup','verifiedExit'),False),
            (('timedOut',),True), (('testRunnerExecuted',),True), (('buildExitCode',),1),
            (('output','stdout','path'),guard.EXPECTED_RUN+r'\..\build.stdout.txt'),
            (('output','stdout','bytes'),0), (('moduleCollection',),'historical-copy'),
            (('moduleSearchRoot',),guard.EXPECTED_SOURCE), (('moduleBindings',),[]),
            (('moduleBindings',),[self.receipt['moduleBindings'][0]]*2),
            (('moduleBindings',0,'relativeSourcePath'),'wrong.swiftmodule'),
            (('moduleBindings',0,'archivePath'),guard.EXPECTED_RUN+r'\..\forged.swiftmodule'),
            (('moduleBindings',0,'bytes'),0), (('helper','sha256'),'sha256:'+'0'*64),
        ]
        for keys, value in faults:
            with self.subTest(keys=keys):
                candidate = copy.deepcopy(self.receipt); target=candidate
                for key in keys[:-1]: target=target[key]
                target[keys[-1]]=value
                self.assertFalse(self.verify(candidate)['accepted'])
        self.assertTrue(self.verify()['accepted'])

    def test_live_file_faults_from_valid_positive(self):
        self.assertTrue(self.verify()['accepted'])
        files = [self.compiler, self.root/'runtime-source-receipt.json', self.root/'runtime-source.tar',
            self.root/'runtime'/'Package.swift', self.run/'module-origin-build.ps1', self.run/'build.stdout.txt',
            self.resolve(guard.EXPECTED_MODULE_ROOT)/guard.EXPECTED_MODULE_NAMES[0],
            self.run/'module-archive'/guard.EXPECTED_MODULE_NAMES[0]]
        for path in files:
            with self.subTest(path=path.name):
                original=path.read_bytes(); path.write_bytes(original+b'\nchanged')
                self.assertFalse(self.verify()['accepted']); path.write_bytes(original)
                self.assertTrue(self.verify()['accepted'])
                path.rename(path.with_name(path.name+'.missing'))
                self.assertFalse(self.verify()['accepted'])
                path.with_name(path.name+'.missing').rename(path)
                self.assertTrue(self.verify()['accepted'])

    def test_full_source_module_archive_coverage(self):
        self.assertTrue(self.verify()['accepted'])
        for directory in (self.root/'runtime', self.resolve(guard.EXPECTED_MODULE_ROOT), self.run/'module-archive'):
            with self.subTest(directory=directory.name):
                extra=directory/'extra'; extra.write_bytes(b'extra')
                self.assertFalse(self.verify()['accepted']); extra.unlink()
                self.assertTrue(self.verify()['accepted'])

    def test_duplicate_receipt_json(self):
        self.assertTrue(self.verify()['accepted'])
        text=self.receipt_file.read_text().replace('"version": 2', '"version": 1, "version": 2')
        self.receipt_file.write_text(text)
        self.assertFalse(guard.verify_receipt(self.receipt_file, resolve_path=self.resolve)['accepted'])

    def test_binding_production_controls(self):
        valid=[{'path':'Package.swift','sha256':'sha256:'+'a'*64}]
        self.assertEqual(guard._binding_rows(valid),valid)
        for invalid in ([],valid*2,[{'path':'../escape','sha256':'sha256:'+'a'*64}],
                [{'path':'Sources/../escape','sha256':'sha256:'+'a'*64}],
                [{'path':'Package.swift','sha256':'sha256:'+'z'*64}],
                [{'path':'b','sha256':'sha256:'+'a'*64},{'path':'a','sha256':'sha256:'+'a'*64}]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError): guard._binding_rows(invalid)
        self.assertFalse(guard.win_inside(guard.EXPECTED_ROOT+r'\..\escape',guard.EXPECTED_ROOT))

if __name__ == '__main__': unittest.main()
