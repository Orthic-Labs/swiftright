#!/usr/bin/env python3
"""Capture whole pinned Swift & Foundation interface SourceKit indexes."""
from __future__ import annotations
import hashlib, json, re, shlex, shutil, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TC = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
TARGET = "arm64-apple-macosx27.0"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
MODULES = {
    "Swift": Path("usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"),
    "Foundation": Path("System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"),
}
TARGETS = {
    "Swift": [("Optional", "enum", 16948), ("Never", "enum", 17607), ("Float", "struct", 39669), ("Double", "struct", 40283), ("Int", "struct", 45246), ("Int8", "struct", 41368), ("Int16", "struct", 42329), ("Int32", "struct", 43290), ("Int64", "struct", 44259), ("UInt", "struct", 44762), ("UInt8", "struct", 40905), ("UInt16", "struct", 41864), ("UInt32", "struct", 42825), ("UInt64", "struct", 43787), ("RangeReplaceableCollection", "protocol", 18661), ("MutableCollection", "protocol", 15531)],
    "Foundation": [("AttributedString", "struct", 74), ("AttributeScopes", "enum", 1048), ("FormatStyle", "protocol", 8471), ("AttributeDynamicLookup", "enum", 810)],
}

def sha(v: bytes | str) -> str:
    if isinstance(v, str): v = v.encode()
    return "sha256:" + hashlib.sha256(v).hexdigest()
def fsha(p: Path) -> str: return sha(p.read_bytes())
def rel(p: Path) -> str: return str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)
def tool(p: Path) -> dict: return {"path": str(p), "sha256": fsha(p)}

def parse_headers(path: Path) -> tuple[str, list[str], str, list[str]]:
    rows = path.read_text(encoding="utf-8", errors="replace").splitlines()
    main = [x for x in rows if x.startswith("// swift-module-flags:")]
    ign = [x for x in rows if x.startswith("// swift-module-flags-ignorable:")]
    if len(main) != 1 or len(ign) != 1: raise RuntimeError(f"header rows: {path}")
    return main[0], shlex.split(main[0].split(":", 1)[1].strip()), ign[0], shlex.split(ign[0].split(":", 1)[1].strip())

def transform(tokens: list[str]) -> tuple[list[str], list[dict], list[dict]]:
    kept, removed, forwarded = [], [], []
    i = 0
    while i < len(tokens):
        if tokens[i] in {"-target", "-target-variant", "-target-arch-variant"}:
            removed.append({"flag": tokens[i], "value": tokens[i + 1] if i + 1 < len(tokens) else None}); i += 2; continue
        token = tokens[i]
        if token == "-target-min-inlining-version" and i + 1 < len(tokens):
            value = tokens[i + 1]
            kept += ["-Xfrontend", token, "-Xfrontend", value]
            forwarded.append({"flag": token, "value": value, "forwardedAs": ["-Xfrontend", token, "-Xfrontend", value], "reason": "frontend-only-header-option"})
            i += 2
            continue
        if token in {"-enable-objc-interop", "-formal-cxx-interoperability-mode=off", "-strict-memory-safety", "-enable-lexical-lifetimes=false", "-parse-stdlib", "-disable-objc-attr-requires-foundation-module", "-target-min-inlining-version", "-enforce-exclusivity=unchecked"}:
            kept += ["-Xfrontend", token]; forwarded.append({"flag": token, "forwardedAs": ["-Xfrontend", token], "reason": "frontend-only-header-option"})
        else: kept.append(token)
        i += 1
    return kept, removed, forwarded

def request_text(source: Path, args: list[str]) -> str:
    q = json.dumps
    return "{\n key.request: source.request.indexsource,\n key.sourcefile: " + q(str(source)) + ",\n key.compilerargs: [ " + ", ".join(q(x) for x in args) + " ]\n}\n"

