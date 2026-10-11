from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from factory.core.artifacts import canonical_hash
from factory.gate.mac_origin_admission import mac_origin_admission_issues, mac_origin_admission_report


def sha(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


class OriginFixture:
    def __init__(self, root: Path):
        self.root = root
        self.data: dict[str, bytes] = {}
        self._write("source/Witness.swift", b"struct Witness {}\n")
        self._write("source/CaptureHost.swift", b"struct CaptureHost {}\n")
        self._write("bin/swift-frontend", b"swift frontend bytes\n")
        logical = self.root / "bin/swiftc"
        logical.symlink_to(self.root / "bin/swift-frontend")
        self._write("bin/xcrun", b"xcrun bytes\n")
        self._write("streams/resolve.out", b"/tmp/swiftc\n")
        self._write("streams/resolve.err", b"")
        self._write("streams/compile.out", b"")
        self._write("streams/compile.err", b"")
        self._write("bin/capture-host", b"Mach-O fixture\n")
        self.case = {"kind": "case", "version": "0.1", "id": "swiftui.fixture", "inputs": {"count": 2}}
        self.case_ref = self._ref("case.json", self._json(self.case))
        self.binary_ref = self._ref("bin/capture-host")
        self.source_ref = self._ref("source/Witness.swift")
        self.adapter_ref = self._ref("source/CaptureHost.swift")
        self.receipt = self._receipt()
        self.receipt_ref = self._ref("receipt.json", self._json(self.receipt))
        self.summary = {
            "kind": "macos-host-capture-candidate",
            "version": "0.1",
            "case": {"id": self.case["id"], "hash": canonical_hash(self.case)},
            "sourceHash": self.source_ref["sha256"],
            "compiledAdapterHash": self.adapter_ref["sha256"],
            "binaryHash": self.binary_ref["sha256"],
            "candidateOnly": True,
            "acceptance": "not-promoted",
            "compilerReceipt": self.receipt,
            "freshAXClient": {"externalAX": "HELD"},
            "runs": [],
        }
        self.summary_ref = self._ref("summary.json", self._json(self.summary))
        self.capture = {
            "id": "swiftui.fixture.macos.run-001",
            "platform": "macos",
            "case": self.case_ref | {"id": self.case["id"], "hash": canonical_hash(self.case)},
            "meta": {"conditions": {"macOrigin": {
                "version": "1",
                "summary": self.summary_ref,
                "case": self.case_ref,
                "source": self.source_ref,
                "adapter": self.adapter_ref,
                "binary": self.binary_ref,
                "compilerReceipt": self.receipt_ref,
            }}},
        }

    def refresh_receipt(self) -> None:
        raw = self._json(self.receipt)
        self._write("receipt.json", raw)
        self.capture["meta"]["conditions"]["macOrigin"]["compilerReceipt"] = self._ref("receipt.json")
        self.summary["compilerReceipt"] = self.receipt
        self.refresh_summary()

    def refresh_summary(self) -> None:
        self._write("summary.json", self._json(self.summary))
        self.capture["meta"]["conditions"]["macOrigin"]["summary"] = self._ref("summary.json")

    def _write(self, name: str, raw: bytes) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        self.data[str(path)] = raw
        return path

    def _json(self, value: object) -> bytes:
        return json.dumps(value, sort_keys=True, indent=2).encode() + b"\n"

    def _ref(self, name: str, raw: bytes | None = None) -> dict[str, object]:
        path = self.root / name
        if raw is not None:
            self._write(name, raw)
        raw = self.data[str(path)]
        return {"path": str(path), "sha256": sha(raw), "bytes": len(raw)}

    def _receipt(self) -> dict[str, object]:
        source = self.root / "source/Witness.swift"
        adapter = self.root / "source/CaptureHost.swift"
        real = self.root / "bin/swift-frontend"
        logical = self.root / "bin/swiftc"
        xcrun = self.root / "bin/xcrun"
        self._write("streams/resolve.out", (str(logical) + "\n").encode())
        empty = sha(b"")
        proc = lambda pid, started, ended: {
            "pid": pid,
            "pgid": pid,
            "ownedProcessGroup": True,
            "startedAtUtc": started,
            "endedAtUtc": ended,
            "exitCode": 0,
            "cleanup": {"timedOut": False, "drainTimedOut": False, "killSent": False, "termSent": False, "groupMissing": False},
        }
        real_ref = {"realPath": str(real), "logicalPath": str(logical), "sha256": sha(self.data[str(real)]), "bytes": len(self.data[str(real)])}
        source_ref = {"path": str(source), "sha256": sha(self.data[str(source)]), "bytes": len(self.data[str(source)])}
        adapter_ref = {"path": str(adapter), "sha256": sha(self.data[str(adapter)]), "bytes": len(self.data[str(adapter)])}
        binary = self.root / "bin/capture-host"
        compiler = proc(20, "2026-10-11T00:00:01+00:00", "2026-10-11T00:00:02+00:00")
        compiler.update({
            "cwd": str(source.parent), "logicalCompilerName": "swiftc", "logicalCompilerPath": str(logical),
            "realPathBefore": str(real), "realHashBefore": real_ref["sha256"], "realToolBefore": real_ref,
            "realToolAfter": real_ref, "realToolDrift": False, "xcrunPath": "/usr/bin/xcrun", "xcrunHash": sha(self.data[str(xcrun)]),
            "argv": [str(logical), "-parse-as-library", "-O", "-o", str(binary), str(source), str(adapter)],
            "stdoutPath": str(self.root / "streams/compile.out"), "stdoutHash": empty,
            "stderrPath": str(self.root / "streams/compile.err"), "stderrHash": empty,
            "sourceBefore": {"Witness.swift": source_ref, "CaptureHost.swift": adapter_ref},
            "sourceAfter": {"Witness.swift": source_ref, "CaptureHost.swift": adapter_ref},
            "outputBinary": {"path": str(binary), "sha256": sha(self.data[str(binary)]), "bytes": len(self.data[str(binary)])},
            "timedOut": False,
        })
        resolver = proc(19, "2026-10-11T00:00:00+00:00", "2026-10-11T00:00:00.100000+00:00")
        resolver.update({
            "argv": ["/usr/bin/xcrun", "--find", "swiftc"],
            "stdoutPath": str(self.root / "streams/resolve.out"), "stdoutHash": sha(self.data[str(self.root / "streams/resolve.out")]),
            "stderrPath": str(self.root / "streams/resolve.err"), "stderrHash": empty,
        })
        return {"kind": "swift-compiler-process-receipt", "version": "2", "status": "SUCCESS", "sourceDrift": False,
                "invocationMode": "direct", "resolver": resolver, "compiler": compiler,
                "sourceBefore": compiler["sourceBefore"], "sourceAfter": compiler["sourceAfter"]}

    def reader(self, ref: dict[str, object]) -> bytes:
        if ref["path"] == "/usr/bin/xcrun":
            return self.data[str(self.root / "bin/xcrun")]
        return self.data[str(ref["path"])]


class MacOriginAdmission(unittest.TestCase):
    def fixture(self):
        if hasattr(self, "tmp"):
            self.tmp.cleanup()
        self.tmp = tempfile.TemporaryDirectory()
        return OriginFixture(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def test_positive_origin_only_result(self):
        f = self.fixture()
        self.assertEqual([], mac_origin_admission_issues(f.capture, f.reader))
        report = mac_origin_admission_report(f.capture, f.reader)
        self.assertEqual("PASS", report["status"])
        self.assertTrue(report["originQualified"])
        self.assertFalse(report["parityGranted"])

    def assert_fault(self, mutate, token):
        f = self.fixture()
        mutate(f)
        issues = mac_origin_admission_issues(f.capture, f.reader)
        self.assertTrue(any(token in issue for issue in issues), (token, issues))

    def test_isolated_fault_controls(self):
        self.assert_fault(lambda f: f.capture["meta"]["conditions"]["macOrigin"].pop("compilerReceipt"), "missing-ref")
        self.assert_fault(lambda f: f.capture["meta"]["conditions"]["macOrigin"].update(binary=f.capture["meta"]["conditions"]["macOrigin"]["source"]), "binary-join")
        self.assert_fault(lambda f: f.capture.update(case={"id": "wrong", "hash": canonical_hash({"id": "wrong"})}), "wrong-case")
        self.assert_fault(lambda f: f.capture["meta"]["conditions"]["macOrigin"]["source"].update(sha256=sha(b"wrong")), "hash")

        def bad_tool(f):
            f.receipt["compiler"]["logicalCompilerPath"] = "relative/swiftc"
            f.refresh_receipt()
        self.assert_fault(bad_tool, "tool-path")

        def bad_pid(f):
            f.receipt["compiler"]["pgid"] = 999
            f.refresh_receipt()
        self.assert_fault(bad_pid, "process-owner")

        def bad_drift(f):
            f.receipt["sourceDrift"] = True
            f.refresh_receipt()
        self.assert_fault(bad_drift, "receipt-status")

        def bad_stream(f):
            f.data[str(f.root / "streams/compile.out")] = b"tampered"
        self.assert_fault(bad_stream, "hash")

        def missing_adapter(f):
            f.capture["meta"]["conditions"]["macOrigin"].pop("adapter")
        self.assert_fault(missing_adapter, "missing-ref")

        def extra_source(f):
            f.receipt["compiler"]["argv"].append("/extra.swift")
            f.refresh_receipt()
        self.assert_fault(extra_source, "source-argv")

        def resolver_order(f):
            f.receipt["compiler"]["startedAtUtc"] = "2026-10-10T23:59:58+00:00"
            f.refresh_receipt()
        self.assert_fault(resolver_order, "process-time")

        def resolver_identity(f):
            f.data[str(f.root / "streams/resolve.out")] = b"/tmp/unrelated\n"
        self.assert_fault(resolver_identity, "resolver-identity")

        def claimed_ax_without_receipt(f):
            f.summary["freshAXClient"] = {"externalAX": "AVAILABLE"}
            f.refresh_summary()
        self.assert_fault(claimed_ax_without_receipt, "ax-join")

        def malformed_argv(f):
            f.receipt["compiler"]["argv"] = []
            f.refresh_receipt()
        self.assert_fault(malformed_argv, "compiler-argv")

        def missing_case(f):
            f.capture.pop("case")
        self.assert_fault(missing_case, "wrong-case")

        def unsupported_top_level(f):
            f.capture["macOrigin"] = copy.deepcopy(f.capture["meta"]["conditions"]["macOrigin"])
        self.assert_fault(unsupported_top_level, "unsupported-location")

    def test_auxiliary_ax_requires_exact_receipt_source_binary(self):
        f = self.fixture()
        self.assertEqual([], mac_origin_admission_issues(f.capture, f.reader))
        ax_source = f._write("ax/AXClient.swift", b"struct AXClient {}\n")
        ax_binary = f._write("ax/f5-ax-client", b"AX Mach-O fixture\n")
        # Reuse receipt shape, then retarget source/output and process refs.
        ax = copy.deepcopy(f.receipt)
        ax["compiler"]["sourceBefore"] = {"AXClient.swift": {"path": str(ax_source), "sha256": sha(ax_source.read_bytes()), "bytes": ax_source.stat().st_size}}
        ax["compiler"]["sourceAfter"] = copy.deepcopy(ax["compiler"]["sourceBefore"])
        ax["sourceBefore"] = ax["compiler"]["sourceBefore"]
        ax["sourceAfter"] = ax["compiler"]["sourceAfter"]
        ax["compiler"]["cwd"] = str(ax_source.parent)
        ax["compiler"]["argv"] = [str(f.root / "bin/swiftc"), "-O", "-o", str(ax_binary), str(ax_source)]
        ax["compiler"]["outputBinary"] = {"path": str(ax_binary), "sha256": sha(ax_binary.read_bytes()), "bytes": ax_binary.stat().st_size}
        ax_ref = f._ref("ax-receipt.json", f._json(ax))
        f.capture["meta"]["conditions"]["macOrigin"]["auxiliaryAX"] = {"receipt": ax_ref, "source": {"path": str(ax_source), "sha256": sha(ax_source.read_bytes()), "bytes": ax_source.stat().st_size}, "binary": {"path": str(ax_binary), "sha256": sha(ax_binary.read_bytes()), "bytes": ax_binary.stat().st_size}}
        f.summary["freshAXClient"] = {"externalAX": "AVAILABLE", "sourceHash": f.capture["meta"]["conditions"]["macOrigin"]["auxiliaryAX"]["source"]["sha256"], "binaryHash": f.capture["meta"]["conditions"]["macOrigin"]["auxiliaryAX"]["binary"]["sha256"], "compilerReceiptHash": ax_ref["sha256"], "compilerStatus": "SUCCESS", "compilerExitCode": 0}
        f.refresh_summary()
        self.assertEqual([], mac_origin_admission_issues(f.capture, f.reader))
        f.capture["meta"]["conditions"]["macOrigin"]["auxiliaryAX"]["binary"]["sha256"] = sha(b"wrong")
        self.assertTrue(any("ax" in issue for issue in mac_origin_admission_issues(f.capture, f.reader)))


if __name__ == "__main__":
    unittest.main()
