"""F6 unordered-completion canonicalization (CONTRACT C9). Run: python3 -I -m unittest test_normalize_hash"""
import importlib.util, json, pathlib, unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("nh", HERE / "normalize-hash.py")
nh = importlib.util.module_from_spec(spec); spec.loader.exec_module(nh)

def load(path):
    return nh.normalized_lines(path)

def digest(lines):
    return nh.canonical_body(lines)

def anim(phase, tag):
    return json.dumps({"fixture": "F6", "kind": "lifecycle", "node_id": "animation",
                       "payload": {"phase": phase, "tag": tag}, "step": "burst-insert"}, sort_keys=True, separators=(",", ":"))

def other(name, step="burst-insert"):
    return json.dumps({"fixture": "F6", "kind": "lifecycle", "node_id": name,
                       "payload": {"phase": "appear"}, "step": step}, sort_keys=True, separators=(",", ":"))

def final(text="Anim B"):
    return json.dumps({"fixture": "F6", "kind": "state", "node_id": "model",
                       "payload": {"rows": [text]}, "step": "burst-insert"}, sort_keys=True, separators=(",", ":"))

BASE = [anim("start", "A"), anim("start", "B"), other("r1"), anim("complete", "A"), other("r2"), anim("complete", "B"), final()]

class F6Unordered(unittest.TestCase):
    def test_swap_passes(self):
        sw = list(BASE); sw[3], sw[5] = sw[5], sw[3]
        self.assertEqual(digest(BASE), digest(sw))

    def test_b_completes_twice_fails(self):
        bad = list(BASE); bad[3] = anim("complete", "B")
        self.assertNotEqual(digest(BASE), digest(bad))

    def test_b_complete_before_b_start_fails(self):
        bad = [anim("start", "A"), anim("complete", "B"), anim("start", "B"), other("r1"), anim("complete", "A"), other("r2"), final()]
        self.assertNotEqual(digest(BASE), digest(bad))

    def test_missing_completion_fails(self):
        self.assertNotEqual(digest(BASE), digest(BASE[:5] + BASE[6:]))

    def test_unrelated_node_reorder_fails(self):
        bad = [anim("start", "A"), anim("start", "B"), other("r1"), other("r1"), anim("complete", "A"), anim("complete", "B"), final()]
        base = [anim("start", "A"), anim("start", "B"), other("r1"), anim("complete", "A"), anim("complete", "B"), other("r1"), final()]
        # per-node order of an unrelated node: appear/disappear swap
        a = other("r1"); d = a.replace("appear", "disappear")
        self.assertNotEqual(digest(base[:2] + [a, d] + base[3:]), digest(base[:2] + [d, a] + base[3:]))
        # an unrelated event moved across a step boundary is also caught
        self.assertNotEqual(digest(BASE), digest([e.replace("burst-insert", "other") if "r2" in e else e for e in BASE]))

    def test_start_swap_fails(self):
        bad = list(BASE); bad[0], bad[1] = bad[1], bad[0]
        self.assertNotEqual(digest(BASE), digest(bad))

    def test_wrong_final_state_fails(self):
        self.assertNotEqual(digest(BASE), digest(BASE[:-1] + [final("Anim A")]))

    def test_only_f6(self):
        other_fix = [e.replace('"F6"', '"F3"') for e in BASE]
        sw = list(other_fix); sw[3], sw[5] = sw[5], sw[3]
        self.assertNotEqual(digest(other_fix), digest(sw))

class Committed(unittest.TestCase):
    def test_traces_all_equal_baseline(self):
        base = digest(load(ROOT / "conformance/accepted/F6/trace.jsonl"))
        paths = sorted((ROOT / "probes/sr0-o/r6/f6").glob("run*.jsonl"))
        paths += sorted((ROOT / "conformance/candidates/F6").glob("*/candidate.jsonl"))
        self.assertGreaterEqual(len(paths), 5)
        for p in paths:
            with self.subTest(p=str(p)):
                self.assertEqual(base, digest(load(p)))

if __name__ == "__main__":
    unittest.main()
