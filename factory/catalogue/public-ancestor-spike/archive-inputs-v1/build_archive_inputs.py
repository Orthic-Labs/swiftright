#!/usr/bin/env python3
"""Build immutable F1 external-input mapping from pinned descriptors."""
from __future__ import annotations
import gzip, hashlib, json, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OWN = Path(__file__).resolve().parent
PREFIX = 'factory/catalogue/public-ancestor-spike/archive-inputs-v1/'
SDK = '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
TOOLCHAIN = '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain'
STAGE = ROOT / 'factory/catalogue/public-ancestor-spike/external-owner-capture/clang-nominal-import-v1/stage-manifest.json'
GUARD = ROOT / 'factory/catalogue/public-ancestor-spike/external-owner-capture/clang-owner-guard-v1/capture-inputs.json'
SWIFT_MAN = ROOT / 'factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-process-v2/archive-manifest.json'
DESTRUCTOR = ROOT / 'factory/catalogue/public-ancestor-spike/destructor-access-capture/archive-manifest.json'


def digest(p: Path):
    h = hashlib.sha256(); n = 0
    with p.open('rb') as f:
        while b := f.read(1 << 20): h.update(b); n += len(b)
    return n, h.hexdigest()

def clean_hash(x): return str(x).removeprefix('sha256:')

def add(specs, path, kind, bytes_, sha, role, source):
    sha = clean_hash(sha) if sha else None
    if path in specs:
        old = specs[path]
        if old['sha256'] != sha or (old['bytes'] is not None and bytes_ is not None and old['bytes'] != bytes_):
            raise SystemExit(f'conflicting descriptor for {path}: {old["bytes"]}/{old["sha256"]} vs {bytes_}/{sha}')
        if old['bytes'] is None and bytes_ is not None: old['bytes'] = bytes_
        old['roles'].append(role)
        old['provenance'].append(source)
    else:
        specs[path] = {'semanticPath': path, 'kind': kind, 'bytes': bytes_, 'sha256': sha,
                       'roles': [role], 'provenance': [source]}