def records(raw: str) -> list[tuple[str, str, str, int, int]]:
    pat = re.compile(r"key\.kind: (source\.lang\.swift\.decl\.[^,\n]+),\n\s+key\.name: \"([^\"]*)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [(k, n, u, int(line), int(col)) for k, n, u, line, col in pat.findall(raw)]

def summarize(raw: str) -> dict:
    rs = records(raw); pairs = [(line, col, name, kind, usr) for kind, name, usr, line, col in rs]
    nominal = {"Swift": 0, "Foundation": 0, "other": 0}; variables = {"Swift": 0, "Foundation": 0, "other": 0}
    for kind, _, usr, _, _ in rs:
        bucket = "Swift" if usr.startswith("s:5Swift") else "Foundation" if usr.startswith("s:10Foundation") else "other"
        if any(x in kind for x in (".struct", ".class", ".enum", ".protocol", ".extension")): nominal[bucket] += 1
        if ".var." in kind: variables[bucket] += 1
    return {"recordDenominator": len(rs), "publicEffectiveAccessFieldCount": raw.count("key.effective_access: source.decl.effective_access.public"), "publicAttributeFieldCount": raw.count("key.attribute: source.decl.attribute.public"), "physicalPositionNameKindUsrPairs": {"denominator": len(pairs), "unique": len(set(pairs)), "duplicatePairCount": len(pairs) - len(set(pairs))}, "nominalUsrPrefixCounts": nominal, "varUsrPrefixCounts": variables, "declarationKinds": sorted({x[0] for x in rs})}

def target_facts(module: str, raw: str) -> list[dict]:
    lines = raw.splitlines(); result = []
    for name, expected_kind, expected_line in TARGETS[module]:
        found = []
        for i, line in enumerate(lines):
            if not re.match(r"^\s+key\.kind: source\.lang\.swift\.decl\.", line): continue
            indent = len(line) - len(line.lstrip())
            end = next(j for j in range(i + 1, len(lines)) if len(lines[j]) - len(lines[j].lstrip()) == indent - 2 and lines[j].strip() in {"},", "}"})
            block = "\n".join(lines[i:end + 1])
            m = re.search(r"key\.kind: (source\.lang\.swift\.decl\.[^,\n]+),\n\s+key\.name: \"([^\"]*)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)", block)
            if m and m.group(2) == name and int(m.group(4)) == expected_line: found.append((i, end, block, m))
        if len(found) != 1: raise RuntimeError(f"target record {module}.{name} matches={len(found)}")
        start, end, block, m = found[0]
        result.append({"name": name, "expectedKind": expected_kind, "kind": m.group(1).removeprefix("source.lang.swift.decl."), "usr": m.group(3), "line": int(m.group(4)), "column": int(m.group(5)), "effectiveAccess": "public" if "key.effective_access: source.decl.effective_access.public" in block else "unknown", "enclosingNominalPath": [], "rawBlockLineSpan": [start + 1, end + 1], "rawBlockSha256": sha(block), "rawRecordStatus": "exact-physical-source-position-name-kind-usr"})
    return result

def capture_module(module: str, source: Path) -> dict:
    raw_flag, source_flags, raw_ign, ign_flags = parse_headers(source)
    main, removed, forwarded = transform(source_flags)
    ign, removed_ign, forwarded_ign = transform(ign_flags)
    args = [str(source), *main, *ign, "-sdk", str(SDK), "-target", TARGET]
    request = HERE / f"requests/{module}.yaml"; request.parent.mkdir(exist_ok=True)
    request.write_text(request_text(source, args), encoding="utf-8")
    preimage = HERE / f"attempts/{module}.request.preimage.yaml"; preimage.parent.mkdir(exist_ok=True); shutil.copyfile(request, preimage)
    out = HERE / f"raw/{module}.index.txt"; err = HERE / f"receipts/{module}.stderr"; out.parent.mkdir(exist_ok=True); err.parent.mkdir(exist_ok=True)
    argv = ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request)]
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, check=False)
    out.write_bytes(result.stdout); err.write_bytes(result.stderr)
    attempt = HERE / f"attempts/{module}.response.stdout"; attempt.write_bytes(result.stdout)
    (HERE / f"attempts/{module}.response.stderr").write_bytes(result.stderr)
    raw_text = result.stdout.decode("utf-8", errors="replace")
    return {"module": module, "source": {"path": str(source), "sha256": fsha(source)}, "headerFlags": {"rawRows": {"swiftModuleFlags": raw_flag, "swiftModuleFlagsIgnorable": raw_ign}, "parsed": {"swiftModuleFlags": source_flags, "swiftModuleFlagsIgnorable": ign_flags}, "removedTargetFlags": removed + removed_ign, "forwardedFrontendFlags": forwarded + forwarded_ign, "compilerArgs": args, "productionTarget": TARGET, "sdkAppended": str(SDK)}, "request": {"path": rel(request), "preimagePath": rel(preimage), "sha256": fsha(request), "preimageSha256": fsha(preimage), "bytes": request.stat().st_size}, "process": {"argv": argv, "cwd": str(ROOT), "exit": result.returncode, "stdout": {"path": rel(out), "sha256": fsha(out), "bytes": out.stat().st_size}, "stderr": {"path": rel(err), "sha256": fsha(err), "bytes": err.stat().st_size}, "attemptStdoutPath": rel(attempt)}, "summary": summarize(raw_text), "targetRecords": target_facts(module, raw_text) if result.returncode == 0 else [], "failedPreimage": {"stdout": rel(attempt), "stderr": rel(HERE / f"attempts/{module}.response.stderr")}}

def main() -> None:
    if fsha(LINK) != EXPECTED_LINK: raise RuntimeError("immutable836 changed")
    out = {"kind": "f1-external-owner-header-index-swift-foundation", "version": 1, "status": "raw-facts-only-no-eligibility-conclusion", "immutableLink": {"path": rel(LINK), "sha256": fsha(LINK)}, "sdk": str(SDK), "target": TARGET, "toolchain": {"swiftc": tool(TC / "usr/bin/swiftc"), "sourcekitLsp": tool(TC / "usr/bin/sourcekit-lsp"), "sourcekitd": tool(TC / "usr/lib/sourcekitd.framework/Versions/A/sourcekitd")}, "modules": []}
    for name, relsource in MODULES.items(): out["modules"].append(capture_module(name, SDK / relsource))
    (HERE / "swift-foundation-index-evidence.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"modules": [{"module": x["module"], "exit": x["process"]["exit"], **x["summary"]} for x in out["modules"]]}, indent=2))

if __name__ == "__main__": main()
