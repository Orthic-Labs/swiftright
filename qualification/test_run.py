"""Unit tests for qualification/run.py (no GUI, no Windows, no network).

Run: python3 -I -m unittest discover -s qualification -v
"""
import argparse
import hashlib
import json
import os
import re
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


def node_events(spec):
    """spec: list of (step, node_id, phase) -> normalized-looking lines."""
    return [json.dumps({"fixture": "F3", "kind": "lifecycle", "node_id": node, "payload": {"phase": phase},
                        "step": step}, sort_keys=True, separators=(",", ":")) for step, node, phase in spec]


class CanonicalV2Tests(unittest.TestCase):
    BASE = [("remove", "row4", "disappear"), ("remove", "row4", "task-cancel"),
            ("remove", "row5", "appear"), ("remove", "window", "layout"), ("reinsert", "row4", "appear")]

    def test_reversing_two_events_of_one_node_changes_digest(self):
        a = node_events(self.BASE)
        b = node_events([self.BASE[1], self.BASE[0], *self.BASE[2:]])  # onDisappear vs task-cancel reversed
        self.assertNotEqual(q.canonical_digest(a), q.canonical_digest(b))

    def test_reversing_non_adjacent_events_of_one_node_changes_digest(self):
        spec = [("s", "n1", "a"), ("s", "n2", "x"), ("s", "n1", "b")]
        swapped = [("s", "n1", "b"), ("s", "n2", "x"), ("s", "n1", "a")]
        self.assertNotEqual(q.canonical_digest(node_events(spec)), q.canonical_digest(node_events(swapped)))

    def test_swapping_events_of_different_nodes_keeps_digest(self):
        a = node_events(self.BASE)
        b = node_events([self.BASE[2], self.BASE[0], self.BASE[1], self.BASE[3], self.BASE[4]])
        self.assertEqual(q.canonical_digest(a), q.canonical_digest(b))
        interleaved = node_events([self.BASE[0], self.BASE[2], self.BASE[1], self.BASE[3], self.BASE[4]])
        self.assertEqual(q.canonical_digest(a), q.canonical_digest(interleaved))

    def test_moving_an_event_across_steps_changes_digest(self):
        a = node_events(self.BASE)
        b = node_events([*self.BASE[:3], ("reinsert", "window", "layout"), self.BASE[4]])
        self.assertNotEqual(q.canonical_digest(a), q.canonical_digest(b))

    def test_step_order_is_significant(self):
        a = node_events([("s1", "n", "a"), ("s2", "n", "b")])
        b = node_events([("s2", "n", "b"), ("s1", "n", "a")])
        self.assertNotEqual(q.canonical_digest(a), q.canonical_digest(b))

    def test_normalize_hash_script_matches_runner_and_applies_same_rule(self):
        script = QUAL.parent / "probes" / "sr0-o" / "fixtures" / "scripts" / "normalize-hash.py"
        import importlib.util
        spec = importlib.util.spec_from_file_location("normalize_hash", script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            def digest(lines, name):
                path = Path(tmp) / name
                path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                return module.canonical_digest(path)
            a = node_events(self.BASE)
            reversed_node = node_events([self.BASE[1], self.BASE[0], *self.BASE[2:]])
            different_nodes = node_events([self.BASE[2], self.BASE[0], self.BASE[1], self.BASE[3], self.BASE[4]])
            self.assertEqual(digest(a, "a"), q.canonical_digest(a))
            self.assertNotEqual(digest(a, "a"), digest(reversed_node, "b"))
            self.assertEqual(digest(a, "a"), digest(different_nodes, "c"))

    def test_accepted_manifest_with_old_canonical_form_is_refused(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            root = Path(tmp)
            fixture_dir = root / "F1"
            lines = trace_lines([("init", 1)])
            q.write_accepted(fixture_dir, lines, {})
            manifest = json.loads((fixture_dir / "manifest.json").read_text())
            del manifest["canonical_form"]
            (fixture_dir / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(q.AcceptedError):
                q.load_accepted(root, "F1")

    def test_repo_accepted_baselines_load_under_v2(self):
        for config in q.CONFIGS:
            loaded = q.load_accepted(q.ACCEPTED_ROOT, config)
            self.assertIsNotNone(loaded, config)
            self.assertEqual(loaded["manifest"]["canonical_form"], q.CANONICAL_FORM)


def run_args(*argv):
    return q.build_parser().parse_args(["run", *argv])


class StrictRunnerTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.log = q.EventLog(self.dir / "e.jsonl", echo=False)

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_default_mac_oracle_manifest_is_all_sixteen_configs(self):
        args = run_args()
        self.assertEqual(sorted(args.fixtures), sorted(q.CONFIGS))
        self.assertEqual(len(args.fixtures), 16)

    def test_default_stages_cover_smoke_and_package_in_declared_order(self):
        stages, error = q.run_stage_order(run_args())
        self.assertIsNone(error)
        self.assertEqual(stages, ["mac-oracle", "win-replay", "compare", "smoke", "package"])

    def test_stages_honour_the_given_order(self):
        stages, _ = q.run_stage_order(run_args("--stages", "package", "mac-oracle"))
        self.assertEqual(stages, ["package", "mac-oracle"])

    def test_compare_before_win_replay_is_a_usage_error(self):
        self.assertEqual(q.cmd_run(run_args("--stages", "compare", "win-replay", "--dry-run")), 2)
        self.assertIsNotNone(q.run_stage_order(run_args("--stages", "compare", "win-replay"))[1])
        self.assertIsNone(q.run_stage_order(run_args("--stages", "win-replay", "compare"))[1])

    def test_compare_without_any_windows_trace_fails(self):
        args = run_args("--stages", "compare")
        q.run_compare(self.log, args, ["compare"], self.dir, dry=False)
        self.assertEqual(self.log.failures, 1)

    def test_compare_after_replay_fails_when_replay_wrote_no_trace(self):
        args = run_args("--stages", "win-replay", "compare")
        q.run_compare(self.log, args, ["win-replay", "compare"], self.dir, dry=False)
        self.assertEqual(self.log.failures, 1)

    def test_dry_run_skips_exit_zero_but_real_skip_is_failure(self):
        self.assertEqual(q.cmd_run(run_args("--stages", "smoke", "package", "--dry-run")), 0)
        log = q.EventLog(self.dir / "s.jsonl", echo=False)
        log.emit("smoke", "skip", reason="x")
        self.assertEqual(log.skips, 1)
        log.close()

    def test_real_run_with_unconfirmed_windows_fails(self):
        self.assertEqual(q.cmd_run(run_args("--stages", "smoke")), 1)

    def test_run_exits_nonzero_when_a_stage_skips_or_has_no_pass(self):
        orig = q.package_stage
        q.package_stage = lambda log, paths, dry=False, tuple_pin=None: log.emit("package", "skip", reason="no")
        try:
            self.assertEqual(q.cmd_run(run_args("--stages", "package")), 1)
        finally:
            q.package_stage = orig


class WindowsEvidenceTests(unittest.TestCase):
    EXE, RND, TRC = "a" * 64, "b" * 64, "c" * 64

    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.log = q.EventLog(self.dir / "e.jsonl", echo=False)

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def artifacts_line(self, trace=None):
        return f"ARTIFACTS exe={self.EXE} renderer={self.RND} trace={trace or self.TRC}\n"

    def events(self):
        return [json.loads(l) for l in (self.dir / "e.jsonl").read_text().splitlines() if l.strip()]

    def record(self, **overrides):
        base = {"ts": "2026-10-09T10:15:30.123Z", "stage": "win-replay", "event": "pass", "fixture": None,
                "artifact_ids": {}, "reason": "ok"}
        base.update(overrides)
        return base

    def test_windows_pass_record_requires_artifact_ids(self):
        for stage in ("win-replay", "smoke"):
            with self.assertRaises(ValueError):
                q.validate_event(self.record(stage=stage))
            with self.assertRaises(ValueError):
                q.validate_event(self.record(stage=stage, artifact_ids={"windows_exe": "sha256:" + "a" * 64}))
            ids = {k: "sha256:" + "a" * 64 for k in q.WINDOWS_PASS_IDS}
            q.validate_event(self.record(stage=stage, artifact_ids=ids))
        q.validate_event(self.record(stage="win-replay", event="fail", reason="x"))

    def fake_win(self, matrix_lines, write_evidence=True, trace=None):
        out_dir = self.dir

        def runner(command, env=None, capture_output=True, text=True):
            if write_evidence:
                for l in matrix_lines:
                    fixture, variant, run = l.split()[0], l.split()[1], l.split()[2]
                    (out_dir / "win-matrix" / f"{fixture}-{variant}-r{run[3:]}.txt").write_text(
                        "SELFTEST PASS\n" + self.artifacts_line(trace), encoding="utf-8")
            return argparse.Namespace(returncode=0, stdout="\n".join(l + ": SELFTEST F1: PASS" for l in matrix_lines),
                                      stderr="")
        return runner

    def test_win_replay_passes_with_artifact_ids(self):
        runner = self.fake_win(["F1 none run1"])
        ok = q.win_stage(self.log, ["F1:none"], 1, self.dir, False, True, runner=runner, which=lambda n: "/bin/win")
        self.assertTrue(ok)
        final = self.events()[-1]
        self.assertEqual(final["event"], "pass")
        self.assertEqual(final["artifact_ids"]["windows_exe"], "sha256:" + self.EXE)
        self.assertEqual(final["artifact_ids"]["windows_renderer"], "sha256:" + self.RND)
        self.assertEqual(final["artifact_ids"]["windows_trace"], "sha256:" + q.sha256_text(self.TRC))

    def test_win_replay_pass_without_artifact_evidence_fails(self):
        runner = self.fake_win(["F1 none run1"], write_evidence=False)
        ok = q.win_stage(self.log, ["F1:none"], 1, self.dir, False, True, runner=runner, which=lambda n: "/bin/win")
        self.assertFalse(ok)
        self.assertIn("ARTIFACTS", self.events()[-1]["reason"])
        self.assertEqual(self.log.passes.get("win-replay"), None)

    def test_win_replay_refuses_mixed_builds(self):
        with self.assertRaises(ValueError):
            q.windows_ids(["a" * 64, "d" * 64], ["b" * 64, "b" * 64], ["c" * 64] * 2)

    def smoke_runner(self, normal, timeout=None, rc=0):
        """Returns the normal text for the plain dispatch and the timeout text for the -SkipShutdown one."""
        timeout = normal if timeout is None else timeout
        return lambda command, capture_output=True, text_=True, **kw: argparse.Namespace(
            returncode=rc, stdout=timeout if "-SkipShutdown" in command[1] else normal, stderr="")

    def smoke_text(self, mode="normal", n=40, verdict=None):
        marker = q.SMOKE_MODE_MARKERS[mode]
        return (f"AUTOMATIONID PASS\nrun: ok\n{marker} [x]\n" + (verdict or f"SMOKE PASS ({n}/{n})") + "\n"
                + self.artifacts_line())

    def test_smoke_dry_run_prints_plan_and_skips(self):
        self.assertTrue(q.smoke_stage(self.log, self.dir, True, False))
        self.assertEqual(self.log.skips, 1)
        plan = q.smoke_plan("t1")
        self.assertEqual(plan["command"][0], "win")
        self.assertIn("schedule-smoke.ps1", plan["command"][1])
        self.assertIn("-Tag t1", plan["command"][1])
        self.assertNotIn("-SkipShutdown", plan["command"][1])

    def test_smoke_timeout_plan_adds_skip_shutdown(self):
        plan = q.smoke_plan("t1", timeout=True)
        self.assertTrue(plan["command"][1].endswith("-Tag t1 -SkipShutdown"))
        self.assertEqual(plan["mode"], "timeout")
        self.assertIn(q.SMOKE_MODE_MARKERS["timeout"], plan["pass_markers"])

    def test_smoke_refuses_without_confirmation(self):
        self.assertFalse(q.smoke_stage(self.log, self.dir, False, False))
        self.assertEqual(self.log.failures, 1)

    def run_smoke(self, runner, tuple_pin=None):
        log = q.EventLog(self.dir / "x.jsonl", echo=False)
        ok = q.smoke_stage(log, self.dir, False, True, runner=runner, which=lambda n: "w", tuple_pin=tuple_pin)
        log.close()
        return ok, [json.loads(l) for l in (self.dir / "x.jsonl").read_text().splitlines() if l.strip()]

    def test_smoke_runs_normal_then_timeout_and_both_must_pass(self):
        runner = self.smoke_runner(self.smoke_text("normal", 40), self.smoke_text("timeout", 41))
        ok, events = self.run_smoke(runner)
        self.assertTrue(ok)
        self.assertEqual(events[-1]["artifact_ids"]["windows_exe"], "sha256:" + self.EXE)
        self.assertIn("normal 40/40, timeout 41/41", events[-1]["reason"])
        self.assertTrue((self.dir / "smoke-normal.txt").exists() and (self.dir / "smoke-timeout.txt").exists())

    def test_smoke_fails_when_one_mode_is_missing_its_evidence(self):
        good_n, good_t = self.smoke_text("normal", 40), self.smoke_text("timeout", 41)
        cases = {
            "no AUTOMATIONID": (good_n.replace("AUTOMATIONID PASS", "AUTOMATIONID FAIL"), good_t, "normal"),
            "no ARTIFACTS": (good_n.split("ARTIFACTS")[0], good_t, "normal"),
            "timeout mode ran the normal dispatch": (good_n, self.smoke_text("normal", 41), "timeout"),
            "timeout verdict fails": (good_n, self.smoke_text("timeout", verdict="SMOKE FAIL (40/41)"), "timeout"),
            "partial pass": (good_n, self.smoke_text("timeout", verdict="SMOKE PASS (40/41)"), "timeout"),
        }
        for name, (normal, timeout, mode) in cases.items():
            with self.subTest(name):
                ok, events = self.run_smoke(self.smoke_runner(normal, timeout))
                self.assertFalse(ok)
                self.assertIn(mode, events[-1]["reason"])
                self.assertEqual(events[-1]["event"], "fail")

    def test_smoke_refuses_mixed_builds_between_modes(self):
        other = self.smoke_text("timeout", 41).replace(self.EXE, "d" * 64)
        ok, events = self.run_smoke(self.smoke_runner(self.smoke_text("normal", 40), other))
        self.assertFalse(ok)
        self.assertIn("exe", events[-1]["reason"])


def sha_ref_of(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


RUN_ID = "20261009T100000Z"
HARNESS_SHA = sha_ref_of(b"harness")


def check_record(platform, check_id, implemented=True, status="pass", run_id=RUN_ID):
    if status == "pass":
        reason = None
    elif implemented:
        reason = "observed mismatch"
    else:
        reason = f"not-implemented: {check_id}"
    return {
        "schema": q.PACKAGE_RECEIPT_SCHEMA, "record": "check", "product": "SliceApp", "platform": platform,
        "run_id": run_id, "check_id": check_id, "check_name": f"{check_id} check", "implemented": implemented,
        "status": status, "reason": reason, "started_utc": "2026-10-09T10:00:00Z",
        "ended_utc": "2026-10-09T10:00:05Z", "exit_status": None,
        "observations": {"window_visible": "true", "rc": 0},
        "artifact_ids": {"installer": sha_ref_of(b"installer")},
        "environment": {"host": "host-a", "os_version": "test 1", "user": "tester"},
        "harness": {"name": "harness", "sha256": HARNESS_SHA},
    }


def run_record(platform, checks, run_id=RUN_ID, expected=None, artifact_ids=None):
    """expected: the run's profile (default: every declared check of the platform)."""
    not_ok = [c["check_id"] for c in checks if c["status"] != "pass" or not c["implemented"]]
    return {
        "schema": q.PACKAGE_RECEIPT_SCHEMA, "record": "run", "product": "SliceApp", "platform": platform,
        "run_id": run_id, "status": "fail" if not_ok else "pass",
        "expected_checks": list(expected if expected is not None else q.PACKAGE_CHECKS[platform]),
        "checks": [{"check_id": c["check_id"], "status": c["status"], "implemented": c["implemented"]} for c in checks],
        "started_utc": "2026-10-09T10:00:00Z", "ended_utc": "2026-10-09T10:01:00Z",
        "reason": f"checks not passing: {', '.join(not_ok)}" if not_ok else None,
        "artifact_ids": artifact_ids or {"old_dmg": sha_ref_of(b"old"), "new_dmg": sha_ref_of(b"new")},
        "harness": {"name": "harness", "sha256": HARNESS_SHA},
    }


def passing_checks(platform):
    return [check_record(platform, cid) for cid in q.PACKAGE_CHECKS[platform]]


def harness_output(platform, unimplemented=()):
    """Checks as a harness emits them: an unimplemented check is recorded as fail with implemented false."""
    return [check_record(platform, cid, implemented=cid not in unimplemented, status="pass" if cid not in unimplemented else "fail")
            for cid in q.PACKAGE_CHECKS[platform]]


WIN_UNIMPLEMENTED = ("W08-interrupted-update", "W11-legacy-data-physical-path")
MAC_UNIMPLEMENTED = ("M08-interrupted-install", "M11-window-visible")


class PackageStageTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.root = self.dir / "receipts"
        self.log = q.EventLog(self.dir / "e.jsonl", echo=False)

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def write_run(self, name, checks, run=None, platform=None):
        """Writes <root>/<name>/<check_id>.json for each check and run.json (default: derived from the checks)."""
        target = self.root / name
        target.mkdir(parents=True, exist_ok=True)
        for c in checks:
            (target / f"{c['check_id']}.json").write_text(json.dumps(c), encoding="utf-8")
        if run is None:
            run = run_record(platform or checks[0]["platform"], checks)
        (target / "run.json").write_text(json.dumps(run), encoding="utf-8")

    def stage(self):
        return q.package_stage(self.log, [self.root])

    def events(self):
        return [json.loads(line) for line in (self.dir / "e.jsonl").read_text().splitlines() if line.strip()]

    def fail_reasons(self):
        return [e["reason"] or "" for e in self.events() if e["event"] == "fail"]

    def test_passing_set_covers_both_platforms(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertTrue(self.stage())
        self.assertEqual(self.log.passes["package"], 4)  # two runs, two platform unions
        self.assertEqual(self.log.failures, 0)

    def test_unimplemented_checks_fail_their_platform(self):
        self.write_run("windows", harness_output("windows-x64", WIN_UNIMPLEMENTED))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        reasons = " ".join(self.fail_reasons())
        self.assertIn("W08-interrupted-update", reasons)
        self.assertIn("W11-legacy-data-physical-path", reasons)
        self.assertIn("must be implemented and pass", reasons)

    def test_mac_unimplemented_checks_fail_the_mac_run(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.write_run("mac", harness_output("macos-arm64", MAC_UNIMPLEMENTED))
        self.assertFalse(self.stage())
        self.assertIn("M11-window-visible", " ".join(self.fail_reasons()))

    def test_pass_on_unimplemented_check_is_rejected_even_when_run_claims_pass(self):
        checks = passing_checks("windows-x64")
        checks[8] = check_record("windows-x64", "W08-interrupted-update", implemented=False, status="pass")
        run = run_record("windows-x64", checks)
        run["status"], run["reason"] = "pass", None
        run["checks"][8]["status"] = "pass"
        self.write_run("windows", checks, run=run)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W08-interrupted-update", " ".join(self.fail_reasons()))

    def test_missing_platform_fails(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.assertFalse(self.stage())
        self.assertIn("macos-arm64", self.events()[-1]["reason"])

    def test_missing_check_record_fails(self):
        checks = passing_checks("windows-x64")
        self.write_run("windows", checks[:-1], run=run_record("windows-x64", checks))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn(f"{checks[-1]['check_id']}: check record missing", " ".join(self.fail_reasons()))

    def test_run_summary_and_check_file_must_agree(self):
        checks = passing_checks("windows-x64")
        stale = [dict(c) for c in checks]
        stale[5] = check_record("windows-x64", "W05-write-data", implemented=True, status="fail")
        self.write_run("windows", stale, run=run_record("windows-x64", checks))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W05-write-data", " ".join(self.fail_reasons()))

    def test_harness_dropping_a_declared_check_fails(self):
        checks = passing_checks("windows-x64")[:-1]
        run = run_record("windows-x64", checks)
        run["expected_checks"] = list(q.PACKAGE_CHECKS["windows-x64"][:-1])
        self.write_run("windows", checks, run=run)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W14-deferred-update-in-use: no run record covers it", " ".join(self.fail_reasons()))

    def test_undeclared_check_record_fails(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.write_run("mac", passing_checks("macos-arm64"))
        (self.root / "windows" / "W12-extra.json").write_text(json.dumps(check_record("windows-x64", "W00-environment")))
        self.assertFalse(self.stage())
        self.assertIn("undeclared check records: W12-extra.json", " ".join(self.fail_reasons()))

    def test_previous_schema_version_is_rejected(self):
        checks = passing_checks("windows-x64")
        run = run_record("windows-x64", checks)
        run["schema"] = "sr0-a.package-receipt/v1"
        self.write_run("windows", checks, run=run)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("schema is 'sr0-a.package-receipt/v1'", " ".join(self.fail_reasons()))

    def test_directory_without_run_record_is_not_a_run(self):
        (self.root / "orphan").mkdir(parents=True)
        (self.root / "orphan" / "W00-environment.json").write_text("{}")
        self.assertFalse(self.stage())
        self.assertEqual(self.log.failures, 1)
        self.assertIn("no package run records", self.events()[-1]["reason"])

    def test_malformed_run_record_fails(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.write_run("mac", passing_checks("macos-arm64"))
        (self.root / "mac" / "run.json").write_text("{nope")
        self.assertFalse(self.stage())
        self.assertIn("run.json unreadable", " ".join(self.fail_reasons()))

    def test_package_dry_run_skips(self):
        self.assertTrue(q.package_stage(self.log, [self.root], dry_run=True))
        self.assertEqual(self.log.skips, 1)

    def test_check_record_rules(self):
        cid = "W00-environment"
        self.assertEqual(q.validate_check_record(check_record("windows-x64", cid), "windows-x64", RUN_ID, cid), [])
        cases = {
            "pass without implemented": check_record("windows-x64", cid, implemented=False, status="pass"),
            "pass with reason": {**check_record("windows-x64", cid), "reason": "x"},
            "fail without reason": {**check_record("windows-x64", cid, status="fail"), "reason": None},
            "sha without prefix": {**check_record("windows-x64", cid), "artifact_ids": {"installer": "ab" * 32}},
            "bad artifact name": {**check_record("windows-x64", cid), "artifact_ids": {"Bad-Name": sha_ref_of(b"x")}},
            "wrong platform": check_record("macos-arm64", cid),
            "wrong run id": check_record("windows-x64", cid, run_id="other"),
            "wrong file name": check_record("windows-x64", "W01-artifacts-bound"),
            "v1 schema": {**check_record("windows-x64", cid), "schema": "sr0-a.package-receipt/v1"},
            "extra key": {**check_record("windows-x64", cid), "stage": "package"},
            "bad timestamp": {**check_record("windows-x64", cid), "started_utc": "2026-10-09 10:00"},
            "observation not scalar": {**check_record("windows-x64", cid), "observations": {"a": [1]}},
        }
        for name, rec in cases.items():
            with self.subTest(name):
                self.assertTrue(q.validate_check_record(rec, "windows-x64", RUN_ID, cid), name)

    def test_run_record_rules(self):
        checks = passing_checks("windows-x64")
        self.assertEqual(q.validate_run_record(run_record("windows-x64", checks))[0], [])
        bad_pass = run_record("windows-x64", harness_output("windows-x64", WIN_UNIMPLEMENTED))
        bad_pass["status"], bad_pass["reason"] = "pass", None
        self.assertTrue(q.validate_run_record(bad_pass)[0])
        problems, platform = q.validate_run_record({**run_record("windows-x64", checks), "platform": "linux-x64"})
        self.assertIsNone(platform)
        self.assertTrue(problems)


    # ---- profiles: several run records of one platform are evaluated as a union (R5 Offline + Network)
    WIN_OFFLINE = tuple(c for c in q.PACKAGE_CHECKS["windows-x64"] if c != "W12-appinstaller-update")
    WIN_NETWORK = ("W00-environment", "W01-artifacts-bound", "W12-appinstaller-update")
    MAC_AUTOMATED = tuple(c for c in q.PACKAGE_CHECKS["macos-arm64"] if c != "M11-window-visible")
    MSIX = {"old_msix": sha_ref_of(b"old-msix"), "new_msix": sha_ref_of(b"new-msix")}

    def profile(self, name, platform, ids, fail=(), artifact_ids=None, mutate=None, run_id=None):
        """Writes one profile run directory covering exactly ids; checks in fail are implemented fail records."""
        run_id = run_id or name
        checks = [check_record(platform, cid, status="fail" if cid in fail else "pass", run_id=run_id) for cid in ids]
        if mutate:
            for c in checks:
                mutate(c)
        run = run_record(platform, checks, run_id=run_id, expected=ids, artifact_ids=artifact_ids or dict(self.MSIX))
        self.write_run(name, checks, run=run)

    def test_r5_profiles_union_passes_when_every_check_passes(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.profile("network", "windows-x64", self.WIN_NETWORK)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertTrue(self.stage())
        self.assertEqual(self.log.failures, 0)
        union = [e for e in self.events() if e["event"] == "pass" and "15/15 declared checks" in (e["reason"] or "")]
        self.assertEqual(len(union), 1)
        self.assertIn("(network, offline)", union[0]["reason"])  # run directories sort by name

    def test_r5_shape_with_w08_fail_fails_only_on_w08(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE, fail=("W08-interrupted-update",))
        self.profile("network", "windows-x64", self.WIN_NETWORK)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        unions = [e for e in self.events() if e["event"] == "fail" and "union of" in (e["reason"] or "")]
        self.assertEqual(len(unions), 1)
        self.assertIn("W08-interrupted-update: no implemented passing record (offline: fail)", unions[0]["reason"])
        self.assertEqual(unions[0]["reason"].count("W0") + unions[0]["reason"].count("W1"), 1, "no other check is named")
        self.assertEqual(self.log.passes["package"], 3, "network run, mac run and the mac union still pass")

    def test_a_check_no_profile_covers_fails(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W12-appinstaller-update: no run record covers it", " ".join(self.fail_reasons()))

    def test_a_check_recorded_in_two_profiles_must_agree(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.profile("network", "windows-x64", self.WIN_NETWORK, fail=("W00-environment",))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W00-environment: different results in network, offline", " ".join(self.fail_reasons()))

    def test_duplicate_check_with_different_artifact_ids_is_a_conflict(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.profile("network", "windows-x64", self.WIN_NETWORK,
                     mutate=lambda c: c.update(artifact_ids={"installer": sha_ref_of(b"other")})
                     if c["check_id"] == "W01-artifacts-bound" else None)
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("W01-artifacts-bound: different results", " ".join(self.fail_reasons()))

    def test_profiles_must_carry_one_artifact_identity(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.profile("network", "windows-x64", self.WIN_NETWORK,
                     artifact_ids={**self.MSIX, "new_msix": sha_ref_of(b"a different build")})
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(self.stage())
        self.assertIn("artifact identity differs between network and offline: new_msix", " ".join(self.fail_reasons()))

    def test_expected_checks_must_be_an_ordered_subset_of_the_declared_checks(self):
        for name, ids in {"reversed": self.WIN_NETWORK[::-1], "unknown": ("W00-environment", "W99-extra"),
                          "duplicate": ("W00-environment", "W00-environment")}.items():
            with self.subTest(name):
                run = run_record("windows-x64", [], expected=ids)
                problems, platform = q.validate_run_record(run)
                self.assertEqual(platform, "windows-x64")
                self.assertTrue(any("expected_checks must be a non-empty subset" in p for p in problems), problems)
        empty = run_record("windows-x64", [], expected=())
        self.assertTrue(q.validate_run_record(empty)[0])

    def test_check_record_outside_a_profile_is_refused(self):
        self.profile("offline", "windows-x64", self.WIN_OFFLINE)
        self.profile("network", "windows-x64", self.WIN_NETWORK)
        self.write_run("mac", passing_checks("macos-arm64"))
        (self.root / "offline" / "W12-appinstaller-update.json").write_text(
            json.dumps(check_record("windows-x64", "W12-appinstaller-update", run_id="offline")))
        self.assertFalse(self.stage())
        self.assertIn("check records outside expected_checks: W12-appinstaller-update.json", " ".join(self.fail_reasons()))

    # ---- manual observation (M11 only)
    def manual_m11(self, **overrides):
        def mark(c):
            c["observations"] = {"manual": "true", "observer": "adrian", "note": "window visible after first launch"}
            c["artifact_ids"] = {"evidence": sha_ref_of(b"M11-window-visible.png")}
            c.update(overrides)
        return mark

    def test_mac_union_of_automated_profile_and_manual_m11_passes(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.profile("mac-auto", "macos-arm64", self.MAC_AUTOMATED, artifact_ids={"old_dmg": sha_ref_of(b"o")})
        self.profile("mac-manual", "macos-arm64", ("M11-window-visible",), artifact_ids={"old_dmg": sha_ref_of(b"o")},
                     mutate=self.manual_m11())
        self.assertTrue(self.stage())
        self.assertIn("macos-arm64: 12/12 declared checks", " ".join(e["reason"] or "" for e in self.events()))

    def test_manual_observation_needs_observer_and_evidence_and_only_m11(self):
        cases = {
            "no observer": ("macos-arm64", "M11-window-visible", lambda c: c["observations"].pop("observer")),
            "no evidence": ("macos-arm64", "M11-window-visible", lambda c: c.update(artifact_ids={})),
            "other check": ("macos-arm64", "M05-offline-first-launch", None),
            "windows check": ("windows-x64", "W04-launch-offline-old", None),
        }
        for name, (platform, cid, tweak) in cases.items():
            with self.subTest(name):
                rec = check_record(platform, cid)
                self.manual_m11()(rec)
                if tweak:
                    tweak(rec)
                self.assertTrue(q.manual_problems(rec), name)
        good = check_record("macos-arm64", "M11-window-visible")
        self.manual_m11()(good)
        self.assertEqual(q.manual_problems(good), [])
        self.assertEqual(q.manual_problems(check_record("macos-arm64", "M11-window-visible")), [], "automated pass is fine")

    def test_manual_claim_on_a_non_manual_check_fails_the_run(self):
        self.write_run("windows", passing_checks("windows-x64"))
        self.profile("mac", "macos-arm64", q.PACKAGE_CHECKS["macos-arm64"],
                     mutate=lambda c: self.manual_m11()(c) if c["check_id"] == "M05-offline-first-launch" else None)
        self.assertFalse(self.stage())
        self.assertIn("a manual observation is only allowed for M11-window-visible", " ".join(self.fail_reasons()))

    # ---- tuple pins on package hashes
    def pinned(self, **pins):
        pin = q.load_tuple(q.TUPLE_FINAL)
        pin["pins"] = {**pin["pins"], **pins}
        return pin

    def test_package_artifact_hashes_must_equal_the_tuple(self):
        final = q.load_tuple(q.TUPLE_FINAL)["pins"]
        ids = {"old_msix": "sha256:" + final["old_msix"], "new_msix": "sha256:" + final["new_msix"]}
        self.profile("offline", "windows-x64", self.WIN_OFFLINE, artifact_ids=ids)
        self.profile("network", "windows-x64", self.WIN_NETWORK, artifact_ids=ids)
        self.write_run("mac", passing_checks("macos-arm64"), run=run_record(
            "macos-arm64", passing_checks("macos-arm64"), artifact_ids={"old_dmg": "sha256:" + final["old_dmg"]}))
        self.assertTrue(q.package_stage(self.log, [self.root], tuple_pin=q.load_tuple(q.TUPLE_FINAL)))
        self.assertIn("tuple_file", [e for e in self.events() if "union" in (e["reason"] or "") or "declared checks" in (e["reason"] or "")][-1]["artifact_ids"])

    def test_package_with_a_hash_that_is_not_the_tuples_fails(self):
        self.write_run("windows", passing_checks("windows-x64"), run=run_record(
            "windows-x64", passing_checks("windows-x64"), artifact_ids=dict(self.MSIX)))
        self.write_run("mac", passing_checks("macos-arm64"))
        self.assertFalse(q.package_stage(self.log, [self.root], tuple_pin=q.load_tuple(q.TUPLE_FINAL)))
        reasons = " ".join(self.fail_reasons())
        self.assertIn("old_msix", reasons)
        self.assertIn("differs from tuple final", reasons)

    def test_a_pending_tuple_member_fails_a_record_that_carries_it(self):
        final = q.load_tuple(q.TUPLE_FINAL)["pins"]
        self.assertIsNotNone(final["new_dmg"], "the 0.1.1 DMG on the final chain is pinned")
        pending = self.pinned(new_dmg=None)  # the tuple as it was before the 0.1.1 DMG was built
        self.write_run("windows", passing_checks("windows-x64"), run=run_record(
            "windows-x64", passing_checks("windows-x64"),
            artifact_ids={"old_msix": "sha256:" + final["old_msix"], "new_msix": "sha256:" + final["new_msix"]}))
        self.write_run("mac", passing_checks("macos-arm64"), run=run_record(
            "macos-arm64", passing_checks("macos-arm64"),
            artifact_ids={"old_dmg": "sha256:" + final["old_dmg"], "new_dmg": sha_ref_of(b"0.1.1 dmg")}))
        self.assertFalse(q.package_stage(self.log, [self.root], tuple_pin=pending))
        self.assertIn("new_dmg is not pinned in tuple final (PENDING)", " ".join(self.fail_reasons()))



def fake_tuple(**pins):
    """A tuple dict as load_tuple returns it (every member pending unless given)."""
    return {"name": "t", "path": "t.json", "sha256": "e" * 64, "smoke_checks": {"normal": 40, "timeout": 41},
            "pins": {**{m: None for m in q.TUPLE_MEMBERS}, **pins}}


class TupleFileTests(unittest.TestCase):
    def test_final_tuple_loads_with_every_member(self):
        pin = q.load_tuple(q.TUPLE_FINAL)
        self.assertEqual(set(pin["pins"]), set(q.TUPLE_MEMBERS))
        self.assertEqual(pin["smoke_checks"], {"normal": 40, "timeout": 41})
        self.assertTrue(pin["pins"]["windows_renderer"].startswith("e280f4a9"))
        self.assertTrue(pin["pins"]["windows_fixture_exe"].startswith("7673a2d5"))
        self.assertTrue(pin["pins"]["windows_smoke_exe"].startswith("21992f16"))
        self.assertTrue(pin["pins"]["old_dmg"].startswith("b976ac70"))
        self.assertTrue(pin["pins"]["new_dmg"].startswith("75f3cd75"))
        self.assertNotEqual(pin["pins"]["new_dmg"], pin["pins"]["old_dmg"])

    def test_every_pinned_hash_is_on_every_cited_line(self):
        doc = json.loads(q.TUPLE_FINAL.read_text(encoding="utf-8"))
        checked = 0
        for name, member in doc["members"].items():
            self.assertEqual(bool(member["source"]), member["sha256"] is not None, name)
            for cite in member["source"]:
                path, _, line = cite.rpartition(":")
                text = (q.REPO / path).read_text(encoding="utf-8", errors="replace").splitlines()[int(line) - 1]
                self.assertIn(member["sha256"], text.lower(), f"{name} not on {cite}")
                checked += 1
        self.assertGreaterEqual(checked, 15)
        for mode, cite in zip(q.SMOKE_MODES, doc["smoke_checks"]["source"]):
            path, _, line = cite.rpartition(":")
            n = doc["smoke_checks"][mode]
            self.assertIn(f"SMOKE PASS ({n}/{n})", (q.REPO / path).read_text().splitlines()[int(line) - 1])

    def test_matrix_script_defaults_are_the_tuple(self):
        text = (q.MATRIX_SCRIPT).read_text(encoding="utf-8")
        pins = q.load_tuple(q.TUPLE_FINAL)["pins"]
        exe = re.search(r"EXPECT_EXE_SHA256:=([0-9A-F]{64})", text).group(1).lower()
        dll = re.search(r"EXPECT_DLL_SHA256:=([0-9A-F]{64})", text).group(1).lower()
        self.assertEqual((exe, dll), (pins["windows_fixture_exe"], pins["windows_renderer"]))

    def test_pin_problems(self):
        pin = fake_tuple(windows_renderer="a" * 64)
        self.assertEqual(q.pin_problems(None, {"windows_renderer": "b" * 64}), [])
        self.assertEqual(q.pin_problems(pin, {"windows_renderer": "a" * 64}), [])
        self.assertIn("differs from tuple t", q.pin_problems(pin, {"windows_renderer": "b" * 64})[0])
        self.assertIn("(PENDING)", q.pin_problems(pin, {"new_dmg": "c" * 64})[0])

    def test_bad_tuple_files_are_refused(self):
        good = json.loads(q.TUPLE_FINAL.read_text(encoding="utf-8"))
        cases = {"schema": {**good, "schema": "x"},
                 "member set": {**good, "members": {k: v for k, v in good["members"].items() if k != "old_dmg"}},
                 "upper-case hash": {**good, "members": {**good["members"], "old_dmg": {"sha256": "AB" * 32}}},
                 "short hash": {**good, "members": {**good["members"], "old_dmg": {"sha256": "ab"}}},
                 "smoke count": {**good, "smoke_checks": {"normal": 40}}}
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            for name, doc in cases.items():
                with self.subTest(name):
                    path = Path(tmp) / f"{name}.json"
                    path.write_text(json.dumps(doc))
                    with self.assertRaises(q.TupleError):
                        q.load_tuple(path)
            with self.assertRaises(q.TupleError):
                q.load_tuple(Path(tmp) / "missing.json")


class SmokeTupleTests(unittest.TestCase):
    """Committed smoke receipts through smoke_stage (injected runner; nothing is dispatched)."""
    BS = q.REPO / "examples" / "BridgeSmoke"

    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def replay(self, normal, timeout, tuple_pin):
        texts = {False: (self.BS / normal).read_text(encoding="utf-8", errors="replace"),
                 True: (self.BS / timeout).read_text(encoding="utf-8", errors="replace")}
        runner = lambda command, **kw: argparse.Namespace(returncode=0, stdout=texts["-SkipShutdown" in command[1]], stderr="")
        log = q.EventLog(self.dir / "e.jsonl", echo=False)
        ok = q.smoke_stage(log, self.dir, False, True, runner=runner, which=lambda n: "w", tuple_pin=tuple_pin)
        log.close()
        return ok, [json.loads(l) for l in (self.dir / "e.jsonl").read_text().splitlines() if l.strip()][-1]

    def test_final_receipts_pass_under_the_final_tuple(self):
        ok, last = self.replay("result-smoke-rev08.txt", "result-smoke-timeout08.txt", q.load_tuple(q.TUPLE_FINAL))
        self.assertTrue(ok, last)
        self.assertIn("normal 40/40, timeout 41/41", last["reason"])
        self.assertEqual(last["artifact_ids"]["windows_exe"], "sha256:" + q.load_tuple(q.TUPLE_FINAL)["pins"]["windows_smoke_exe"])
        self.assertIn("tuple_file", last["artifact_ids"])

    def test_negative_control_old_rev06c_receipt_fails_the_tuple(self):
        ok, last = self.replay("result-smoke-rev06c.txt", "result-smoke-timeout06c.txt", q.load_tuple(q.TUPLE_FINAL))
        self.assertFalse(ok)
        self.assertEqual(last["event"], "fail")
        self.assertIn("777f14c4", last["reason"])
        self.assertIn("differs from tuple final", last["reason"])

    def test_the_same_old_receipt_passes_when_unpinned(self):
        ok, last = self.replay("result-smoke-rev06c.txt", "result-smoke-timeout06c.txt", None)
        self.assertTrue(ok, "only the tuple rejects the old build")
        self.assertIn("(unpinned)", last["reason"])

    def test_a_tuple_count_other_than_the_receipts_fails(self):
        pin = q.load_tuple(q.TUPLE_FINAL)
        pin["smoke_checks"] = {"normal": 41, "timeout": 41}
        ok, last = self.replay("result-smoke-rev08.txt", "result-smoke-timeout08.txt", pin)
        self.assertFalse(ok)
        self.assertIn("tuple expects 41/41", last["reason"])


class WinReplayTupleTests(unittest.TestCase):
    EXE, RND = "a" * 64, "b" * 64
    MATRIX = q.REPO / "probes" / "sr0-s" / "fresh-on-bridge" / "out" / "matrix-08"

    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.log = q.EventLog(self.dir / "e.jsonl", echo=False)
        self.calls = []

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def events(self):
        return [json.loads(l) for l in (self.dir / "e.jsonl").read_text().splitlines() if l.strip()]

    def artifacts(self, exe=None):
        return f"ARTIFACTS exe={exe or self.EXE} renderer={self.RND} trace={'c' * 64}\n"

    def windows(self, verify="ARTIFACT_OK\n", record="state=Ready last_result=0\nrecorder exit=0\n", pull_ok=True, exe=None):
        """Fake `win`/matrix transport for win_stage with the F1 trace step."""
        def runner(command, env=None, capture_output=True, text=True):
            self.calls.append(command)
            if command[0] == "bash":
                for cfg in command[2:]:
                    f, _, v = cfg.partition(":")
                    (Path(env["OUT_DIR"]) / f"{f}-{v}-r1.txt").write_text("SELFTEST PASS\n" + self.artifacts(exe), encoding="utf-8")
                lines = [f"{c.partition(':')[0]} {c.partition(':')[2]} run1: SELFTEST F1: PASS" for c in command[2:]]
                return argparse.Namespace(returncode=0, stdout="\n".join(lines), stderr="")
            if "verify-artifacts.ps1" in command[1]:
                return argparse.Namespace(returncode=0, stdout=verify, stderr="")
            if "schedule-f1.ps1" in command[1]:
                return argparse.Namespace(returncode=0, stdout=record, stderr="")
            if "cat.ps1" in command[1]:
                return argparse.Namespace(returncode=0 if pull_ok else 1, stdout="\x1b[0m{}\n" if pull_ok else "", stderr="")
            raise AssertionError(command)
        return runner

    def assembler(self, rc=0):
        def assemble(argv):
            self.calls.append(argv)
            if rc == 0:
                Path(argv[argv.index("--out") + 1]).write_text('{"fixtureId": "F1"}', encoding="utf-8")
            return rc, "wrote" if rc == 0 else "boom"
        return assemble

    def stage(self, runner, tuple_pin=None, f1=False, assembler=None):
        recorder = lambda out_dir, exe, renderer, runner=None: q.win_f1_trace(
            out_dir, exe, renderer, runner=runner, assembler=assembler or self.assembler())
        return q.win_stage(self.log, ["F1:none"], 1, self.dir, False, True, runner=runner, which=lambda n: "w",
                           tuple_pin=tuple_pin, f1_trace=f1, f1_recorder=recorder)

    # ---- D5: tuple pins
    def test_unpinned_replay_passes_and_says_so(self):
        self.assertTrue(self.stage(self.windows()))
        self.assertIn("(unpinned)", self.events()[-1]["reason"])

    def test_replay_on_the_tuple_build_passes(self):
        pin = fake_tuple(windows_fixture_exe=self.EXE, windows_renderer=self.RND)
        self.assertTrue(self.stage(self.windows(), tuple_pin=pin))
        self.assertIn("tuple_file", self.events()[-1]["artifact_ids"])

    def test_replay_on_another_exe_or_renderer_fails(self):
        for name, pin in {"exe": fake_tuple(windows_fixture_exe="d" * 64, windows_renderer=self.RND),
                          "renderer": fake_tuple(windows_fixture_exe=self.EXE, windows_renderer="d" * 64),
                          "pending": fake_tuple(windows_renderer=self.RND)}.items():
            with self.subTest(name):
                self.log.close()
                self.log = q.EventLog(self.dir / "e.jsonl", echo=False)
                self.assertFalse(self.stage(self.windows(), tuple_pin=pin))
                self.assertIn("not the tuple build", self.events()[-1]["reason"])

    def test_committed_matrix_final_passes_the_final_tuple_and_fails_a_wrong_pin(self):
        records = sorted(self.MATRIX.glob("F*-r*.txt"))
        records = [r for r in records if ".a" not in r.name]
        if len(records) != 320:
            self.skipTest("matrix-08 evidence not present")
        configs = list(q.DEFAULT_MATRIX_CONFIGS)

        def runner(command, env=None, capture_output=True, text=True):
            target = Path(env["OUT_DIR"])
            lines = []
            for cfg in configs:
                f, _, v = cfg.partition(":")
                for run in range(1, 21):
                    rec = self.MATRIX / f"{f}-{v}-r{run}.txt"
                    if (f, v, run) == ("F3", "list-0s", 16):
                        # matrix-08 run 16 failed on external typed input (RESULT.md); the committed
                        # rerun (rerun-F3-list-0s, 3/3 PASS) stands in so the replay sees 320 passes
                        shutil.copyfile(self.MATRIX / "rerun-F3-list-0s" / "F3-list-0s-r1.txt", target / rec.name)
                        rec = self.MATRIX / "rerun-F3-list-0s" / "F3-list-0s-r1.txt"
                    else:
                        shutil.copyfile(rec, target / rec.name)
                    selftest = [l for l in rec.read_text(errors="replace").splitlines() if l.startswith("SELFTEST ")][-1]
                    lines.append(f"{f} {v} run{run}: {selftest}")
            return argparse.Namespace(returncode=0, stdout="\n".join(lines), stderr="")
        ok = q.win_stage(self.log, configs, 20, self.dir, False, True, runner=runner, which=lambda n: "w",
                         tuple_pin=q.load_tuple(q.TUPLE_FINAL))
        self.assertTrue(ok, self.events()[-1])
        self.assertIn("320/320", self.events()[-1]["reason"])
        wrong = q.load_tuple(q.TUPLE_FINAL)
        wrong["pins"]["windows_renderer"] = "7" * 64
        self.assertFalse(q.win_stage(self.log, configs, 20, self.dir, False, True, runner=runner, which=lambda n: "w",
                                     tuple_pin=wrong))

    # ---- D3: win-replay produces the schema-v0 trace that compare consumes
    def test_replay_with_f1_trace_writes_the_file_compare_reads(self):
        self.assertTrue(self.stage(self.windows(), f1=True))
        trace = self.dir / "win-matrix" / q.WIN_TRACE_FILE
        self.assertTrue(trace.exists())
        last = self.events()[-1]
        self.assertEqual(last["artifact_ids"]["windows_f1_trace_v0"], "sha256:" + q.sha256_file(trace))
        steps = [c[1] if c[0] == "win" else "assemble" for c in self.calls if c[0] != "bash"]
        self.assertTrue("verify-artifacts.ps1" in steps[0] and "schedule-f1.ps1" in steps[1] and steps[-1] == "assemble", steps)
        self.assertIn(f"-ExpectExe {self.EXE.upper()}", steps[0])
        assemble = [c for c in self.calls if c[0] == "F1Assemble"][0]
        self.assertEqual(assemble[1], "win")
        self.assertIn("--keep-lists", assemble)
        self.assertEqual(Path(assemble[assemble.index("--stimulus") + 1]), q.F1_STIMULUS)
        self.assertEqual(len(list((self.dir / "win-matrix" / "f1").glob("*"))), 3)

    def test_without_f1_trace_nothing_is_recorded(self):
        self.assertTrue(self.stage(self.windows(), f1=False))
        self.assertFalse((self.dir / "win-matrix" / q.WIN_TRACE_FILE).exists())
        self.assertFalse(any("schedule-f1" in c[1] for c in self.calls if c[0] == "win"))

    def test_f1_trace_failures_fail_the_stage_with_a_reason(self):
        cases = {"build changed": (self.windows(verify="ARTIFACT_MISMATCH\n"), None, "no longer equals the matrix build"),
                 "recorder job failed": (self.windows(record="state=Ready last_result=1\nno run log\n"), None, "did not finish cleanly"),
                 "recorder timeout": (self.windows(record="last_result=0\nrecorder exit=0\nRECORDER TIMEOUT\n"), None, "did not finish"),
                 "pull failed": (self.windows(pull_ok=False), None, "F1 file pull failed"),
                 "assemble failed": (self.windows(), self.assembler(rc=1), "F1Assemble failed rc=1")}
        for name, (runner, assembler, text) in cases.items():
            with self.subTest(name):
                self.log.close()
                self.log = q.EventLog(self.dir / "e.jsonl", echo=False)
                self.assertFalse(self.stage(runner, f1=True, assembler=assembler))
                self.assertEqual(self.events()[-1]["event"], "fail")
                self.assertIn(text, self.events()[-1]["reason"])
                if name == "recorder job failed":
                    self.assertIn("UIARecorder.exe", self.events()[-1]["reason"], "names the missing recorder tree")

    def test_dry_run_plan_names_the_f1_steps(self):
        plan = q.win_plan(["F1:none"], 1, Path("/x"), f1_trace=True)
        f1 = plan["f1_trace"]
        self.assertIn("-Mode record", f1["record"][1])
        self.assertIn("-Bin " + q.F1_BIN, f1["record"][1])
        self.assertIn("verify-artifacts.ps1", f1["verify"][1])
        self.assertEqual(f1["assemble"][:2], ["F1Assemble", "win"])
        self.assertNotIn("f1_trace", q.win_plan(["F1:none"], 1, Path("/x")))

    def test_f1_assemble_command_reproduces_the_committed_windows_trace(self):
        """Same flags as the committed strict W6 trace: build F1Assemble from committed source and rerun it."""
        out = q.F1_PACKAGE / "out"
        needed = [out / n for n in ("winrec-w6.json", "winside-w6.json", "events-w6.txt", "win-trace-strict-w6.json")]
        if not all(n.exists() for n in needed) or not shutil.which("swift"):
            self.skipTest("w6 evidence or swift toolchain not present")
        if not os.environ.get("SR0A_BUILD_ROOT"):
            self.skipTest("set SR0A_BUILD_ROOT to an internal-disk path: a fresh binary run from /Volumes/D triggers TCC prompts")
        work = Path(tempfile.mkdtemp())  # system temp (internal disk): the fresh binary reads and writes nothing on /Volumes/D
        try:
            for src in (*needed[:3], q.F1_STIMULUS):
                shutil.copyfile(src, work / src.name)
            target = work / "reproduced.json"
            argv = ["F1Assemble", "win", "--rec", str(work / needed[0].name), "--side", str(work / needed[1].name),
                    "--events", str(work / needed[2].name), "--stimulus", str(work / q.F1_STIMULUS.name),
                    "--out", str(target), "--keep-lists"]
            rc, output = q.f1_assemble(argv)
            self.assertEqual(rc, 0, output)
            self.assertEqual(json.loads(target.read_text()), json.loads(needed[3].read_text()))
        finally:
            shutil.rmtree(work, ignore_errors=True)


class RunWiringTests(unittest.TestCase):
    """cmd_run passes the tuple and the F1 request to the stages (stages are replaced by recorders)."""
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.saved = (q.OUT_ROOT, q.win_stage, q.smoke_stage, q.package_stage)
        q.OUT_ROOT = self.dir
        self.seen = {}

        def make(stage):
            def fake(log, *args, **kw):
                self.seen[stage] = kw
                log.emit(stage, "pass", None, {k: "sha256:" + "a" * 64 for k in q.WINDOWS_PASS_IDS} if stage != "package" else {}, "ok")
                return True
            return fake
        q.win_stage, q.smoke_stage, q.package_stage = make("win-replay"), make("smoke"), make("package")

    def tearDown(self):
        q.OUT_ROOT, q.win_stage, q.smoke_stage, q.package_stage = self.saved
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_default_run_uses_the_final_tuple_and_exits_zero(self):
        self.assertEqual(q.cmd_run(run_args("--stages", "win-replay", "smoke", "package", "--confirm-windows-gui")), 0)
        for stage in ("win-replay", "smoke", "package"):
            self.assertEqual(self.seen[stage]["tuple_pin"]["name"], "final", stage)

    def test_no_tuple_runs_unpinned_and_is_non_qualifying(self):
        code = q.cmd_run(run_args("--stages", "win-replay", "smoke", "package", "--no-tuple", "--confirm-windows-gui"))
        self.assertEqual(code, 1, "pinned stages emit a skip, which is a failure outside --dry-run")
        for stage in ("win-replay", "smoke", "package"):
            self.assertIsNone(self.seen[stage]["tuple_pin"], stage)
        events = [json.loads(l) for f in self.dir.glob("*/events.jsonl") for l in f.read_text().splitlines() if l.strip()]
        skips = [e for e in events if e["event"] == "skip"]
        self.assertEqual(sorted(e["stage"] for e in skips), ["package", "smoke", "win-replay"])
        self.assertTrue(all("non-qualifying" in e["reason"] for e in skips))

    def test_tuple_and_no_tuple_are_exclusive_and_a_bad_tuple_is_a_usage_error(self):
        with self.assertRaises(SystemExit):
            run_args("--tuple", str(q.TUPLE_FINAL), "--no-tuple")
        bad = self.dir / "bad.json"
        bad.write_text("{}")
        self.assertEqual(q.cmd_run(run_args("--stages", "package", "--tuple", str(bad))), 2)

    def test_f1_trace_is_requested_only_when_compare_follows_win_replay(self):
        q.cmd_run(run_args("--stages", "win-replay", "compare", "--dry-run"))
        self.assertTrue(self.seen["win-replay"]["f1_trace"])
        q.cmd_run(run_args("--stages", "win-replay", "--dry-run"))
        self.assertFalse(self.seen["win-replay"]["f1_trace"])

    def test_win_replay_defaults_to_the_sixteen_sr0_configs(self):
        configs = run_args().configs
        self.assertEqual(len(configs), 16)
        text = q.MATRIX_SCRIPT.read_text(encoding="utf-8")
        sr0 = re.search(r"^SR0=\((.*?)\)\n", text, re.S | re.M).group(1)
        self.assertEqual(configs, re.findall(r'"([^"]+)"', sr0))


class WindowsDriverDriftTests(unittest.TestCase):
    def test_drivers_emit_the_artifacts_line_the_runner_parses(self):
        for path in (q.REPO / "probes/sr0-s/fresh-on-bridge/scripts/drive-fixture.ps1",
                     q.REPO / "examples/BridgeSmoke/scripts/drive-smoke.ps1"):
            with self.subTest(path.name):
                self.assertIn("ARTIFACTS exe=$", path.read_text(encoding="utf-8"))
        line = f"ARTIFACTS exe={'a' * 64} renderer={'b' * 64} trace={'c' * 64}"
        self.assertEqual(q.parse_windows_artifacts(line), ("a" * 64, "b" * 64, "c" * 64))


class HarnessDriftTests(unittest.TestCase):
    """The declared checks, the schema file and the harnesses must agree on one format."""
    CLEAN = q.REPO / "qualification" / "clean-machine"
    MAC = CLEAN / "mac-clean-run.sh"
    GUEST = CLEAN / "windows" / "guest" / "sandbox-run.ps1"
    HOST = CLEAN / "windows" / "run-sandbox.ps1"

    def mac_profile(self, name):
        text = self.MAC.read_text(encoding="utf-8")
        return tuple(re.findall(r"M\d{2}-[a-z0-9-]+", re.search(rf"{name}=\((.*?)\)", text, re.S).group(1)))

    def test_mac_harness_profiles_cover_the_package_checks(self):
        """The runner takes the union of the profiles: automated (M00-M10) + manual (M11) = PACKAGE_CHECKS."""
        automated, manual, window = (self.mac_profile(n) for n in ("EXPECTED_AUTOMATED", "EXPECTED_MANUAL", "EXPECTED_WINDOW"))
        self.assertEqual(automated + manual, q.PACKAGE_CHECKS["macos-arm64"])
        self.assertEqual(manual, tuple(q.MANUAL_CHECKS))
        self.assertEqual(window, manual, "the window-server profile is another way to record the same check as manual")
        self.assertFalse(set(automated) & set(manual), "M11 is never in the automated profile")

    def test_mac_harness_guard_refuses_uid_501_only_outside_a_vm(self):
        text = self.MAC.read_text(encoding="utf-8")
        self.assertIn('[ "$uid" -ne "$MAIN_UID" ] || in_vm || die', text)
        # values observed in a Tart guest on 10 Oct 2026 (macOS 26.6.2): kern.hv_vmm_present=1, hw.model=VirtualMac2,1
        self.assertRegex(text, r'sysctl -n kern\.hv_vmm_present[^\n]*= 1 \]')
        self.assertIn("VirtualMac*", text)
        for refusal in ('refusing to run as root', 'refusing to run as $MAIN_USER', "is not listed in", "must be owned by",
                        "group/world writable", "is not /Users/$me", "must be under $HOME"):
            self.assertIn(refusal, text)

    def test_mac_harness_never_calls_python3_or_the_xcrun_shims(self):
        """The vanilla guest has only Command Line Tools shims: each call pops an install dialog."""
        code = "\n".join(line for line in self.MAC.read_text(encoding="utf-8").splitlines() if not line.lstrip().startswith("#"))
        self.assertIsNone(re.search(r"\bpython3\s+-", code))
        self.assertNotIn("xcrun", code)
        self.assertNotIn("stapler", code)
        self.assertIn("syspolicy_check distribution", code)

    def test_mac_harness_m08_uses_the_r7_interrupt_method_in_all_three_modes(self):
        text = self.MAC.read_text(encoding="utf-8")
        self.assertIn("for mode in copy swap swap-term", text)
        self.assertIn("interrupt-mac-install-hook.mjs", text)
        self.assertIn("RIGHT_RELEASE=", text)
        self.assertNotIn("interrupted_install_placeholder", text)

    def extract_perl(self, name):
        """The perl program of one heredoc in the harness (check_finish, write_run_record), in file order."""
        blocks = re.findall(r"<<'PL'\n(.*?)\nPL\n", self.MAC.read_text(encoding="utf-8"), re.S)
        return blocks[name]

    def run_perl(self, program, *args):
        import subprocess
        return subprocess.run(["perl", "-", *map(str, args)], input=program, text=True, capture_output=True, check=False)

    @unittest.skipUnless(shutil.which("perl"), "perl not available")
    def test_mac_harness_receipt_writers_produce_records_the_runner_accepts(self):
        """Runs the harness's own perl writers (not the harness) on synthetic input and loads the result with the runner."""
        SCRATCH.mkdir(parents=True, exist_ok=True)
        work = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        rdir = work / "run"
        (work / "env.tsv").write_text("host\tVM\nos_version\tmacOS 26.6.2 (25G83)\nuser\tadmin\narch\tarm64\nvm\ttrue\n")
        sha = "sha256:" + "ab" * 32
        checks = self.mac_profile("EXPECTED_AUTOMATED")
        for index, cid in enumerate(checks):
            (work / "o.tsv").write_text("launch_first_alive\ttrue\nquarantine_OLD\t0081;6ac;Safari;U\n")
            (work / "a.tsv").write_text(f"old_dmg\t{sha}\n")
            fail = cid == "M08-interrupted-install"
            done = self.run_perl(self.extract_perl(0), rdir, "RUN1", cid, "name " + cid, "true", "fail" if fail else "pass",
                                 "boom" if fail else "-", "-" if index == 0 else str(index),
                                 "2026-10-10T00:00:00Z", "2026-10-10T00:00:01Z", work / "o.tsv", work / "a.tsv",
                                 work / "env.tsv", "mac-clean-run.sh", sha)
            self.assertEqual(done.returncode, 0, done.stderr)
        run = self.run_perl(self.extract_perl(1), rdir, "RUN1", "2026-10-10T00:00:00Z", "mac-clean-run.sh", sha, sha,
                            "sha256:" + "cd" * 32, *checks)
        self.assertEqual(run.returncode, 1, "a failing M08 fails the run")
        rec, problems, records = q.load_package_run(rdir)
        self.assertEqual(rec["status"], "fail")
        self.assertEqual(rec["expected_checks"], list(checks))
        self.assertEqual(rec["artifact_ids"], {"old_dmg": sha, "new_dmg": "sha256:" + "cd" * 32})
        self.assertEqual(q.validate_check_record(records["M08-interrupted-install"][0], "macos-arm64", "RUN1",
                                                 "M08-interrupted-install"), [])
        self.assertEqual(records["M00-environment"][0]["exit_status"], None)
        self.assertEqual(records["M03-gatekeeper-dmg"][0]["exit_status"], 3)
        self.assertEqual(len(problems), 2, problems)  # M08 fail: run status and the check; every other record is accepted
        self.assertTrue(all("M08" in p or "run status" in p for p in problems), problems)

    def test_windows_harnesses_declare_the_package_checks(self):
        for path in (self.GUEST, self.HOST):
            with self.subTest(path.name):
                text = path.read_text(encoding="utf-8")
                block = re.search(r"\$ExpectedChecks\s*=\s*@\((.*?)\)", text, re.S).group(1)
                self.assertEqual(tuple(re.findall(r"'(W\d{2}-[a-z0-9-]+)'", block)), q.PACKAGE_CHECKS["windows-x64"])

    def test_every_harness_writes_only_the_v2_schema(self):
        for path in (self.MAC, self.GUEST, self.HOST):
            with self.subTest(path.name):
                text = path.read_text(encoding="utf-8")
                self.assertIn(q.PACKAGE_RECEIPT_SCHEMA, text)
                self.assertNotIn("clean-machine-receipt/", text)
                self.assertNotIn("sr0-a.package-receipt/v1", text)

    def test_json_schema_file_matches_the_code(self):
        schema = json.loads((self.CLEAN / "receipt.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(schema["title"], q.PACKAGE_RECEIPT_SCHEMA)
        self.assertEqual(set(schema["$defs"]["check"]["required"]), set(q.PACKAGE_CHECK_KEYS))
        self.assertEqual(set(schema["$defs"]["run"]["required"]), set(q.PACKAGE_RUN_KEYS))
        self.assertEqual(schema["$defs"]["check"]["properties"]["schema"]["const"], q.PACKAGE_RECEIPT_SCHEMA)
        self.assertEqual(schema["$defs"]["run"]["properties"]["schema"]["const"], q.PACKAGE_RECEIPT_SCHEMA)


if __name__ == "__main__":
    unittest.main()