def main():
    specs = {}
    stage = json.loads(STAGE.read_text())
    for d in stage['requiredExternalDependencies']:
        add(specs, d['path'], d['kind'], d.get('bytes'), d.get('sha256'), d['reason'],
            {'manifest': str(STAGE.relative_to(ROOT)), 'field': 'requiredExternalDependencies', 'path': d['path']})
    guard = json.loads(GUARD.read_text())
    for key, d in guard.items():
        if not isinstance(d, dict) or 'path' not in d: continue
        # Guard's physical source/header/modulemap/umbrella records are external inputs.
        if not (key.startswith(('source:', 'map:', 'umbrella:')) or key == 'source:Spatial.Base' or key == 'tool:sourcekitd'):
            continue
        add(specs, d['path'], 'file', d['bytes'], d['sha256'], key,
            {'manifest': str(GUARD.relative_to(ROOT)), 'field': key, 'path': d['path']})
    sw = json.loads(SWIFT_MAN.read_text())
    for d in sw['requiredExternalOrRepositoryRelativeDependencies']:
        p = d['path']
        if str(p).startswith('/'):
            add(specs, p, 'file', d['bytes'], d['sha256'], 'Swift 16 process prerequisite',
                {'manifest': str(SWIFT_MAN.relative_to(ROOT)), 'field': 'requiredExternalOrRepositoryRelativeDependencies', 'path': p})
    dm = json.loads(DESTRUCTOR.read_text())
    for d in dm['externalOrigins']:
        add(specs, d['origin'], 'file', None, d['sha256'], 'destructor-access source/tool prerequisite',
            {'manifest': str(DESTRUCTOR.relative_to(ROOT)), 'field': 'externalOrigins', 'archive': d['archive'], 'path': d['origin']})

    # Exact source snapshot checks are performed before archive materialization.
    live = {
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd'),
      '/usr/bin/xcrun': Path('/usr/bin/xcrun'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface'),
      '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface': Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface'),
    }
    for p, fp in live.items():
        if p not in specs: continue
        if not fp.exists(): raise SystemExit(f'missing live prerequisite: {p}')
        n, h = digest(fp)
        if specs[p]['bytes'] is not None and (n != specs[p]['bytes'] or h != specs[p]['sha256']):
            raise SystemExit(f'live prerequisite drift: {p}: {n}/{h}, expected {specs[p]["bytes"]}/{specs[p]["sha256"]}')
        specs[p]['observedLive'] = {'bytes': n, 'sha256': h}
        if specs[p]['bytes'] is None: specs[p]['bytes'], specs[p]['sha256'] = n, h

    # Explicit checked archives from prior cleared captures.
    existing = {
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc': 'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols/staging/swiftc.archive.gz',
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp': 'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols-process-v2/archive/tools/sourcekit-lsp',
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd': 'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols-process-v2/archive/tools/sourcekitd',
      '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle': 'factory/catalogue/public-ancestor-spike/destructor-access-capture/archive/tools/swift-demangle',
      '/usr/bin/xcrun': 'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols-process-v2/archive/tools/xcrun',
      '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface': 'factory/catalogue/public-ancestor-spike/destructor-access-capture/archive/inputs/SwiftUI.swiftinterface',
      '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface': 'factory/catalogue/public-ancestor-spike/destructor-access-capture/archive/inputs/SwiftUICore.swiftinterface',
      '/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/public-ancestor-v1/preliminary-reconstruction.json': 'factory/catalogue/public-ancestor-spike/destructor-access-capture/archive/inputs/preliminary-reconstruction.json',
    }
    # clang is intentionally compressed into this fresh folder.
    clang_path = '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'
    clang_archive = OWN / 'archive/tools/clang.archive.gz'
    if clang_path in specs:
        src = live[clang_path]
        if not clang_archive.exists():
            with clang_archive.open('wb') as out, src.open('rb') as inp:
                # gzip -n equivalent: mtime=0, no filename/comment.
                with gzip.GzipFile(fileobj=out, mode='wb', filename='', mtime=0) as gz:
                    shutil.copyfileobj(inp, gz, length=1 << 20)
        n, h = digest(clang_archive)
        with gzip.open(clang_archive, 'rb') as f:
            hh = hashlib.sha256(); total=0
            while b := f.read(1 << 20): hh.update(b); total += len(b)
        if (total, hh.hexdigest()) != (specs[clang_path]['bytes'], specs[clang_path]['sha256']): raise SystemExit('clang gzip decompressed digest mismatch')
        specs[clang_path]['archive'] = {'path': str(clang_archive.relative_to(ROOT)), 'compression': 'gzip', 'bytes': n, 'sha256': h, 'decompressedBytes': total, 'decompressedSha256': hh.hexdigest()}
    for p, ap in existing.items():
        if p not in specs: continue
        af = ROOT / ap
        if not af.exists(): raise SystemExit(f'missing checked archive: {ap}')
        n, h = digest(af)
        # Validate direct archives against semantic bytes/hash, except swiftc gzip.
        if p.endswith('/swiftc'):
            with gzip.open(af, 'rb') as f:
                hh=hashlib.sha256(); total=0
                while b:=f.read(1<<20): hh.update(b); total += len(b)
            if (total,hh.hexdigest()) != (specs[p]['bytes'],specs[p]['sha256']): raise SystemExit('swiftc archive mismatch')
            comp='gzip'; extra={'decompressedBytes':total,'decompressedSha256':hh.hexdigest()}
        else:
            # For inaccessible cache-origin, checked archive preimage supplies strict bytes.
            an, ah = digest(af)
            if specs[p]['bytes'] is None: specs[p]['bytes'] = an
            if (an,ah) != (specs[p]['bytes'], specs[p]['sha256']): raise SystemExit(f'checked archive mismatch: {ap}')
            comp='none'; extra={}
        specs[p]['archive'] = {'path': ap, 'compression': comp, 'bytes': n, 'sha256': h, **extra}
    # Copy missing SDK/source files into deterministic hash-prefixed names.
    for p, s in specs.items():
        if 'archive' in s or s['kind'] == 'directory': continue
        fp = Path(p)
        if not fp.exists():
            # Cache origins may only have approved archive preimages.
            raise SystemExit(f'unmapped inaccessible dependency: {p}')
        src_n, src_h = digest(fp)
        if (src_n,src_h) != (s['bytes'],s['sha256']): raise SystemExit(f'live input drift: {p}')
        s['observedLive'] = {'bytes': src_n, 'sha256': src_h}
        out = OWN / 'archive/inputs' / f'{s["sha256"][:16]}-{fp.name}'
        shutil.copyfile(fp, out)
        n,h = digest(out)
        if (n,h) != (s['bytes'],s['sha256']): raise SystemExit(f'copied input mismatch: {p}')
        s['archive'] = {'path': str(out.relative_to(ROOT)), 'compression': 'none', 'bytes': n, 'sha256': h}
    out = {'schema':'factory.public-ancestor.archive-input-mapping.v1','status':'frozen-inputs-only','sourceScope':{
      'nominalStage': str(STAGE.relative_to(ROOT)), 'nominalStageSha256': digest(STAGE)[1],
      'clangOwnerGuard': str(GUARD.relative_to(ROOT)), 'clangOwnerGuardSha256': digest(GUARD)[1],
      'swift16Manifest': str(SWIFT_MAN.relative_to(ROOT)), 'swift16ManifestSha256': digest(SWIFT_MAN)[1],
      'destructorManifest': str(DESTRUCTOR.relative_to(ROOT)), 'destructorManifestSha256': digest(DESTRUCTOR)[1]},
      'policy': {'archiveRoot': PREFIX, 'archivePathsRepositoryRelative':True,'maxArchiveBytes':100000000,'directoryPrerequisitesAreNotCopied':True,'noLiveCacheOrWholeSdkCopy':True},
      'directoryPrerequisites':[s for s in specs.values() if s['kind']=='directory'],
      'entries': sorted([s for s in specs.values() if s['kind']=='file'], key=lambda x:x['semanticPath'])}
    # remove internal observedLive from final? Retain it to bind build-time check.
    (OWN/'archive-input-mapping.json').write_text(json.dumps(out, indent=2, sort_keys=True)+'\n')
    print(json.dumps({'entries':len(out['entries']),'directories':len(out['directoryPrerequisites']),'mapping':str((OWN/'archive-input-mapping.json').relative_to(ROOT))},indent=2))
if __name__ == '__main__': main()
