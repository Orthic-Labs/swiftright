"""Offline control for exact AVAILABLE auxiliary compiler archive paths."""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from factory.core.artifacts import canonical_hash
from factory.native.macos.capture import archive_origin, digest, file_ref
from factory.gate.mac_origin_admission import mac_origin_admission_issues


def _sha(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def _ref(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": digest(path), "bytes": path.stat().st_size}


def _process(pid: int, started: str, ended: str) -> dict:
    return {"pid": pid, "pgid": pid, "ownedProcessGroup": True,
            "startedAtUtc": started, "endedAtUtc": ended, "exitCode": 0,
            "cleanup": {"timedOut": False, "drainTimedOut": False,
                        "killSent": False, "termSent": False, "groupMissing": False}}


class AuxiliaryArchiveControl(unittest.TestCase):
    def test_available_aux_uses_producer_paths_after_live_delete(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            evidence = root / "output" / "swiftui.fixture"
            work = root / "scratch" / "swiftui.fixture"
            aux_work = root / "scratch" / "auxiliary-owned-location"
            evidence.mkdir(parents=True)
            work.mkdir(parents=True)
            aux_work.mkdir(parents=True)
            source = work / "Witness.swift"
            adapter = work / "CaptureHost.swift"
            binary = work / "capture-host"
            source.write_bytes(b"struct Witness {}\n")
            adapter.write_bytes(b"struct CaptureHost {}\n")
            binary.write_bytes(b"main executable\n")
            binary.chmod(0o755)
            case_file = root / "cases" / "swiftui.fixture.json"
            case_file.parent.mkdir()
            case = {"kind": "case", "version": "0.1", "id": "swiftui.fixture", "inputs": {"count": 2}}
            case_file.write_text(json.dumps(case, sort_keys=True) + "\n")
            xcrun = root / "tools" / "xcrun"
            main_frontend = root / "tools" / "main-frontend"
            aux_frontend = root / "tools" / "aux-frontend"
            for tool, raw in ((xcrun, b"xcrun fixture\n"), (main_frontend, b"main compiler\n"), (aux_frontend, b"different auxiliary compiler\n")):
                tool.parent.mkdir(parents=True, exist_ok=True)
                tool.write_bytes(raw)
            # Main/aux receipts bind xcrun to immutable archived bytes; fixture
            # keeps local stand-in only to make paths explicit.
            xcrun_hash = "sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9"
            main_logical = root / "logical" / "main-swiftc"
            aux_logical = root / "logical" / "aux-swiftc"
            main_logical.parent.mkdir()
            aux_logical.parent.mkdir(exist_ok=True)
            main_logical.write_bytes(b"main logical placeholder")
            aux_logical.write_bytes(b"aux logical placeholder")
            main_stream = evidence / "build.stdout.txt"
            main_err = evidence / "build.stderr.txt"
            main_resolve = evidence / "build-swiftc-resolve.stdout.txt"
            main_resolve_err = evidence / "build-swiftc-resolve.stderr.txt"
            main_stream.write_bytes(b"")
            main_err.write_bytes(b"")
            main_resolve.write_bytes((str(main_logical) + "\n").encode())
            main_resolve_err.write_bytes(b"")
            main_src = {"Witness.swift": _ref(source), "CaptureHost.swift": _ref(adapter)}
            main_real = {"realPath": str(main_frontend), "logicalPath": str(main_logical), "sha256": digest(main_frontend), "bytes": main_frontend.stat().st_size}
            main_compiler = _process(20, "2026-10-11T00:00:01+00:00", "2026-10-11T00:00:02+00:00") | {
                "cwd": str(work), "logicalCompilerName": "swiftc", "logicalCompilerPath": str(main_logical),
                "realPathBefore": str(main_frontend), "realHashBefore": digest(main_frontend),
                "realToolBefore": main_real, "realToolAfter": main_real, "realToolDrift": False,
                "xcrunPath": "/usr/bin/xcrun", "xcrunHash": xcrun_hash,
                "argv": [str(main_logical), "-parse-as-library", "-O", "-o", str(binary), str(source), str(adapter)],
                "stdoutPath": str(main_stream), "stdoutHash": digest(main_stream), "stderrPath": str(main_err), "stderrHash": digest(main_err),
                "sourceBefore": main_src, "sourceAfter": main_src,
                "outputBinary": {"path": str(binary), "sha256": digest(binary), "bytes": binary.stat().st_size},
                "outputMode": 0o755, "outputExecutable": True, "timedOut": False,
            }
            main_resolver = _process(19, "2026-10-11T00:00:00+00:00", "2026-10-11T00:00:00.100000+00:00") | {
                "argv": ["/usr/bin/xcrun", "--find", "swiftc"], "stdoutPath": str(main_resolve),
                "stdoutHash": digest(main_resolve), "stderrPath": str(main_resolve_err), "stderrHash": digest(main_resolve_err),
            }
            main_receipt = {"kind": "swift-compiler-process-receipt", "version": "2", "status": "SUCCESS", "sourceDrift": False,
                            "invocationMode": "direct", "resolver": main_resolver, "compiler": main_compiler,
                            "sourceBefore": main_src, "sourceAfter": main_src}
            (evidence / "compiler-receipt.json").write_text(json.dumps(main_receipt, sort_keys=True) + "\n")
            # Auxiliary receipt deliberately lives at output root, outside per-case evidence.
            aux_source = aux_work / "AXClient.swift"
            aux_binary = aux_work / "f5-ax-client"
            aux_receipt_path = root / "output" / "ax-compiler-receipt.json"
            aux_stream = root / "output" / "ax-build.stdout.txt"
            aux_err = root / "output" / "ax-build.stderr.txt"
            aux_resolve = root / "output" / "ax-build-swiftc-resolve.stdout.txt"
            aux_resolve_err = root / "output" / "ax-build-swiftc-resolve.stderr.txt"
            aux_source.write_bytes(b"struct AXClient {}\n")
            aux_binary.write_bytes(b"aux executable\n")
            aux_binary.chmod(0o755)
            for stream in (aux_stream, aux_err, aux_resolve_err): stream.write_bytes(b"")
            aux_resolve.write_bytes((str(aux_logical) + "\n").encode())
            aux_src = {"AXClient.swift": _ref(aux_source)}
            aux_real = {"realPath": str(aux_frontend), "logicalPath": str(aux_logical), "sha256": digest(aux_frontend), "bytes": aux_frontend.stat().st_size}
            aux_compiler = _process(30, "2026-10-11T00:00:03+00:00", "2026-10-11T00:00:04+00:00") | {
                "cwd": str(aux_work), "logicalCompilerName": "swiftc", "logicalCompilerPath": str(aux_logical),
                "realPathBefore": str(aux_frontend), "realHashBefore": digest(aux_frontend),
                "realToolBefore": aux_real, "realToolAfter": aux_real, "realToolDrift": False,
                "xcrunPath": "/usr/bin/xcrun", "xcrunHash": xcrun_hash,
                "argv": [str(aux_logical), "-O", "-o", str(aux_binary), str(aux_source)],
                "stdoutPath": str(aux_stream), "stdoutHash": digest(aux_stream), "stderrPath": str(aux_err), "stderrHash": digest(aux_err),
                "sourceBefore": aux_src, "sourceAfter": aux_src,
                "outputBinary": {"path": str(aux_binary), "sha256": digest(aux_binary), "bytes": aux_binary.stat().st_size},
                "outputMode": 0o755, "outputExecutable": True, "timedOut": False,
            }
            aux_resolver_record = _process(29, "2026-10-11T00:00:02+00:00", "2026-10-11T00:00:02.100000+00:00") | {
                "argv": ["/usr/bin/xcrun", "--find", "swiftc"], "stdoutPath": str(aux_resolve),
                "stdoutHash": digest(aux_resolve), "stderrPath": str(aux_resolve_err), "stderrHash": digest(aux_resolve_err),
            }
            aux_receipt = {"kind": "swift-compiler-process-receipt", "version": "2", "status": "SUCCESS", "sourceDrift": False,
                           "invocationMode": "direct", "resolver": aux_resolver_record, "compiler": aux_compiler,
                           "sourceBefore": aux_src, "sourceAfter": aux_src}
            aux_receipt_path.write_text(json.dumps(aux_receipt, sort_keys=True) + "\n")
            summary = {"kind": "macos-host-capture-candidate", "version": "0.1",
                       "case": {"id": case["id"], "hash": canonical_hash(case)},
                       "sourceHash": digest(source), "compiledAdapterHash": digest(adapter), "binaryHash": digest(binary),
                       "candidateOnly": True, "acceptance": "not-promoted", "compilerReceipt": main_receipt,
                       "freshAXClient": {"externalAX": "AVAILABLE", "sourceHash": digest(aux_source), "binaryHash": digest(aux_binary),
                                         "compilerReceiptPath": str(aux_receipt_path), "compilerReceiptHash": digest(aux_receipt_path),
                                         "compilerStatus": "SUCCESS", "compilerExitCode": 0}, "runs": []}
            summary_path = evidence / "origin-summary.json"
            summary_path.write_text(json.dumps(summary, sort_keys=True) + "\n")
            origin = {"version": "1", "captureId": "swiftui.fixture.macos.run-001", "summary": _ref(summary_path),
                      "case": _ref(case_file), "source": _ref(source), "adapter": _ref(adapter), "binary": _ref(binary),
                      "compilerReceipt": _ref(evidence / "compiler-receipt.json"),
                      "auxiliaryAX": {"receipt": _ref(aux_receipt_path), "source": _ref(aux_source), "binary": _ref(aux_binary)}}
            self.assertNotEqual(aux_receipt_path.parent, evidence)
            self.assertNotEqual(aux_source.parent, work.parent / "external-ax-client")
            capture = {"id": origin["captureId"], "platform": "macos",
                       "case": {"id": case["id"], "hash": canonical_hash(case)},
                       "meta": {"conditions": {"macOrigin": origin}}}
            # archive_origin invokes real guard before returning, including AX compiler receipt.
            reader, manifest = archive_origin(evidence, [capture], case_file, work, binary,
                                              {"externalAX": "AVAILABLE", "compilerReceiptPath": str(aux_receipt_path),
                                               "sourcePath": str(aux_source), "executable": str(aux_binary)})
            self.assertEqual("PASS", manifest["status"])
            for path in (work, case_file, aux_work, aux_receipt_path, aux_stream, aux_err, aux_resolve, aux_resolve_err):
                if path.is_dir(): shutil.rmtree(path)
                elif path.exists(): path.unlink()
            # Remove every live evidence input while retaining only durable archive.
            for path in evidence.iterdir():
                if path.name == "origin-archive":
                    continue
                if path.is_dir(): shutil.rmtree(path)
                else: path.unlink()
            self.assertEqual([], mac_origin_admission_issues(capture, lambda ref: reader(capture=capture, reference=ref)))


if __name__ == "__main__":
    unittest.main()
