"""Scan the Pulse notch's Swift source for SwiftUI API use.

Lexical, not semantic: a token counts only if the pinned SDK's SwiftUI / SwiftUICore
interface declares it (see swiftui_index.py).  Precision limits are written to the report.
"""
import re
from collections import defaultdict
from pathlib import Path

import lexer

# SwiftUI value types whose static / enum members appear as implicit members (`.easeInOut`).
VALUE_CONTEXTS = [
    "Animation", "Alignment", "HorizontalAlignment", "VerticalAlignment", "Edge", "Edge.Set", "Axis",
    "Axis.Set", "UnitPoint", "Font", "Font.Weight", "Font.Design", "BlendMode", "Visibility",
    "ContentMode", "ControlSize", "ColorScheme", "Color", "AnyTransition", "Material", "Angle",
    "LayoutDirection", "TextAlignment", "Text.TruncationMode", "StrokeStyle", "FillStyle", "Gradient",
    "ShapeStyle", "KeyboardShortcut", "KeyEquivalent", "EventModifiers", "ButtonRole", "AccessibilityTraits",
    "HitTestingMode", "Transaction", "SymbolRenderingMode", "RoundedCornerStyle", "CoordinateSpace", "Spring",
    "ScrollTargetBehavior", "ColorRenderingMode", "Image.ResizingMode", "Image.Scale", "Text.Scale", "GraphicsContext.Shading",
]
# Names that are plain Swift/Foundation/AppKit members as often as SwiftUI ones; never counted as SwiftUI.
STOP_MEMBERS = {
    "init", "zero", "default", "none", "all", "infinity", "pi", "map", "filter", "first", "last", "count",
    "id", "min", "max", "contains", "reduce", "sorted", "append", "insert", "remove", "isEmpty", "value",
    "black", "white", "clear", "red", "green", "blue", "yellow", "orange", "gray", "purple", "pink",
    "primary", "secondary", "left", "right", "center", "top", "bottom", "natural", "justified",
    "standard", "regular", "small", "medium", "large", "mini", "automatic", "plain", "bordered", "light",
    "dark", "removed", "current", "self", "unspecified", "identity", "current", "empty", "text", "name",
    "title", "label", "action", "body", "shared", "main", "system", "format", "size", "height", "width",
    "x", "y", "origin", "frame", "bounds", "alpha", "color", "font", "image", "string", "data", "date",
    "disabled", "hidden", "tag", "offset", "position", "rotation", "scale", "mask", "border", "shadow",
}
MODIFIER_STOP = {"id", "init", "tag"}
IMPLICIT_STOP = {"init", "self", "zero", "infinity", "pi", "identity", "current", "unspecified", "empty"}
TYPE_RX = re.compile(r"(?<![\w.@])([A-Z][A-Za-z0-9_]*)\b")
WRAP_RX = re.compile(r"@([A-Z]\w*)")
DOT_RX = re.compile(r"\.([A-Za-z_]\w*)")
GENERIC_RX = re.compile(r"\b(?:struct|class|enum|func|init|protocol|extension|typealias|associatedtype)\b[^{\n]*")
DECL_RX = re.compile(r"\b(?:struct|class|enum|protocol|actor|typealias|associatedtype)\s+([A-Z]\w*)")
GEN_PARAM_RX = re.compile(r"(?:<|,)\s*([A-Z]\w*)\s*(?::|,|>)")
PREV_RECEIVER = set(")]}>\"?!") 
IMPLICIT_AFTER = set("(,:=[{;<&|+-*/%~^")


def project_names(files):
    names = set()
    for text in files.values():
        names.update(DECL_RX.findall(text))
        for line in GENERIC_RX.findall(text):
            names.update(GEN_PARAM_RX.findall(line))
    return names


