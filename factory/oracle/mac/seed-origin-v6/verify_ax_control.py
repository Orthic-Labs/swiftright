#!/usr/bin/env python3
"""Verify auxiliary AXClient compiler receipt, source joins, & read-only preflight."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
from pathlib import Path

def digest(path: Path) -> str: return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
def fail(message: str) -> None: raise ValueError(message)
def instant(value: str): return datetime.datetime.fromisoformat(value.replace('Z','+00:00'))
def validate(root: Path) -> dict:
    root=root.resolve(); archive=json.loads((root/'auxiliary-ax-control/archive-map.json').read_text()); rows=archive.get('files'); isinstance(rows,list) and len(rows)==12 or fail('aux archive count')
    by_repo={}
    for row in rows:
        rel=row['repoPath']; rel not in by_repo or fail('duplicate aux path'); p=root/rel; p.is_file() or fail(f'missing aux file {rel}'); digest(p).removeprefix('sha256:')==row['sha256'] or fail(f'aux hash {rel}'); p.stat().st_size==row['bytes'] or fail(f'aux bytes {rel}'); by_repo[rel]=row
    binding=archive['sourceBindings']; isinstance(binding,list) and len(binding)==1 or fail('source binding count'); binding=binding[0]; source_archive=root/binding['archivePath']; source_input=Path(binding['sourceInputInternalPath']); source_work=Path(binding['receiptWorkPath']); source_archive.is_file() and source_input.is_file() and source_work.is_file() or fail('AX source files')
    digest(source_archive)==digest(source_input)==digest(source_work)==binding['sha256'] or fail('AX source bytes')
    receipt_row=by_repo['auxiliary-ax-control/evidence/ax-compiler-receipt.json']; receipt_path=Path(receipt_row['internalPath']); receipt_path.is_file() or fail('AX receipt missing'); digest(receipt_path).removeprefix('sha256:')==receipt_row['sha256'] or fail('AX receipt changed'); receipt=json.loads(receipt_path.read_text()); receipt['kind']=='swift-compiler-process-receipt' and receipt['status']=='SUCCESS' and receipt['sourceDrift'] is False or fail('AX receipt status/source')
    resolver=receipt['resolver']; resolver['argv']==['/usr/bin/xcrun','--find','swiftc'] and resolver['exitCode']==0 or fail('resolver argv/exit'); isinstance(resolver['pid'],int) and resolver['pid']>0 and resolver['pgid']==resolver['pid'] or fail('resolver pid'); instant(resolver['startedAtUtc'])<=instant(resolver['endedAtUtc']) or fail('resolver time')
    compiler=receipt['compiler']; compiler['argv'][:2]==['/usr/bin/xcrun','swiftc'] and compiler['argv'][-1]==str(source_work) and compiler['argv'][compiler['argv'].index('-o')+1]==compiler['outputBinary']['path'] or fail('AX compiler argv joins'); compiler['cwd']==str(source_work.parent) or fail('AX cwd'); compiler['exitCode']==0 and compiler['timedOut'] is False and compiler['realToolDrift'] is False or fail('AX compiler outcome'); isinstance(compiler['pid'],int) and compiler['pid']>0 and compiler['pgid']==compiler['pid'] or fail('AX compiler pid'); instant(compiler['startedAtUtc'])<=instant(compiler['endedAtUtc']) or fail('AX compiler time'); compiler['sourceBefore']['AXClient.swift']['path']==str(source_work) and compiler['sourceAfter']['AXClient.swift']['path']==str(source_work) or fail('AX receipt source path'); compiler['sourceBefore']['AXClient.swift']['sha256']==digest(source_archive)==compiler['sourceAfter']['AXClient.swift']['sha256'] or fail('AX receipt source hash'); compiler['outputBinary']['sha256']==digest(root/'auxiliary-ax-control/binary/f5-ax-client') and compiler['outputBinary']['bytes']==(root/'auxiliary-ax-control/binary/f5-ax-client').stat().st_size or fail('AX binary join')
    for path_key,hash_key in [('stdoutPath','stdoutHash'),('stderrPath','stderrHash')]: Path(compiler[path_key]).is_file() and digest(Path(compiler[path_key]))==compiler[hash_key] or fail(f'AX compiler stream {path_key}')
    for path_key,hash_key in [('stdoutPath','stdoutHash'),('stderrPath','stderrHash')]: Path(resolver[path_key]).is_file() and digest(Path(resolver[path_key]))==resolver[hash_key] or fail(f'AX resolver stream {path_key}')
    summary=json.loads((root/'auxiliary-ax-control/evidence/ax-control-summary.json').read_text()); summary['compilerStatus']=='SUCCESS' and summary['compilerExitCode']==0 and summary['compileAttempt']==1 and summary['retry'] is False or fail('AX summary'); summary['permissionRequests'] is False and summary['seedCaptureRun'] is False and summary['guiCaptureRun'] is False or fail('AX scope'); summary['compilerReceiptHash']==digest(root/'auxiliary-ax-control/evidence/ax-compiler-receipt.json') or fail('AX summary receipt hash'); summary['binaryHash']==compiler['outputBinary']['sha256'] or fail('AX summary binary hash'); summary['preflight']['permissionRequests'] is False or fail('AX preflight permission')
    preflight=json.loads((root/'auxiliary-ax-control/evidence/fresh-ax-preflight.stdout.txt').read_text()); preflight['permissionRequests'] is False or fail('raw preflight permission')
    pin=json.loads((root/'auxiliary-ax-control/dependency-pin.json').read_text()); pin['sourceSha256']==digest(source_archive) and pin['receiptSha256']==digest(root/'auxiliary-ax-control/evidence/ax-compiler-receipt.json') and pin['binarySha256']==digest(root/'auxiliary-ax-control/binary/f5-ax-client') or fail('aux dependency pin')
    return {'status':'PASS','compilerPid':compiler['pid'],'resolverPid':resolver['pid'],'compilerExit':0,'receiptHash':receipt_row['sha256'],'binaryHash':compiler['outputBinary']['sha256'],'sourceHash':digest(source_archive),'sourceBindings':1,'preflightAxTrusted':preflight.get('axTrusted'),'permissionRequests':False,'attempts':1}
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('root',type=Path); args=parser.parse_args()
    try: print(json.dumps(validate(args.root),sort_keys=True,indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
