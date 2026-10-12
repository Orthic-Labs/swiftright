#!/usr/bin/env python3
"""Bounded source controls; root runs through supervise-job when authorized."""
from __future__ import annotations
import copy, json, sys
import hashlib
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
MAX_TEXT = 64 * 1024 * 1024
def load(path: Path):
    st = path.stat()
    if path.is_symlink() or not path.is_file() or st.st_size > MAX_JSON: raise ValueError("unbounded JSON")
    return json.loads(path.read_text(encoding="utf-8"))
def text(path: Path):
    st = path.stat()
    if path.is_symlink() or not path.is_file() or st.st_size > MAX_TEXT: raise ValueError("unbounded source")
    return path.read_text(encoding="utf-8")
def digest(path: Path):
    st = path.stat()
    if path.is_symlink() or not path.is_file() or st.st_size > MAX_TEXT: raise ValueError("unbounded source")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return "sha256:" + h.hexdigest()

def admit(recipe: dict, witness: str, branch: str) -> None:
    i = recipe["inputs"]
    assert recipe["id"] == "swiftui.circle.fixed.recipe"
    assert i["shape"] == "Circle()" and i["style"] == "fill(Color.blue)"
    assert i["semanticColor"] == "system.blue"
    assert i["colorScheme"] == "light" and i["frameDip"] == {"width": 40, "height": 40}
    assert i["viewportDip"] == {"width": 320, "height": 240}
    assert "Circle()" in witness and "Color.blue" in witness and "width: 40" in witness and "height: 40" in witness
    assert ".light" in witness and "factoryRequireCircleFixedViewport" in branch
    assert "scale.isFinite" in branch and "Float(client.width) / scale - 320" in branch and "Float(client.height) / scale - 240" in branch
    assert "factoryCircleFixedPrimitive" in branch and "shape.geometry == .circle" in branch

def fault_cases(recipe: dict, witness: str, branch: str):
    cases = []
    for name, mutate in (
        ("wrong-frame", lambda r: r["inputs"]["frameDip"].update(width=41)),
        ("wrong-viewport", lambda r: r["inputs"]["viewportDip"].update(width=321)),
        ("wrong-color", lambda r: r["inputs"].update(semanticColor="system.red")),
        ("wrong-shape", lambda r: r["inputs"].update(shape="Rectangle()")),
    ):
        candidate = copy.deepcopy(recipe); mutate(candidate)
        try: admit(candidate, witness, branch)
        except (AssertionError, KeyError): cases.append(name)
    assert cases == ["wrong-frame", "wrong-viewport", "wrong-color", "wrong-shape"]

def main() -> int:
    if len(sys.argv) != 4: raise SystemExit("recipe witness branch")
    recipe = load(Path(sys.argv[1])); witness_path = Path(sys.argv[2]); witness = text(witness_path)
    branch = text(Path(sys.argv[3]))
    assert recipe["witness"]["sha256"] == digest(witness_path)
    admit(recipe, witness, branch); fault_cases(recipe, witness, branch)
    print(json.dumps({"status": "SOURCE_CONTROLS_PASS", "positive": True, "faults": 4, "effects": {"nativeActions": 0}}))
    return 0
if __name__ == "__main__": raise SystemExit(main())
