"""Unit tests for qualification/run.py (no GUI, no Windows, no network).

Run: python3 -I -m unittest discover -s qualification -v
"""
import argparse
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import run as q

QUAL = Path(__file__).resolve().parent
SCRATCH = QUAL / "out" / "tests"


def trace_lines(step_values):
    """Synthetic normalized-looking JSONL events. step_values: list of (step, payload-int)."""
    # Already normalized (mono_ns dropped, keys sorted), as read_normalized() returns them.
    out = []
    for step, value in step_values:
        out.append(json.dumps({"fixture": "F1", "kind": "lifecycle", "node_id": f"n{value}",
                               "payload": {"v": value}, "step": step}, sort_keys=True, separators=(",", ":")))
    return out


class FakeEnv(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.accepted = self.dir / "accepted"
        self.candidates = self.dir / "candidates"
        self.binary = self.dir / "FixtureApp"
        self.binary.write_bytes(b"fake-binary-v1")
        self.log = q.EventLog(self.dir / "events.jsonl", echo=False)
        self.captured = []
        self._stdout_patch = None

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def write_accepted(self, lines, fixture="F1"):
        fixture_dir = self.accepted / fixture
        fixture_dir.mkdir(parents=True)
        q.write_accepted(fixture_dir, lines, {"source": "test"})

    def fake_launcher(self, per_run):
        """per_run: list of (lines or None, verdict_text). Writes the events file and returns the launch dict."""
        def launch(binary, fixture, events, stdout):
            lines, verdict = per_run[len(self.captured)]
            self.captured.append(events)
            if lines is not None:
                q.write_lines(Path(events), lines)
            Path(stdout).write_text(verdict + "\n", encoding="utf-8")
            return {"rc": 0, "stdout": verdict + "\n", "attempts": ["attempt 1: root-appear"]}
        return launch

    def events(self):
        return [json.loads(l) for l in (self.dir / "events.jsonl").read_text().splitlines() if l.strip()]


class EventSchemaTests(unittest.TestCase):
    def valid(self, **overrides):
        record = {"ts": "2026-10-09T10:15:30.123Z", "stage": "mac-oracle", "event": "pass", "fixture": "F1",
                  "artifact_ids": {"fixture_binary": "sha256:" + "a" * 64}, "reason": "ok"}
        record.update(overrides)
        return record

    def test_valid_record_passes(self):
        q.validate_event(self.valid())

    def test_key_set_is_exact(self):
        record = self.valid()
        record["extra"] = 1
        with self.assertRaises(ValueError):
            q.validate_event(record)
        record = self.valid()
        del record["reason"]
        with self.assertRaises(ValueError):
            q.validate_event(record)

    def test_stage_and_event_are_closed_sets(self):
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(stage="deploy"))
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(event="done"))

    def test_timestamp_format(self):
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(ts="2026-10-09 10:15:30"))

    def test_fail_and_skip_need_reason(self):
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(event="fail", reason=""))
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(event="skip", reason=None))
        q.validate_event(self.valid(event="start", reason=None))

    def test_artifact_ids_must_be_sha256_refs(self):
        with self.assertRaises(ValueError):
            q.validate_event(self.valid(artifact_ids={"fixture_binary": "deadbeef"}))

    def test_emit_writes_jsonl_to_file(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            log = q.EventLog(Path(tmp) / "e.jsonl", echo=False)
            log.emit("compare", "fail", "F1", reason="x")
            log.close()
            record = json.loads((Path(tmp) / "e.jsonl").read_text().strip())
            self.assertEqual(record["event"], "fail")
            self.assertEqual(log.failures, 1)


class DigestTests(unittest.TestCase):
    def test_raw_digest_matches_normalize_hash_definition(self):
        lines = trace_lines([("init", 1), ("type", 2)])
        expected = hashlib.sha256("\n".join(lines).encode()).hexdigest()
        self.assertEqual(q.raw_digest(lines), expected)

    def test_canonical_ignores_order_within_a_step_only(self):
        a = trace_lines([("s1", 1), ("s1", 2), ("s2", 3)])
        b = trace_lines([("s1", 2), ("s1", 1), ("s2", 3)])
        self.assertEqual(q.canonical_digest(a), q.canonical_digest(b))
        c = trace_lines([("s2", 3), ("s1", 1), ("s1", 2)])
        self.assertNotEqual(q.canonical_digest(a), q.canonical_digest(c))

    def test_mono_ns_is_dropped(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            p = Path(tmp) / "t.jsonl"
            p.write_text('{"step":"a","mono_ns":1,"x":2}\n{"step":"a","mono_ns":99,"x":2}\n')
            self.assertEqual(q.read_normalized(p)[0], q.read_normalized(p)[1])


class CandidateNotPromotedTests(FakeEnv):
    def test_differing_trace_becomes_candidate_and_accepted_is_unchanged(self):
        accepted = trace_lines([("init", 1), ("type", 2)])
        self.write_accepted(accepted)
        before = (self.accepted / "F1" / "manifest.json").read_bytes(), (self.accepted / "F1" / "trace.jsonl").read_bytes()
        changed = trace_lines([("init", 1), ("type", 9)])
        ok = q.oracle_fixture("F1", 3, self.fake_launcher([(changed, "SELFTEST F1: PASS (7/7)")] * 3),
                              self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        self.assertFalse(ok)
        after = (self.accepted / "F1" / "manifest.json").read_bytes(), (self.accepted / "F1" / "trace.jsonl").read_bytes()
        self.assertEqual(before, after, "oracle must never write accepted traces")
        meta_files = list((self.candidates / "F1").glob("*/candidate.json"))
        self.assertEqual(len(meta_files), 1, "one candidate per distinct differing trace")
        meta = json.loads(meta_files[0].read_text())
        self.assertEqual(meta["status"], "candidate-not-promoted")
        self.assertIsNone(meta["approval"])
        diff = (meta_files[0].parent / "diff.txt").read_text()
        self.assertIn('"v":9', diff)
        final = [e for e in self.events() if e["stage"] == "mac-oracle" and e["event"] == "fail"][-1]
        self.assertIn("NOT promoted", final["reason"])

    def test_matching_trace_passes_and_writes_no_candidate(self):
        lines = trace_lines([("init", 1), ("type", 2)])
        self.write_accepted(lines)
        ok = q.oracle_fixture("F1", 2, self.fake_launcher([(lines, "SELFTEST F1: PASS (7/7)")] * 2),
                              self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        self.assertTrue(ok)
        self.assertFalse(self.candidates.exists())
        self.assertEqual(self.log.failures, 0)

    def test_failing_self_test_fails_without_candidate(self):
        lines = trace_lines([("init", 1)])
        self.write_accepted(lines)
        other = trace_lines([("init", 5)])
        ok = q.oracle_fixture("F1", 1, self.fake_launcher([(other, "SELFTEST F1: FAIL (6/7)")]),
                              self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        self.assertFalse(ok)
        self.assertFalse(self.candidates.exists(), "a failed assertion is a fail, not a candidate")

    def test_missing_baseline_writes_candidate_and_fails(self):
        lines = trace_lines([("init", 1)])
        ok = q.oracle_fixture("F1", 1, self.fake_launcher([(lines, "SELFTEST F1: PASS (7/7)")]),
                              self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        self.assertFalse(ok)
        self.assertTrue(list((self.candidates / "F1").glob("*/candidate.jsonl")))
        self.assertFalse((self.accepted / "F1").exists())


class PromoteTests(FakeEnv):
    def make_candidate(self, lines):
        self.write_accepted(trace_lines([("init", 1)]))
        q.oracle_fixture("F1", 1, self.fake_launcher([(lines, "SELFTEST F1: PASS (7/7)")]),
                         self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        return next((self.candidates / "F1").glob("*"))

    def args(self, *extra):
        return q.build_parser().parse_args(list(extra))

    def promote(self, argv):
        return q.cmd_promote(self.args(*argv), self.log, accepted_root=self.accepted)

    def test_approved_by_flag_is_required(self):
        with self.assertRaises(SystemExit):
            self.args("promote", "--fixture", "F1", "--candidate", str(self.dir))

    def test_blank_approver_is_refused(self):
        with self.assertRaises(q.ApprovalError):
            q.check_approver("   ")
        with self.assertRaises(q.ApprovalError):
            q.check_approver("bad;name")

    def test_promote_records_approver_and_history(self):
        new_lines = trace_lines([("init", 1), ("type", 7)])
        candidate = self.make_candidate(new_lines)
        ok = self.promote(("promote", "--fixture", "F1", "--candidate", str(candidate),
                                     "--approved-by", "Test Approver"))
        self.assertTrue(ok)
        manifest = json.loads((self.accepted / "F1" / "manifest.json").read_text())
        self.assertEqual(manifest["approved_by"], "Test Approver")
        self.assertEqual(manifest["canonical_sha256"], q.canonical_digest(new_lines))
        log_line = json.loads((self.accepted / "F1" / "PROMOTIONS.jsonl").read_text().splitlines()[-1])
        self.assertEqual(log_line["approved_by"], "Test Approver")
        self.assertTrue(list((self.accepted / "F1" / "history").glob("*/trace.jsonl")))

    def test_promote_refuses_tampered_candidate(self):
        candidate = self.make_candidate(trace_lines([("init", 1), ("type", 7)]))
        q.write_lines(candidate / "candidate.jsonl", trace_lines([("init", 1), ("type", 8)]))
        ok = self.promote(("promote", "--fixture", "F1", "--candidate", str(candidate),
                                     "--approved-by", "A"))
        self.assertFalse(ok)


class ArtifactIdentityTests(FakeEnv):
    def test_pass_events_carry_binary_and_trace_hashes(self):
        lines = trace_lines([("init", 1)])
        self.write_accepted(lines)
        q.oracle_fixture("F1", 1, self.fake_launcher([(lines, "SELFTEST F1: PASS (7/7)")]),
                         self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        run_event = [e for e in self.events() if e["event"] == "pass" and "run 1/1" in (e["reason"] or "")][0]
        binary_sha = hashlib.sha256(b"fake-binary-v1").hexdigest()
        self.assertEqual(run_event["artifact_ids"]["fixture_binary"], "sha256:" + binary_sha)
        self.assertEqual(run_event["artifact_ids"]["trace_raw"], "sha256:" + q.raw_digest(lines))
        self.assertEqual(run_event["artifact_ids"]["trace_canonical"], "sha256:" + q.canonical_digest(lines))

    def test_corrupt_accepted_trace_is_detected(self):
        lines = trace_lines([("init", 1)])
        self.write_accepted(lines)
        q.write_lines(self.accepted / "F1" / "trace.jsonl", trace_lines([("init", 2)]))
        with self.assertRaises(q.AcceptedError):
            q.load_accepted(self.accepted, "F1")


class PlanTests(unittest.TestCase):
    def test_win_plan_names_matrix_script_and_runs(self):
        plan = q.win_plan(["F1:none"], 3, Path("/x"))
        self.assertEqual(plan["command"][1], str(q.MATRIX_SCRIPT))
        self.assertEqual(plan["env"]["RUNS"], "3")

    def test_win_stage_refuses_without_confirmation(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            log = q.EventLog(Path(tmp) / "e.jsonl", echo=False)
            self.assertFalse(q.win_stage(log, ["F1:none"], 3, Path(tmp), dry_run=False, confirmed=False))
            self.assertEqual(log.failures, 1)
            log.close()



class ConfigAddressingTests(FakeEnv):
    def test_allow_list_is_the_sixteen_known_configs(self):
        self.assertEqual(len(q.CONFIGS), 16)
        self.assertEqual(q.CONFIGS["F3"], ("F3", ()))
        self.assertEqual(q.CONFIGS["F3-lazy-3s"], ("F3", ("--f3-variant", "lazy-3s")))
        self.assertEqual(q.CONFIGS["F6-reduced"], ("F6", ("--reduced-motion-variant",)))

    def test_unknown_configs_are_refused(self):
        for bad in ("F10", "F3-list-0s", "F3-list-2s", "F6-reduced-x", "F3-list-1s; rm", "f3"):
            with self.assertRaises(argparse.ArgumentTypeError):
                q.validate_fixture(bad)
        with self.assertRaises(ValueError):
            q.self_test_argv("/b/FixtureApp", "F3-list-2s", "/e.jsonl")

    def test_variant_flags_precede_self_test_which_stays_last(self):
        argv = q.self_test_argv("/b/FixtureApp", "F3-lazy-3s", "/e.jsonl")
        self.assertEqual(argv, ["/b/FixtureApp", "--fixture", "F3", "--events", "/e.jsonl",
                                "--f3-variant", "lazy-3s", "--self-test"])

    def test_reduced_motion_config_uses_reduced_flag(self):
        argv = q.self_test_argv("/b/FixtureApp", "F6-reduced", "/e.jsonl")
        self.assertEqual(argv, ["/b/FixtureApp", "--fixture", "F6", "--events", "/e.jsonl",
                                "--reduced-motion-variant", "--self-test"])

    def test_original_f3_has_no_variant_flag(self):
        argv = q.self_test_argv("/b/FixtureApp", "F3", "/e.jsonl")
        self.assertNotIn("--f3-variant", argv)
        self.assertEqual(argv[-1], "--self-test")

    def test_variant_verdict_lines_parse_and_match_config(self):
        verdict = q.parse_verdict("SELFTEST F3 variant=lazy-1s: PASS (5/5)\n")
        self.assertEqual(verdict, ("F3-lazy-1s", "PASS", 5, 5))
        self.assertTrue(q.verdict_passes(verdict, "F3-lazy-1s"))
        self.assertFalse(q.verdict_passes(verdict, "F3-vstack-1s"))
        self.assertFalse(q.verdict_passes(verdict, "F3"))
        self.assertEqual(q.parse_verdict("SELFTEST F3: PASS (5/5)")[0], "F3")
        reduced = q.parse_verdict("SELFTEST F6-reduced: PASS (3/3)")
        self.assertTrue(q.verdict_passes(reduced, "F6-reduced"))
        self.assertFalse(q.verdict_passes(reduced, "F6"))

    def test_event_fixture_accepts_config_ids_only(self):
        record = {"ts": "2026-10-09T10:15:30.123Z", "stage": "mac-oracle", "event": "pass",
                  "fixture": "F3-vstack-3s", "artifact_ids": {}, "reason": "ok"}
        q.validate_event(record)
        record["fixture"] = "F3-list-0s"
        with self.assertRaises(ValueError):
            q.validate_event(record)

    def test_variant_oracle_run_passes_under_config_id(self):
        lines = trace_lines([("init", 1)])
        self.write_accepted(lines, fixture="F3-lazy-1s")
        ok = q.oracle_fixture("F3-lazy-1s", 1,
                              self.fake_launcher([(lines, "SELFTEST F3 variant=lazy-1s: PASS (5/5)")]),
                              self.binary, self.accepted, self.candidates, self.dir / "work", self.log)
        self.assertTrue(ok)
        self.assertFalse(list(self.candidates.glob("**/candidate.json")))

    def test_repeat_evidence_has_a_stem_for_every_config(self):
        if not q.REPEAT_DIR.exists():
            self.skipTest("repeat-run evidence not present on this host")
        for config in q.CONFIGS:
            self.assertTrue((q.REPEAT_DIR / f"{config}-run1.stdout").exists(), config)


if __name__ == "__main__":
    unittest.main()
