#!/usr/bin/env python3
"""Lane B text-input cases (blocks 13 swiftui.textfield, 14 swiftui.focus-state, 15 swiftui.ime-marked-text). Stamps, per case:
  <block>/<case>/package/{Package.swift, Sources/FactoryProbe/{Witness.swift, main.swift (text-hosts/windows), FactoryViewport.swift}}
  <block>/<case>/mac-source/Sources/MacHost/{Witness.swift (byte-identical), CaptureHost.swift (text-hosts/mac)}
  <block>/<case>/pair.json  (exclusions, semantic gate, interaction steps for the Windows F2 job and the Mac host, the in-process script)
usage: make-text-cases.py [case-substring ...]   (all cases when none is named)"""
import json, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WINHOST = HERE.parent / "pilot-delivery-five-v1/shared-windows-host"
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
PACKAGE = (WINHOST / "stamp-case.py").read_text().split("PACKAGE = '''")[1].split("'''")[0].encode().decode("unicode_escape")

FIELD_RECT = [35, 30, 315, 80]   # text area of a 120 x 24 pt field padded by 10 pt, in capture px
SEM = {"fields": ["role", "name", "value", "enabled"], "scope": "main", "roles": ["textfield", "text"]}


def cases():
    out = []
    def case(block, name, witness, wtype, **kw):
        out.append(dict(block=block, name=name, witness=witness, wtype=wtype, **kw))
    pad = ".frame(width: 120).padding(10)"
    case("swiftui.textfield", "placeholder-v1", f'''struct Witness_tf_placeholder: View {{
    @State private var name = ""
    var body: some View {{ TextField("Name", text: $name).textFieldStyle(.roundedBorder){pad} }}
}}''', "Witness_tf_placeholder", exclude=[("placeholder 'Name' glyphs (Segoe UI vs SF, sr1-decisions #2)", FIELD_RECT)], sem=SEM)
    case("swiftui.textfield", "prompt-v1", f'''struct Witness_tf_prompt: View {{
    @State private var name = ""
    var body: some View {{ TextField("Name", text: $name, prompt: Text("Enter")).textFieldStyle(.roundedBorder){pad} }}
}}''', "Witness_tf_prompt", exclude=[("prompt 'Enter' glyphs", FIELD_RECT)], sem=SEM)
    case("swiftui.textfield", "filled-truncated-v1", '''struct Witness_tf_truncated: View {
    @State private var name = "A long sentence that will not fit"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 80).padding(10) }
}''', "Witness_tf_truncated", exclude=[("typed text glyphs, clipped at the field's text area", [35, 30, 215, 80])], sem=SEM)
    case("swiftui.textfield", "plain-v1", '''struct Witness_tf_plain: View {
    @State private var name = "Hello"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.plain).frame(width: 120).padding(10) }
}''', "Witness_tf_plain", exclude=[("plain field text (no bezel; the whole 16 pt line)", [25, 25, 325, 65])], sem=SEM)
    case("swiftui.textfield", "automatic-style-v1", f'''struct Witness_tf_automatic: View {{
    @State private var name = "Hello"
    var body: some View {{ TextField("Name", text: $name){pad} }}
}}''', "Witness_tf_automatic", exclude=[("typed text glyphs", FIELD_RECT)], sem=SEM)
    return out


def stamp(c):
    d = HERE / c["block"] / c["name"]
    pkg = d / "package/Sources/FactoryProbe"; mac = d / "mac-source/Sources/MacHost"
    pkg.mkdir(parents=True, exist_ok=True); mac.mkdir(parents=True, exist_ok=True)
    for old in list(pkg.glob("*.swift")) + list(mac.glob("*.swift")):
        old.unlink()
    witness = HEADER + c["witness"] + "\n"
    (pkg / "Witness.swift").write_text(witness); (mac / "Witness.swift").write_text(witness)
    script = json.dumps(c.get("script", []), separators=(",", ":"))
    expr = f'{c["wtype"]}()'
    win = (HERE / "text-hosts/windows/CaptureHost.template.swift").read_text()
    win = win.replace("@@WITNESS@@", expr).replace("@@CENTERED@@", "false").replace("@@DARK@@", "false").replace("@@SCRIPT@@", script.replace("\\", "\\\\").replace('"', '\\"'))
    assert "@@" not in win
    (pkg / "main.swift").write_text(win)
    shutil.copy(WINHOST / "FactoryViewport.swift", pkg / "FactoryViewport.swift")
    (d / "package/Package.swift").write_text(PACKAGE)
    m = (HERE / "text-hosts/mac/CaptureHost.template.swift").read_text().replace("@@WITNESS@@", expr).replace("@@SETTLE@@", "0.3")
    assert "@@" not in m
    (mac / "CaptureHost.swift").write_text(m)
    pj = {}
    if c.get("exclude"):
        pj["excludeRects"] = [{"name": n, "rect": r} for n, r in c["exclude"]]
    if c.get("sem"):
        pj["semanticGate"] = c["sem"]
    if c.get("steps"):
        pj["steps"] = c["steps"]
        pj["macArgs"] = ["--steps", json.dumps(c["steps"], separators=(",", ":"))]
    elif c.get("sem"):
        pj["steps"] = [{"op": "wait", "ms": 300}]   # the F2 interact job dumps the UIA tree for the semantic gate; the Mac side stays never-shown
    (d / "pair.json").write_text(json.dumps(pj, indent=1) + "\n")
    print("stamped", d.relative_to(HERE))


if __name__ == "__main__":
    want = sys.argv[1:]
    for c in cases():
        if not want or any(w in f'{c["block"]}/{c["name"]}' for w in want):
            stamp(c)
