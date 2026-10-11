"""Synthetic archive fixtures only; structural passes never qualify native output."""
import copy
import hashlib
import json
import unittest
from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import (
    verify_windows_exit_admission, windows_exit_admission_issues,
    make_windows_exit_admission,
)


def raw_hash(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


class Fixture:
    """Every byte/identity is invented test data, never measured evidence."""
    def __init__(self):
        self.raw = {'witness': b'// synthetic test-only witness\n',
                    'exe': b'synthetic test-only EXE', 'renderer': b'synthetic DLL',
                    'stdout': b'synthetic stdout\n', 'stderr': b''}
        h = lambda role: raw_hash(self.raw[role])
        commit = 'a' * 40
        self.runtime = {'Package.swift': b'// synthetic runtime package',
                        'Sources/SwiftRightRuntime/Test.swift': b'// synthetic runtime source'}
        tree = [{'path': path, 'sha256': raw_hash(raw)} for path, raw in self.runtime.items()]
        self.compiler = b'synthetic compiler executable'
        rr = {'sourceCommit': commit, 'sourceTreeHash': canonical_hash(tree)}
        plan = {'case': 'synthetic-case', 'sourceHash': h('witness'),
                'runtimeSourceCommit': commit, 'runtimeSourceTreeHash': canonical_hash(tree)}
        build = {'sourceHash': h('witness'), 'exeSha256': h('exe')[7:],
                 'rendererSha256': h('renderer')[7:], 'exePath': 'D:\\synthetic\\build-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe',
                 'runtimeSourceCommit': commit, 'runtimeSourceTreeHash': canonical_hash(tree),
                 'exitCode': 0, 'timedOut': False, 'ownedExited': True}
        request = {'kind': 'swiftpm-windows-gui-release/1', 'packagePath': 'D:\\synthetic',
                   'scratchPath': 'D:\\synthetic\\build-r1\\scratch',
                   'compilerPath': 'C:\\Swift\\usr\\bin\\swift.exe',
                   'configuration': 'release', 'target': 'windows-x86_64'}
        argv = ('build --package-path "D:\\synthetic" --scratch-path "D:\\synthetic\\build-r1\\scratch" -c release '
                '-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTDEPENDENCY:type=\'win32\' name=\'Microsoft.Windows.Common-Controls\' '
                'version=\'6.0.0.0\' processorArchitecture=\'*\' publicKeyToken=\'6595b64144ccf1df\' language=\'*\'" '
                '-Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup')
        build.update(pid=789, argv=argv, cwd='D:\\synthetic', compilerPath=request['compilerPath'],
                     target='windows-x86_64', configuration='release',
                     startedAt='2026-10-11T00:59:00Z',
                     processStartedAt='2026-10-11T00:59:01Z',
                     finishedAt='2026-10-11T00:59:59Z',
                     compilerHash=raw_hash(self.compiler)[7:], error=None, cleanupError=None)
        plan.update(rendererSha256=h('renderer')[7:], compilerHash=raw_hash(self.compiler))
        plan.update(compileRequest=request, compilerPath=request['compilerPath'])
        owned = {'pid': 123, 'path': build['exePath'], 'startedAt': '2026-10-11T01:00:00Z'}
        close = {'pid': 123, 'hwnd': 456, 'message': 16, 'messageName': 'WM_CLOSE',
                 'posted': True, 'activationRequested': False, 'at': '2026-10-11T01:00:10Z'}
        streams = []
        for name in ('stdout', 'stderr'):
            streams.append({'name': name, 'copyCompleted': True, 'destinationClosed': True,
                            'sealed': True, 'taskIsCompleted': True, 'taskIsFaulted': False,
                            'taskIsCanceled': False, 'taskStatus': 'RanToCompletion',
                            'closureTaskStatus': 'RanToCompletion', 'taskException': '',
                            'hashQualification': 'sealed-raw',
                            'closure': {'flushCompleted': True, 'destinationClosed': True,
                                        'completedWithinDeadline': True, 'deadlineExpired': False,
                                        'error': ''}})
        outcome = {'primaryError': '', 'streamErrors': [], 'ownedIdentity': copy.deepcopy(owned),
                   'sourceHash': h('witness'), 'exeHash': h('exe')[7:],
                   'cleanup': {'exitCertification': 'retained-kernel-handle',
                               'kernelExitSignaled': True, 'confirmedOwnedExit': True,
                               'kernelWaitResult': 0, 'status': 'already-signaled', 'error': ''},
                   'rawStreams': streams, 'rawHashesQualification': 'sealed-raw',
                   'rawHashStates': {n: {'qualification': 'sealed-raw', 'error': '',
                                        'sha256': h(n)[7:]} for n in ('stdout', 'stderr')},
                   'stdoutSha256': h('stdout')[7:], 'stderrSha256': h('stderr')[7:]}
        row = {'index': 1, 'exitCode': 0, 'hostValid': True, 'case': plan['case'],
               'ownedIdentity': copy.deepcopy(owned), 'hwnd': 456,
               'sourceHash': h('witness'), 'exeSha256': h('exe')[7:],
               'rendererSha256': h('renderer')[7:], 'runtimeSourceCommit': commit,
               'runtimeSourceTreeHash': canonical_hash(tree), 'files': []}
        self.objects = {'runtimeTree': tree, 'runtimeReceipt': rr, 'plan': plan,
                        'compile': build, 'owned': owned, 'close': close,
                        'outcome': outcome, 'observation': [row]}
        self.host = {'Package.swift': b'// synthetic package',
                     'Sources/FactoryProbe/main.swift': b'// synthetic main',
                     'Sources/FactoryProbe/Witness.swift': self.raw['witness']}
        plan['sourceBindings'] = [{'path': path, 'sha256': raw_hash(raw)}
                                  for path, raw in self.host.items()]
        self.capture = {'platform': 'windows', 'case': plan['case'],
                        'tuple': {'rendererHash': h('renderer'), 'runtimeCommit': commit},
                        'provenance': {'sourceHash': h('witness')},
                        'meta': {'run': 1, 'host': {'hash': h('exe')}, 'clock': {},
                                 'conditions': {'synthetic': True, 'producer': 'test-fixture',
                                                'actualSourceHash': h('witness'),
                                                'actualHostExecutableHash': h('exe'),
                                                'actualRendererHash': h('renderer')}}}
        self.rebind()

    def rebind(self):
        """Refresh outer hashes after faults so semantic checks must reject."""
        for role in ('runtimeTree', 'runtimeReceipt'):
            self.raw[role] = encode(self.objects[role])
        plan = self.objects['plan']
        plan['runtimeSourceReceiptHash'] = raw_hash(self.raw['runtimeReceipt'])
        plan['runtimeSourceTreeFileHash'] = raw_hash(self.raw['runtimeTree'])
        self.raw['plan'] = encode(plan)
        self.objects['compile']['planSha256'] = raw_hash(self.raw['plan'])[7:]
        self.raw['compile'] = encode(self.objects['compile'])
        self.objects['outcome']['compileReceiptHash'] = raw_hash(self.raw['compile'])[7:]
        for role in ('owned', 'close', 'outcome'):
            self.raw[role] = encode(self.objects[role])
        self.objects['observation'][0]['files'] = [
            {'path': role + '.raw', 'sha256': raw_hash(self.raw[role])[7:]}
            for role in ('outcome', 'owned', 'close', 'stdout', 'stderr')]
        self.raw['observation'] = encode(self.objects['observation'])
        self.capture['meta']['conditions']['windowsExitProof'] = {'version': 1, 'files': {
            role: {'path': role + '.raw', 'hash': raw_hash(raw)} for role, raw in self.raw.items()}}
        self.capture['meta']['conditions']['rawReceiptHash'] = raw_hash(self.raw['observation'])
        self.capture['meta']['clock']['correlationHash'] = raw_hash(self.raw['observation'])

    def reader(self, path):
        if path=='tool/compiler.bin':
            return self.compiler
        if path.startswith('runtime/'):
            return self.runtime[path[8:]]
        if path.startswith('host/'):
            return self.host[path[5:]]
        return self.raw[path.removesuffix('.raw')]

    def result(self):
        return verify_windows_exit_admission(self.capture, read_bytes=self.reader)


class WindowsExitAdmissionTests(unittest.TestCase):
    def test_synthetic_structural_control_is_exit_only(self):
        f = Fixture(); result = f.result()
        self.assertEqual(result['issues'], [])
        self.assertFalse(result['nativeParityGranted'])
        self.assertEqual(result['captureHash'], canonical_hash(f.capture))
        self.assertEqual(len(result['evidence']['rawInputs']), 19)

    def fault(self, mutate):
        f = Fixture(); self.assertEqual(f.result()['issues'], [])
        mutate(f); f.rebind()
        self.assertEqual(f.result()['status'], 'blocked')
        self.assertTrue(windows_exit_admission_issues(f.capture, f.reader))

    def test_legacy_hasexited_is_not_kernel_proof(self):
        self.fault(lambda f: f.objects['outcome'].update(cleanup={
            'confirmedOwnedExit': True, 'hasExited': True, 'error': ''}))

    def test_successful_cleanup_cannot_erase_primary_failure(self):
        self.fault(lambda f: f.objects['outcome'].update(primaryError='Owned renderer child deadline'))

    def test_production_compiler_invocation_isolated_coherent_faults(self):
        for field, value in (('argv', 'unrelated.exe --no-source'), ('cwd', 'D:\\foreign'),
                             ('compilerPath', 'C:\\foreign\\swift.exe'), ('target', 'linux-x86_64'),
                             ('configuration', 'debug')):
            with self.subTest(field=field):
                self.fault(lambda f: f.objects['compile'].update({field: value}))
        for old, new in (('D:\\synthetic"', 'D:\\foreign"'), ('-c release', '-c debug'),
                         ('/SUBSYSTEM:WINDOWS', '/SUBSYSTEM:CONSOLE'),
                         ('/ENTRY:mainCRTStartup', '/ENTRY:wrong'),
                         ('/MANIFEST:EMBED', '/MANIFEST:NO')):
            with self.subTest(flag=old):
                self.fault(lambda f: f.objects['compile'].update(argv=f.objects['compile']['argv'].replace(old,new)))
        self.fault(lambda f: f.objects['compile'].update(exePath='D:\\foreign\\FactoryProbe.exe'))
        self.fault(lambda f: f.objects['plan']['compileRequest'].update(configuration='debug'))
        self.fault(lambda f: f.objects['plan']['compileRequest'].update(target='windows-arm64'))
        self.fault(lambda f: f.objects['plan']['compileRequest'].update(scratchPath='D:\\foreign\\scratch'))

    def test_exact_terminal_cleanup_status(self):
        for status in ('hold-cleanup', '', None, True, [], 'Already-Signaled'):
            with self.subTest(status=status):
                self.fault(lambda f: f.objects['outcome']['cleanup'].update(status=status))
        for status in ('already-signaled','signaled-after-exit-observation','signaled-during-lookup',
                       'signaled-before-kill','signaled-during-kill','killed-owned-handle-signaled'):
            f=Fixture();f.objects['outcome']['cleanup']['status']=status;f.rebind()
            self.assertEqual(f.result()['issues'], [])

    def test_malformed_capture_and_nested_objects_fail_closed(self):
        for capture in (None, [], 1, 'bad', {'platform': 'windows'}, {'platform': 'windows', 'meta': []}):
            with self.subTest(capture=capture):
                self.assertTrue(windows_exit_admission_issues(capture, lambda _: b''))
                self.assertEqual(make_windows_exit_admission(lambda _: lambda path:b'')(captures=[capture])['status'],'blocked')
        self.assertEqual(make_windows_exit_admission(lambda _:None)(captures=None)['status'],'blocked')
        for role in ('plan','compile','owned','close','outcome','runtimeReceipt'):
            f=Fixture(); self.assertEqual(f.result()['issues'], [])
            f.raw[role]=b'[]'
            f.capture['meta']['conditions']['windowsExitProof']['files'][role]['hash']=raw_hash(b'[]')
            self.assertTrue(f.result()['issues'])

    def test_kernel_wait_requires_exact_zero_integer(self):
        for bad in (258, 4294967295, False, '0', None):
            with self.subTest(bad=bad):
                self.fault(lambda f: f.objects['outcome']['cleanup'].update(kernelWaitResult=bad))

    def test_owned_identity_and_close_faults(self):
        for field, value in (('pid', 124), ('path', 'D:\\wrong.exe'), ('startedAt', 'wrong')):
            with self.subTest(field=field):
                self.fault(lambda f: f.objects['owned'].update({field: value}))
        for field, value in (('pid', True), ('hwnd', False), ('message', False),
                             ('posted', False), ('activationRequested', True)):
            with self.subTest(field=field):
                self.fault(lambda f: f.objects['close'].update({field: value}))
        self.fault(lambda f: f.objects['close'].update(at='2026-10-11T00:59:59.9999999Z'))
        def boolean_identity(f):
            f.objects['owned']['pid'] = 1
            f.objects['outcome']['ownedIdentity']['pid'] = True
            f.objects['observation'][0]['ownedIdentity']['pid'] = 1
            f.objects['close']['pid'] = 1
        self.fault(boolean_identity)

    def test_stream_completion_sealing_and_exact_count(self):
        for field, value in (('copyCompleted', False), ('destinationClosed', False),
                             ('sealed', False), ('taskIsFaulted', True), ('taskIsCanceled', True),
                             ('taskStatus', 'Running'), ('hashQualification', 'partial-diagnostic')):
            with self.subTest(field=field):
                self.fault(lambda f: f.objects['outcome']['rawStreams'][0].update({field: value}))
        self.fault(lambda f: f.objects['outcome']['rawStreams'].pop())
        self.fault(lambda f: f.objects['outcome']['rawStreams'][1].update(name='stdout'))
        self.fault(lambda f: f.objects['outcome']['rawStreams'][0]['closure'].update(deadlineExpired=True))

    def test_raw_stream_hashes_and_missing_bytes(self):
        f = Fixture(); f.raw['stdout'] += b'drift'; self.assertTrue(f.result()['issues'])
        self.fault(lambda f: f.raw.update(stdout=b'drift'))
        f = Fixture()
        def missing(_):
            raise FileNotFoundError('missing owned archive bytes')
        self.assertTrue(windows_exit_admission_issues(f.capture, missing))

    def test_source_compile_executable_and_runtime_joins(self):
        for role in ('witness', 'exe', 'renderer'):
            with self.subTest(role=role):
                self.fault(lambda f: f.raw.update({role: b'changed test-only bytes'}))
        self.fault(lambda f: f.objects['compile'].update(exitCode=False))
        self.fault(lambda f: f.objects['compile'].update(timedOut=True))
        self.fault(lambda f: f.objects['compile'].update(pid=True))
        self.fault(lambda f: f.objects['compile'].update(compilerHash='d'*64))
        self.fault(lambda f: f.objects['compile'].update(finishedAt='2026-10-11T01:01:00Z'))
        self.fault(lambda f: f.objects['runtimeReceipt'].update(sourceCommit='b' * 40))
        self.fault(lambda f: f.objects['runtimeTree'].append({'path': 'extra', 'hash': 'drift'}))
        self.fault(lambda f: f.host.update({'Sources/FactoryProbe/main.swift': b'drift'}))
        self.fault(lambda f: f.objects['plan'].update(sourceBindings=[]))
        self.fault(lambda f: f.runtime.update({'Package.swift': b'changed runtime package'}))
        self.fault(lambda f: setattr(f, 'compiler', b'changed compiler bytes'))

    def test_run_case_and_boolean_exit_faults(self):
        self.fault(lambda f: f.objects['observation'][0].update(index=True))
        self.fault(lambda f: f.objects['observation'][0].update(exitCode=False))
        self.fault(lambda f: f.objects['observation'][0].update(case='wrong'))
        self.fault(lambda f: f.objects['observation'][0].update(hwnd=True))
        self.fault(lambda f: f.objects['observation'][0]['ownedIdentity'].update(pid=124))
        self.fault(lambda f: f.objects['observation'].append(copy.deepcopy(f.objects['observation'][0])))
        f = Fixture(); f.capture['meta']['run'] = True; self.assertTrue(f.result()['issues'])

    def test_reference_coverage_paths_and_duplicate_json(self):
        for mode in ('missing', 'escape', 'duplicate', 'hash'):
            f = Fixture(); refs = f.capture['meta']['conditions']['windowsExitProof']['files']
            if mode == 'missing': refs.pop('close')
            elif mode == 'escape': refs['close']['path'] = '../close.raw'
            elif mode == 'duplicate': refs['close']['path'] = refs['owned']['path']
            else: refs['close']['hash'] = 'sha256:' + '0' * 64
            self.assertTrue(f.result()['issues'])
        f = Fixture(); f.raw['close'] = b'{"pid":123,"pid":123}'
        f.capture['meta']['conditions']['windowsExitProof']['files']['close']['hash'] = raw_hash(f.raw['close'])
        self.assertTrue(f.result()['issues'])

    def test_labels_and_caller_pass_cannot_bypass_reader(self):
        for label in ('pass', 'qualified', True):
            f = Fixture(); f.capture['meta']['conditions'].update(nativeParity=label, verified=True)
            del f.capture['meta']['conditions']['windowsExitProof']
            self.assertTrue(f.result()['issues'])
            callback = make_windows_exit_admission(lambda _: f.reader)
            self.assertEqual(callback(captures=[f.capture], verified=True)['status'], 'blocked')
        self.assertEqual(make_windows_exit_admission(lambda _: None)(captures=[])['status'], 'blocked')


if __name__ == '__main__':
    unittest.main()
