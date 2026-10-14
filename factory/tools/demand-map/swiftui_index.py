"""Build an index of public SwiftUI API names from the SDK's .swiftinterface files.

The index drives the demand-map scan: a token in the Pulse notch source counts as a
SwiftUI API only if the pinned SDK declares it.  Pure standard library.
"""
import re
import subprocess
from pathlib import Path

DECL = re.compile(r'^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|open|package|nonisolated|final|indirect|static|class|mutating|nonmutating|override|convenience|required|prefix|postfix|distributed|borrowing|consuming|dynamic|unowned|weak|@inlinable|@usableFromInline|@_disfavoredOverload|@discardableResult|@available\([^)]*\))\s+)*')
TOP = re.compile(r'^(extension)\s+([\w:\.]+)|^(?:@\w+(?:\([^)]*\))?\s+)*(?:public |open |package )?(?:final )?(struct|class|enum|protocol|actor|typealias)\s+(\w+)')
KIND = re.compile(r'\b(struct|class|enum|protocol|actor|typealias)\s+(\w+)')
FUNC = re.compile(r'\b(?:func|var|let|case|init)\s+`?(\w+)`?')
CASE = re.compile(r'^\s*(?:indirect\s+)?case\s+(.+)$')


def sdk_path():
    return subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()


def interface_files(sdk):
    base = Path(sdk) / "System/Library/Frameworks"
    out = []
    for fw in ("SwiftUI", "SwiftUICore"):
        p = base / f"{fw}.framework/Modules/{fw}.swiftmodule/arm64e-apple-macos.swiftinterface"
        if p.exists():
            out.append(p)
    return out


MODULES = ("SwiftUICore", "SwiftUI", "Swift", "Foundation", "CoreFoundation", "CoreGraphics", "Combine")


def strip_module(name):
    name = name.replace("::", ".")
    parts = name.split(".")
    while len(parts) > 1 and parts[0] in MODULES:
        parts = parts[1:]
    return ".".join(parts)


def build(sdk=None):
    """Return dict: types{name:kind}, wrappers set, members{ctx:{name:set(kinds)}}, files[list]."""
    sdk = sdk or sdk_path()
    types, wrappers = {}, set()
    members = {}
    files = interface_files(sdk)
    for path in files:
        ctx = None          # top-level type being extended or declared
        nested = None
        pending_wrapper = False
        for raw in path.read_text(errors="replace").splitlines():
            if not raw.strip() or raw.lstrip().startswith("//"):
                continue
            indent = len(raw) - len(raw.lstrip())
            line = raw.strip()
            if "@propertyWrapper" in line and indent == 0:
                pending_wrapper = True
            if indent == 0:
                nested = None
                m = re.match(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:public |open |package )?(?:final )?(?:extension\s+([\w:\.<>]+)|(struct|class|enum|protocol|actor|typealias)\s+(\w+))', line)
                if line.startswith("extension") or (m and m.group(1)):
                    mm = re.match(r'^(?:@\w+\s+)*extension\s+([\w:\.]+)', line)
                    if mm:
                        ctx = strip_module(mm.group(1))
                    continue
                k = re.search(r'\b(struct|class|enum|protocol|actor|typealias)\s+(\w+)', line)
                if k and "public" in line.split(k.group(1))[0] + " public":
                    if ("public " in line) or ("open " in line):
                        ctx = k.group(2)
                        types.setdefault(ctx, k.group(1))
                        if pending_wrapper or "@propertyWrapper" in line:
                            wrappers.add(ctx)
                        pending_wrapper = False
                    else:
                        ctx = None
                continue
            if ctx is None:
                continue
            if indent == 2:
                k = re.search(r'\b(struct|class|enum|protocol|actor|typealias)\s+(\w+)', line)
                if k and ("public " in line):
                    nested = ctx + "." + k.group(2)
                    types.setdefault(nested, k.group(1))
                    continue
                nested = None
            if "public " not in line and not line.startswith("case "):
                continue
            target = nested if (nested and indent >= 4) else ctx
            c = CASE.match(raw)
            if c:
                for nm in re.findall(r'(\w+)(?:\([^)]*\))?', c.group(1)):
                    members.setdefault(target, {}).setdefault(nm, set()).add("case")
                continue
            f = re.search(r'\b(func|var|let)\s+`?(\w+)`?', line)
            if f:
                static = " static " in (" " + line)
                members.setdefault(target, {}).setdefault(f.group(2), set()).add(
                    ("static " if static else "") + f.group(1))
    return {"types": types, "wrappers": wrappers, "members": members,
            "files": [str(p) for p in files], "sdk": sdk}


if __name__ == "__main__":
    ix = build()
    print(len(ix["types"]), "types", len(ix["wrappers"]), "wrappers", len(ix["members"]), "member contexts")
    v = ix["members"].get("View", {})
    print("View members", len(v), [n for n in ("opacity", "frame", "padding", "overlay", "onHover") if n in v])
    print(sorted(ix["wrappers"]))
    print(ix["members"].get("Animation", {}).get("easeInOut"))