# Receiver-bearing calls that are SwiftUI (checked by hand against the source; everything else with a
# receiver is treated as Foundation/AppKit/own code).  name -> (owner, regex the text after the dot must match)
MEMBER_CALLS = {
    "addArc": ("Path", None), "addCurve": ("Path", None), "addEllipse": ("Path", None),
    "addLine": ("Path", None), "addQuadCurve": ("Path", None), "addRect": ("Path", None),
    "addRoundedRect": ("Path", None), "addLines": ("Path", None), "closeSubpath": ("Path", None),
    "move": ("Path", r"move\(\s*to:"), "applying": ("Path", None), "offsetBy": ("Path", None),
    "strokedPath": ("Path", None), "trimmedPath": ("Path", None), "addPath": ("Path", None),
    "fill": ("Shape/GraphicsContext", None), "stroke": ("Shape/GraphicsContext", None),
    "strokeBorder": ("InsettableShape", None), "trim": ("Shape", r"trim\(\s*from:"),
    "addFilter": ("GraphicsContext", None), "drawLayer": ("GraphicsContext", None),
    "translateBy": ("GraphicsContext", None), "clip": ("GraphicsContext", None),
    "resizable": ("Image", None), "interpolation": ("Image", None), "renderingMode": ("Image", None),
    "delay": ("Animation", None), "repeatForever": ("Animation", None), "repeatCount": ("Animation", None),
    "speed": ("Animation", None),
    "onChanged": ("Gesture", None), "onEnded": ("Gesture", None), "updating": ("Gesture", None),
    "place": ("LayoutSubview", r"place\(\s*at:"), "scrollTo": ("ScrollViewProxy", None),
    "combined": ("AnyTransition", r"combined\(\s*with:"), "interactive": ("Glass", None),
    "commands": ("Scene", None),
}
# Project methods that share a SwiftUI modifier's name: skip when the first argument label says so.
MODIFIER_EXCLUDE_ARGS = {
    "offset": r"\(\s*(?:for|of|by|from|to|in):", "position": r"\(\s*(?:for|of|by|from|to|in):",
    "frame": r"\(\s*forContentRect", "environment": r"\(\s*(?:for|of):",
}
IMPLICIT_ENCLOSING_EXTRA = {"withAnimation", "withTransaction", "system", "custom", "init"}


def enclosing_call(text, pos, limit=600):
    """Name of the nearest unmatched `name(` before pos, or None (closure bodies stop the search)."""
    stack = []
    k = pos - 1
    lo = max(0, pos - limit)
    while k >= lo:
        c = text[k]
        if c in ")]}":
            stack.append(c)
        elif c in "([{":
            if stack:
                stack.pop()
            elif c == "(":
                j = k - 1
                while j >= 0 and text[j] in " \t\n":
                    j -= 1
                if j >= 0 and text[j] == ">":
                    d = 0
                    while j >= 0:
                        if text[j] == ">":
                            d += 1
                        elif text[j] == "<":
                            d -= 1
                            if d == 0:
                                j -= 1
                                break
                        j -= 1
                e = j
                while j >= 0 and (text[j].isalnum() or text[j] == "_"):
                    j -= 1
                return text[j + 1:e + 1] or None
            elif c == "{":
                return None
        k -= 1
    return None


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def prev_char(text, pos):
    k = pos - 1
    while k >= 0 and text[k] in " \t\r\n":
        k -= 1
    if k < 0:
        return ""
    # keyword before the dot means an implicit member (return .x, case .x, in .x ...)
    j = k
    while j >= 0 and (text[j].isalnum() or text[j] == "_"):
        j -= 1
    word = text[j + 1:k + 1]
    if word in ("return", "case", "in", "else", "if", "switch", "where", "default", "await", "try", "throw"):
        return "("
    return text[k]


