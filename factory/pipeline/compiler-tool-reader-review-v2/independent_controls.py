"""Offline archive-only extraction review; archived tools never executed."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import sys
import tempfile
from factory.pipeline.reader_config import load_origin_reader_config

ROOT = Path.cwd()
OWN = ROOT / 'factory/pipeline/compiler-tool-reader-review-v2'
ARCHIVE = ROOT / 'factory/oracle/mac/compiler-tool-archive-v1'
CACHE = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/compiler-tool-reader-review-v2')
CACHE.mkdir(parents=True, exist_ok=True)
assert not CACHE.resolve().is_relative_to(Path('/Volumes/D'))
assert CACHE.stat().st_dev != ROOT.stat().st_dev
scratch = Path(tempfile.mkdtemp(prefix='offline-', dir=CACHE))
blocked = {'/usr/bin/xcrun', '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc', '/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend'}
reads = []
def audit(event, args):
    if event == 'open' and isinstance(args[0], (str, bytes, os.PathLike)):
        value = os.fsdecode(args[0])
        reads.append(value)
        if value in blocked:
            raise AssertionError('Forbidden current tool read: ' + value)
sys.addaudithook(audit)
spec = importlib.util.spec_from_file_location('frozen_extractor', OWN / 'archive_tool_bytes-reviewed.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
# Frozen exact helper bytes with immutable archive roots restored explicitly.
module.HERE = ARCHIVE
module.V1 = ARCHIVE.parent / 'seed-origin-actual-v1'
module.archive_bytes.__kwdefaults__['archive_root'] = ARCHIVE
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
result = {'sourceSha256': digest(OWN/'archive_tool_bytes-reviewed.py'), 'scratch': str(scratch), 'scratchDevice': scratch.stat().st_dev, 'repositoryDevice': ROOT.stat().st_dev, 'toolExecutions': 0}
try:
    sys.argv = [str(OWN/'archive_tool_bytes-reviewed.py'), '--output-dir', str(scratch)]
    assert module.main() == 0
    extracted = []
    for name in ('xcrun','swift-frontend'):
        path = scratch/name
        extracted.append({'name':name,'bytes':path.stat().st_size,'sha256':digest(path),'mode':oct(stat.S_IMODE(path.stat().st_mode))})
    result['extracted'] = extracted
    for name in ('reader_config.json','verification-receipt.json'):
        shutil.copyfile(scratch/name, OWN/('actual-'+name))
    reader = load_origin_reader_config(scratch/'reader_config.json')
    result['generatedConfigLoader'] = {'accepted':True,'versionExactInteger':type(module.reader_config()['version']) is int}
    aliases=[]
    for logical in ('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc','/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend'):
        data=reader(capture={'platform':'macos'},reference={'path':logical,'sha256':module.SHA_FRONTEND,'bytes':173118384})
        aliases.append({'logicalPath':logical,'bytes':len(data),'sha256':module.digest(data)})
        del data
    result['actualAliasReads']=aliases
    path = scratch/'xcrun'; original=(ARCHIVE/'tools/xcrun').read_bytes()
    result['exactReuse0644'] = module.write_exact(path, original)
    path.chmod(0o755); rejected=False
    try:module.write_exact(path, original)
    except ValueError:rejected=True
    assert rejected
    result['reuse0755']={'rejected':rejected,'modePreserved':oct(stat.S_IMODE(path.stat().st_mode))}
    path.chmod(0o4644)
    try:action=module.write_exact(path, original)
    except ValueError:action='REJECTED'
    result['specialModeProbe']={'action':action,'actualMode':oct(stat.S_IMODE(path.stat().st_mode))}
    divergent = scratch/'divergent';divergent.write_bytes(b'existing')
    try: module.write_exact(divergent,b'different')
    except ValueError: result['divergentCollision']={'rejected':True,'preserved':divergent.read_bytes()==b'existing'}
    else: raise AssertionError('Divergent overwrite permitted')
    bad = scratch/'bool-config.json'; config=module.reader_config();config['version']=True;bad.write_text(json.dumps(config))
    try:load_origin_reader_config(bad)
    except ValueError:result['booleanConfigVersionRejected']=True
    else:raise AssertionError('Boolean version accepted')
finally:
    shutil.rmtree(scratch)
    result['scratchRemoved'] = not scratch.exists()
    result['currentToolReads'] = sum(path in blocked for path in reads)
    result['readAuditPaths'] = sorted(set(reads))
    (OWN/'control-result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='readAuditPaths'},indent=2))
