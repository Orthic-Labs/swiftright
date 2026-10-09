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
        q.package_stage = lambda log, paths, dry=False, repo=q.REPO: log.emit("package", "skip", reason="no")
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

    def smoke_runner(self, text, rc=0):
        return lambda command, capture_output=True, text_=True, **kw: argparse.Namespace(returncode=rc, stdout=text, stderr="")

    def test_smoke_dry_run_prints_plan_and_skips(self):
        self.assertTrue(q.smoke_stage(self.log, self.dir, True, False))
        self.assertEqual(self.log.skips, 1)
        plan = q.smoke_plan("t1")
        self.assertEqual(plan["command"][0], "win")
        self.assertIn("schedule-smoke.ps1", plan["command"][1])
        self.assertIn("-Tag t1", plan["command"][1])

    def test_smoke_refuses_without_confirmation(self):
        self.assertFalse(q.smoke_stage(self.log, self.dir, False, False))
        self.assertEqual(self.log.failures, 1)

    def test_smoke_pass_needs_markers_and_artifacts(self):
        good = "AUTOMATIONID PASS\nrun: ok\n" + self.artifacts_line()
        self.assertTrue(q.smoke_stage(self.log, self.dir, False, True, runner=self.smoke_runner(good), which=lambda n: "w"))
        self.assertEqual(self.events()[-1]["artifact_ids"]["windows_exe"], "sha256:" + self.EXE)
        for text in ("AUTOMATIONID PASS\nrun: ok\n", "AUTOMATIONID FAIL\nrun: ok\n" + self.artifacts_line()):
            log = q.EventLog(self.dir / "x.jsonl", echo=False)
            self.assertFalse(q.smoke_stage(log, self.dir, False, True, runner=self.smoke_runner(text), which=lambda n: "w"))
            self.assertEqual(log.failures, 1)
            log.close()


class PackageStageTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.log = q.EventLog(self.dir / "e.jsonl", echo=False)
        self.art = self.dir / "slice.exe"
        self.art.write_bytes(b"exe")

    def tearDown(self):
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def receipt(self, platform="windows-x64", **overrides):
        body = {"schema": q.PACKAGE_RECEIPT_SCHEMA, "product": "SliceApp", "platform": platform,
                "created_ts": "2026-10-09T10:00:00.000Z", "source_rev": "abc1234", "verdict": "PASS",
                "artifacts": {"slice": {"sha256": hashlib.sha256(b"exe").hexdigest(), "path": str(self.art)}},
                "checks": [{"name": "launch", "result": "PASS"}, {"name": "signature", "result": "PASS"}]}
        body.update(overrides)
        return body

    def write(self, name, body):
        (self.dir / "receipts").mkdir(exist_ok=True)
        (self.dir / "receipts" / name).write_text(json.dumps(body), encoding="utf-8")

    def stage(self):
        return q.package_stage(self.log, [self.dir / "receipts"])

    def test_both_platform_receipts_pass(self):
        self.write("win.json", self.receipt("windows-x64"))
        self.write("mac.json", self.receipt("macos-arm64"))
        self.assertTrue(self.stage())
        self.assertEqual(self.log.passes["package"], 2)
        self.assertEqual(self.log.failures, 0)

    def test_absent_receipts_fail(self):
        self.assertFalse(self.stage())
        self.assertEqual(self.log.failures, 1)

    def test_missing_platform_fails(self):
        self.write("win.json", self.receipt("windows-x64"))
        self.assertFalse(self.stage())
        self.assertIn("macos-arm64", self.events()[-1]["reason"])

    def events(self):
        return [json.loads(l) for l in (self.dir / "e.jsonl").read_text().splitlines() if l.strip()]

    def test_failed_verdict_check_or_hash_mismatch_fails(self):
        for name, overrides in (("verdict", {"verdict": "FAIL"}),
                                ("check", {"checks": [{"name": "launch", "result": "FAIL"}]}),
                                ("hash", {"artifacts": {"slice": {"sha256": "0" * 64, "path": str(self.art)}}}),
                                ("nohash", {"artifacts": {"slice": {"path": str(self.art)}}}),
                                ("nochecks", {"checks": []}),
                                ("schema", {"schema": "other/v1"}),
                                ("platform", {"platform": "linux-x64"})):
            self.assertTrue(q.validate_package_receipt(self.receipt(**overrides)), name)
        self.assertEqual(q.validate_package_receipt(self.receipt()), [])

    def test_invalid_receipt_fails_even_when_platforms_are_covered(self):
        self.write("win.json", self.receipt("windows-x64"))
        self.write("mac.json", self.receipt("macos-arm64"))
        self.write("bad.json", self.receipt("macos-arm64", verdict="FAIL"))
        self.assertFalse(self.stage())

    def test_malformed_json_fails(self):
        (self.dir / "receipts").mkdir()
        (self.dir / "receipts" / "x.json").write_text("{nope")
        self.assertFalse(self.stage())

    def test_package_dry_run_skips(self):
        self.assertTrue(q.package_stage(self.log, [self.dir / "receipts"], dry_run=True))
        self.assertEqual(self.log.skips, 1)


if __name__ == "__main__":
    unittest.main()