def scan_file(path, text, ix, own_names):
    """Yield (kind, name, line, extra) tuples for one SwiftUI-importing file."""
    code = lexer.strip(text)
    types = ix["types"]
    wrappers = ix["wrappers"]
    members = ix["members"]
    view_funcs = {n for n, k in members.get("View", {}).items() if any(x.endswith("func") for x in k)}
    value_ctx = {c: members.get(c, {}) for c in VALUE_CONTEXTS if c in members}
    out = []
    for m in WRAP_RX.finditer(code):
        nm = m.group(1)
        if nm in wrappers:
            out.append(("wrapper", nm, line_of(code, m.start()), ""))
        elif nm in ("Published",):
            out.append(("combine", "@Published", line_of(code, m.start()), ""))
    for m in re.finditer(r"\bObservableObject\b|\bimport Combine\b|\bPassthroughSubject\b|\bCurrentValueSubject\b|\.sink\s*\{|\.receive\s*\(on|\bAnyCancellable\b|\.objectWillChange\b", code):
        out.append(("combine", m.group(0).strip(), line_of(code, m.start()), ""))
    for m in TYPE_RX.finditer(code):
        nm = m.group(1)
        if nm in types and "." not in nm and nm not in own_names and nm not in wrappers:
            out.append(("type", nm, line_of(code, m.start()), types[nm]))
    for m in re.finditer(r"(?<![\w.@])([A-Z]\w*)\s*(?:<[^>\n]*>)?\(\s*(?:(\w+)\s*:)?", code):
        nm = m.group(1)
        if nm in types and "." not in nm and nm not in own_names and nm not in wrappers:
            out.append(("form", nm, line_of(code, m.start()), m.group(2) or "_"))
    for m in DOT_RX.finditer(code):
        nm = m.group(1)
        s = m.start()
        # explicit Type.member
        k = s - 1
        recv_word = ""
        if k >= 0 and (code[k].isalnum() or code[k] == "_"):
            j = k
            while j >= 0 and (code[j].isalnum() or code[j] == "_"):
                j -= 1
            recv_word = code[j + 1:k + 1]
        after = code[m.end():m.end() + 1] if m.end() < len(code) else ""
        rest = code[m.end():m.end() + 40].lstrip(" \t")
        called = rest.startswith("(") or rest.startswith("{")
        pc = prev_char(code, s)
        ln = line_of(code, s)
        if recv_word and recv_word[0].isupper() and recv_word in types and recv_word not in own_names:
            ctxm = members.get(recv_word, {})
            if nm in ctxm and nm not in STOP_MEMBERS:
                out.append(("static", f"{recv_word}.{nm}", ln, "explicit"))
            continue
        if pc == "" or pc in IMPLICIT_AFTER:
            if nm in IMPLICIT_STOP:
                continue
            owners = sorted(c for c, mm in value_ctx.items() if nm in mm)
            if not owners:
                continue
            enc = enclosing_call(code, s)
            if enc and (enc in view_funcs or enc in MEMBER_CALLS or (enc in types and "." not in enc and enc not in own_names)
                        or enc in IMPLICIT_ENCLOSING_EXTRA):
                out.append(("implicit", nm, ln, ",".join(owners)))
            continue
        # receiver present
        if called and nm in view_funcs and nm not in MODIFIER_STOP and nm not in MEMBER_CALLS:
            ex = MODIFIER_EXCLUDE_ARGS.get(nm)
            if ex and re.match(ex, code[m.end():m.end() + 40]):
                continue
            out.append(("modifier", nm, ln, ""))
        elif called and nm in MEMBER_CALLS:
            owner, rx = MEMBER_CALLS[nm]
            if rx is None or re.match(rx, code[s + 1:s + 40]):
                out.append(("member-call", nm, ln, owner))
    for m in re.finditer(r"\\\.([A-Za-z_]\w*)", code):
        if m.group(1) in members.get("EnvironmentValues", {}):
            out.append(("env-key", m.group(1), line_of(code, m.start()), ""))
    return out


EXT_RX = re.compile(r"\bextension\s+([A-Z]\w*)\b[^{]*\{")


def extension_inits(files):
    """Init labels the project itself adds to a type (extension Color { init(hex:) }): not SwiftUI API."""
    out = {}
    for text in files.values():
        code = lexer.strip(text)
        for m in EXT_RX.finditer(code):
            depth, k = 1, m.end()
            while k < len(code) and depth:
                depth += (code[k] == "{") - (code[k] == "}")
                k += 1
            body = code[m.end():k]
            for im in re.finditer(r"(?<![.\w])init\??\(\s*(\w+)\s*(?:\w+\s*)?:", body):
                out.setdefault(m.group(1), set()).add(im.group(1))
    return out


def scan_tree(root, ix):
    root = Path(root)
    files = {}
    for p in sorted(root.rglob("*.swift")):
        files[str(p.relative_to(root))] = p.read_text(errors="replace")
    own = project_names(files)
    swiftui_files = [f for f, t in files.items() if re.search(r"^\s*import\s+SwiftUI\b", t, re.M)]
    results = {}
    for f in swiftui_files:
        results[f] = scan_file(f, files[f], ix, own)
    return files, swiftui_files, results, own


if __name__ == "__main__":
    import sys
    import swiftui_index
    ix = swiftui_index.build()
    files, sf, res, own = scan_tree(sys.argv[1], ix)
    print(len(files), "swift files;", len(sf), "import SwiftUI")
    from collections import Counter
    c = Counter()
    for f, items in res.items():
        for k, n, ln, ex in items:
            c[(k, n)] += 1
    for kind in ("wrapper", "combine", "type", "modifier", "member-call", "static", "implicit", "env-key"):
        rows = [(n, v) for (k, n), v in c.items() if k == kind]
        rows.sort(key=lambda r: -r[1])
        print("==", kind, len(rows), sum(v for _, v in rows))
        print("  ", rows[:70])
