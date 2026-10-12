"""Focused contract tests for Windows compiler-request admission."""
from __future__ import annotations
import unittest
from factory.gate.windows_exit_admission import _production_compile_argv

BASE = {
    "kind": "swiftpm-windows-gui-release/1",
    "packagePath": r"D:\Claude\swiftright\.factory-work\hosts\rectangle\package",
    "scratchPath": r"D:\Claude\swiftright\.factory-work\hosts\rectangle\package\build-bound-r1\scratch",
    "compilerPath": r"C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe",
    "target": "windows-x86_64",
    "configuration": "release",
}
DEPENDENCY = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
PREFIX = ('build --package-path "' + BASE["packagePath"] + '" --scratch-path "' + BASE["scratchPath"] + '"')
SUFFIX = (' -c release -Xlinker /MANIFEST:EMBED -Xlinker "' + DEPENDENCY +
          '" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup')


class WindowsCompileRequestContractTests(unittest.TestCase):
    def test_legacy_request_keeps_exact_argv(self):
        self.assertEqual(_production_compile_argv(dict(BASE)), PREFIX + SUFFIX)

    def test_bounded_parallel_request_matches_measured_rectangle_argv(self):
        request = dict(BASE, maxParallelJobs=1)
        self.assertEqual(_production_compile_argv(request), PREFIX + " --jobs 1" + SUFFIX)

    def test_measured_text_request_matches_exact_frontend_argv(self):
        request = dict(BASE, jobs=1, maxParallelJobs=1, maxFrontendThreads=1)
        self.assertEqual(_production_compile_argv(request), PREFIX + " --jobs 1 -Xswiftc -num-threads -Xswiftc 1" + SUFFIX)

    def test_wrong_parallel_values_rejected(self):
        for value in (2, True, "1", 0, None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    _production_compile_argv(dict(BASE, maxParallelJobs=value))

    def test_measured_request_rejects_wrong_or_missing_bounds(self):
        for key, value in (("jobs", 2), ("jobs", True), ("jobs", "1"),
                           ("maxParallelJobs", 2), ("maxFrontendThreads", 2),
                           ("maxFrontendThreads", False)):
            with self.subTest(key=key, value=value):
                request = dict(BASE, jobs=1, maxParallelJobs=1, maxFrontendThreads=1)
                request[key] = value
                with self.assertRaises(ValueError):
                    _production_compile_argv(request)
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, jobs=1, maxFrontendThreads=1))
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, jobs=1, maxParallelJobs=1))
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, maxFrontendThreads=1))
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, jobs=1, maxFrontendThreads=1))
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, jobs=1, maxParallelJobs=1, maxFrontendThreads=1, frontendThreads=1))

    def test_unknown_request_key_rejected(self):
        with self.assertRaises(ValueError):
            _production_compile_argv(dict(BASE, unexpected=True))


if __name__ == "__main__":
    unittest.main()
