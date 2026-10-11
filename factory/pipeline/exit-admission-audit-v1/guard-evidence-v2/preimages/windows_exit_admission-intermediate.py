"""Reader-backed Windows exit admission. This proves archive joins, never parity.

A capture's meta.conditions.windowsExitProof is {version:1,files:{role:{path,hash}}}.
Readers return exact archived bytes for safe relative semantic paths. Legacy captures
remain usable observationally; absent proof is an issue for qualified admission.
Plan sourceBindings resolve below host/; runtimeTree members below runtime/;
compiler bytes resolve at tool/compiler.bin. Hashes come from pinned raw inputs.
"""
from __future__ import annotations
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import PurePosixPath, PureWindowsPath
from factory.core.artifacts import canonical_hash

ROLES = frozenset(('outcome','observation','owned','close','plan','compile','witness',
                   'exe','renderer','runtimeReceipt','runtimeTree','stdout','stderr'))
TERMINAL_CLEANUP = frozenset(('already-signaled','signaled-after-exit-observation',
    'signaled-during-lookup','signaled-before-kill','signaled-during-kill',
    'killed-owned-handle-signaled'))
MANIFEST_DEPENDENCY = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"

def _production_compile_argv(request):
    """Exact production SwiftPM GUI host request, not an arbitrary argv whitelist."""
    if not isinstance(request,dict) or set(request)!={'kind','packagePath','scratchPath','compilerPath','target','configuration'}:
        raise ValueError('exact compiler request required')
    if request['kind']!='swiftpm-windows-gui-release/1' or request['target']!='windows-x86_64' or request['configuration']!='release':
        raise ValueError('unsupported compiler request target/configuration')
    for key in ('packagePath','scratchPath','compilerPath'):
        path=request[key]
        if not isinstance(path,str) or not path or any(c in path for c in ('"','\r','\n','\x00')) or not PureWindowsPath(path).is_absolute() or str(PureWindowsPath(path))!=path or '..' in PureWindowsPath(path).parts:
            raise ValueError('compiler request path invalid')
    package=PureWindowsPath(request['packagePath']);scratch=PureWindowsPath(request['scratchPath'])
    if package not in scratch.parents or scratch.name!='scratch':
        raise ValueError('compiler scratch must belong to host package')
    return ('build --package-path "'+request['packagePath']+'" --scratch-path "'+request['scratchPath']+
            '" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+MANIFEST_DEPENDENCY+
            '" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup')

def _safe_path(path):
    if not isinstance(path,str) or '\\' in path or ':' in path or path in ('','.','..'):
        return False
    parsed=PurePosixPath(path)
    return not parsed.is_absolute() and '..' not in parsed.parts and str(parsed)==path

def _hash(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()

def _integer(value, *, positive=False):
    return type(value) is int and (value > 0 if positive else value >= 0)

def _instant(value):
    if not isinstance(value,str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?(?:Z|[+-]\d\d:\d\d)',value):
        raise ValueError('owned/compile timestamp invalid')
    # Preserve Windows' seventh fractional digit; no floating time arithmetic.
    match=re.fullmatch(r'(.*?)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',value)
    base,fraction,zone=match.groups()
    parsed=datetime.fromisoformat(base+zone.replace('Z','+00:00')).astimezone(timezone.utc)
    delta=parsed-datetime(1970,1,1,tzinfo=timezone.utc)
    return (delta.days*86400+delta.seconds)*10_000_000+int((fraction or '').ljust(7,'0'))

def _empty_error(value):
    return value is None or (type(value) is str and value=='')

def _json(raw):
    def pairs(rows):
        result = {}
        for key,value in rows:
            if key in result:
                raise ValueError('duplicate raw JSON key')
            result[key]=value
        return result
    def invalid(_):
        raise ValueError('nonfinite raw JSON constant')
    return json.loads(raw.decode('utf-8-sig'), object_pairs_hook=pairs, parse_constant=invalid)

def verify_windows_exit_admission(capture, *, read_bytes):
    """Return issues + exact capture/raw hashes; caller owns reader confinement.

    Success is exit-proof structural admission only. A mandatory F10 callback
    must call this against its own archived reader, rather than accept metadata
    booleans or nativeParity labels supplied by a caller.
    """
    consumed={}
    capture_hash=None
    def require(value,message):
        if not value:
            raise ValueError(message)
    try:
        require(isinstance(capture,dict),'capture object required')
        capture_hash=canonical_hash(capture)
        require(capture.get('platform')=='windows','Windows platform required')
        meta=capture['meta'];conditions=meta['conditions'];run=meta['run']
        require(_integer(run,positive=True),'run must be positive exact integer')
        proof=conditions.get('windowsExitProof')
        require(isinstance(proof,dict) and type(proof.get('version')) is int and proof['version']==1,'reader-backed exit proof missing/version invalid')
        bindings=proof['files'];require(isinstance(bindings,dict) and set(bindings)==ROLES,'exact exit proof roles required')
        paths=set();data={}
        for role,ref in bindings.items():
            require(isinstance(ref,dict) and set(ref)=={'path','hash'},'raw proof reference shape')
            path=ref['path'];require(_safe_path(path) and path not in paths,'raw proof path escape/duplicate')
            paths.add(path);raw=read_bytes(path);require(type(raw) is bytes,'reader exact bytes required')
            require(isinstance(ref['hash'],str) and re.fullmatch(r'sha256:[0-9a-f]{64}',ref['hash']) and _hash(raw)==ref['hash'],'raw proof hash mismatch')
            consumed[role]={'path':path,'hash':_hash(raw)};data[role]=raw
        obj={role:_json(data[role]) for role in ROLES-{'witness','exe','renderer','stdout','stderr'}}
        observations=obj['observation']
        rows=observations if isinstance(observations,list) else [observations]
        require(all(isinstance(row,dict) for row in rows),'raw observation rows')
        matches=[row for row in rows if type(row.get('index')) is int and row['index']==run]
        require(len(matches)==1,'exact observation run missing/duplicated');row=matches[0]
        require(_integer(row.get('exitCode')) and row['exitCode']==0 and row.get('hostValid') is True,'successful exact exitCode/hostValid required')
        outcome,owned,close,plan,build,rr,tree=(obj[x] for x in ('outcome','owned','close','plan','compile','runtimeReceipt','runtimeTree'))
        require(_empty_error(outcome['primaryError']) and outcome['streamErrors']==[],'primary or stream failure forbids qualified capture')
        require(canonical_hash(outcome['ownedIdentity'])==canonical_hash(owned),'owned process identity mismatch')
        require(_integer(owned['pid'],positive=True) and isinstance(owned['path'],str) and owned['path'] and isinstance(owned['startedAt'],str) and owned['startedAt'],'owned PID/path/start required')
        require(owned['path']==build['exePath'],'compile/owned executable path mismatch')
        owned_start=_instant(owned['startedAt'])
        require(canonical_hash(row['ownedIdentity'])==canonical_hash(owned),'observation/owned process identity mismatch')
        require(_integer(close['pid'],positive=True) and close['pid']==owned['pid'] and _integer(close['hwnd'],positive=True) and type(close['message']) is int and close['message']==16 and close['messageName']=='WM_CLOSE' and close['posted'] is True and close['activationRequested'] is False,'owned WM_CLOSE proof invalid')
        require(_instant(close['at'])>=owned_start,'WM_CLOSE precedes owned process')
        require(type(row['hwnd']) is int and row['hwnd']==close['hwnd'],'observation/WM_CLOSE HWND mismatch')
        cleanup=outcome['cleanup']
        require(cleanup['exitCertification']=='retained-kernel-handle' and cleanup['kernelExitSignaled'] is True and cleanup['confirmedOwnedExit'] is True and type(cleanup['kernelWaitResult']) is int and cleanup['kernelWaitResult']==0 and type(cleanup['status']) is str and cleanup['status'] in TERMINAL_CLEANUP and _empty_error(cleanup['error']),'terminal retained kernel signal0 required; HasExited alone insufficient')
        source=_hash(data['witness']);exe=_hash(data['exe']);renderer=_hash(data['renderer'])
        require(capture['provenance']['sourceHash']==conditions['actualSourceHash']==plan['sourceHash']==row['sourceHash']==outcome['sourceHash']==build['sourceHash']==source,'Witness source identity mismatch')
        require(capture['case']==plan['case']==row['case'],'case identity mismatch')
        require(capture['meta']['host']['hash']==conditions['actualHostExecutableHash']==exe and 'sha256:'+row['exeSha256']==exe and 'sha256:'+build['exeSha256']==exe and 'sha256:'+outcome['exeHash']==exe,'actual executable bytes mismatch')
        require(capture['tuple']['rendererHash']==conditions['actualRendererHash']==renderer and 'sha256:'+row['rendererSha256']==renderer and 'sha256:'+build['rendererSha256']==renderer,'actual renderer bytes mismatch')
        require(build['planSha256']==consumed['plan']['hash'].removeprefix('sha256:') and outcome['compileReceiptHash']==consumed['compile']['hash'].removeprefix('sha256:'),'compile/plan raw join')
        require(type(build['exitCode']) is int and build['exitCode']==0 and build['timedOut'] is False and build['ownedExited'] is True,'compile failure')
        require(_integer(build['pid'],positive=True) and isinstance(build['argv'],str) and build['argv'] and isinstance(build['cwd'],str) and build['cwd'],'compile process/argv/cwd identity missing')
        request=plan['compileRequest'];expected_argv=_production_compile_argv(request)
        require(build['argv']==expected_argv and build['cwd']==request['packagePath'],'production compiler argv/cwd mismatch')
        require(build['compilerPath']==request['compilerPath']==plan['compilerPath'],'production compiler path mismatch')
        require(build['target']==request['target'] and build['configuration']==request['configuration'],'production compiler target/configuration mismatch')
        expected_exe=str(PureWindowsPath(request['scratchPath'])/'out'/'Products'/'Release-windows-x86_64'/'FactoryProbe.exe')
        require(build['exePath']==expected_exe,'production compiler output path mismatch')
        require(_instant(build['startedAt'])<=_instant(build['processStartedAt'])<=_instant(build['finishedAt'])<=owned_start,'compile/owned process chronology invalid')
        require(_empty_error(build['error']) and _empty_error(build['cleanupError']),'compile process/cleanup error')
        require('sha256:'+build['rendererSha256']=='sha256:'+plan['rendererSha256'],'plan renderer identity mismatch')
        require(re.fullmatch(r'[0-9a-f]{64}',build['compilerHash']) is not None and build['compilerHash']==plan['compilerHash'].removeprefix('sha256:'),'compile tool identity mismatch')
        compiler=read_bytes('tool/compiler.bin')
        require(type(compiler) is bytes and _hash(compiler)=='sha256:'+build['compilerHash'],'compiler bytes mismatch')
        consumed['compiler']={'path':'tool/compiler.bin','hash':_hash(compiler)}
        # Plan-bound host files use a fixed archive namespace, never remote paths.
        host_bindings=plan['sourceBindings']
        require(isinstance(host_bindings,list) and host_bindings,'host source bindings missing')
        host_paths=set()
        for binding in host_bindings:
            path=binding['path'];require(_safe_path(path) and path not in host_paths,'host source path unsafe/duplicate')
            host_paths.add(path);archive_path='host/'+path
            require(archive_path not in paths,'host/raw proof path collision')
            raw=read_bytes(archive_path);require(type(raw) is bytes and _hash(raw)==binding['sha256'],'host source bytes mismatch')
            consumed['host:'+path]={'path':archive_path,'hash':_hash(raw)}
        require('Package.swift' in host_paths and 'Sources/FactoryProbe/Witness.swift' in host_paths and 'Sources/FactoryProbe/main.swift' in host_paths,'host package/main/Witness binding missing')
        require(next(x['sha256'] for x in host_bindings if x['path']=='Sources/FactoryProbe/Witness.swift')==source,'host/Witness source join')
        require(rr['sourceCommit']==plan['runtimeSourceCommit']==row['runtimeSourceCommit']==build['runtimeSourceCommit']==capture['tuple']['runtimeCommit'],'runtime commit identity mismatch')
        require(rr['sourceTreeHash']==plan['runtimeSourceTreeHash']==row['runtimeSourceTreeHash']==build['runtimeSourceTreeHash']==canonical_hash(tree),'runtime tree identity mismatch')
        require(plan['runtimeSourceReceiptHash']==consumed['runtimeReceipt']['hash'] and plan['runtimeSourceTreeFileHash']==consumed['runtimeTree']['hash'],'runtime raw receipt/tree join')
        require(isinstance(tree,list) and tree,'runtime source tree missing')
        runtime_paths=set()
        for binding in tree:
            path=binding['path'];require(_safe_path(path) and path not in runtime_paths,'runtime source path unsafe/duplicate')
            runtime_paths.add(path);archive_path='runtime/'+path
            require(archive_path not in paths,'runtime/raw proof path collision')
            raw=read_bytes(archive_path);require(type(raw) is bytes and _hash(raw)==binding['sha256'],'runtime source bytes mismatch')
            consumed['runtime:'+path]={'path':archive_path,'hash':_hash(raw)}
        require('Package.swift' in runtime_paths and any(x.startswith('Sources/SwiftRightRuntime/') for x in runtime_paths),'runtime package/source coverage missing')
        require(conditions['rawReceiptHash']==capture['meta']['clock']['correlationHash']==consumed['observation']['hash'],'observation/clock raw join')
        raw_files=row['files'];require(isinstance(raw_files,list) and raw_files,'observation raw file bindings required')
        raw_map={}
        for ref in raw_files:
            require(isinstance(ref,dict) and _safe_path(ref.get('path')) and ref['path'] not in raw_map,'observation file unsafe/duplicate')
            expected='sha256:'+ref['sha256']
            raw=read_bytes(ref['path'])
            require(type(raw) is bytes and _hash(raw)==expected,'observation raw file bytes mismatch')
            if 'bytes' in ref:
                require(_integer(ref['bytes']) and ref['bytes']==len(raw),'observation raw file size mismatch')
            raw_map[ref['path']]=expected
        for role in ('outcome','owned','close','stdout','stderr'):
            ref=consumed[role];require(raw_map.get(ref['path'])==ref['hash'],'observation missing/misbound exit raw file')
        streams=outcome['rawStreams'];require(isinstance(streams,list) and len(streams)==2 and {s['name'] for s in streams}=={'stdout','stderr'},'exact two terminal streams required')
        require(outcome['rawHashesQualification']=='sealed-raw','partial stream hashes cannot qualify')
        for stream in streams:
            require(all(stream[k] is True for k in ('copyCompleted','destinationClosed','sealed','taskIsCompleted')) and all(stream[k] is False for k in ('taskIsFaulted','taskIsCanceled')) and stream['taskStatus']=='RanToCompletion' and stream['closureTaskStatus']=='RanToCompletion' and stream['taskException']=='' and stream['hashQualification']=='sealed-raw','terminal sealed stream required')
            closure=stream['closure'];require(all(closure[k] is True for k in ('flushCompleted','destinationClosed','completedWithinDeadline')) and closure['deadlineExpired'] is False and closure['error']=='','stream closure failed')
            name=stream['name'];state=outcome['rawHashStates'][name]
            require(state['qualification']=='sealed-raw' and not state['error'] and 'sha256:'+state['sha256']==consumed[name]['hash'] and 'sha256:'+outcome[name+'Sha256']==consumed[name]['hash'],'sealed stream raw byte hash mismatch')
        issues=[]
    except (ValueError,TypeError,KeyError,OSError,UnicodeError,AttributeError,OverflowError) as exc:
        issues=[str(exc)]
    evidence={'kind':'windows-exit-admission/1','captureHash':capture_hash,'rawInputs':consumed,'issues':issues}
    return {'status':'pass' if not issues else 'blocked','issues':issues,'captureHash':capture_hash,'evidenceHash':canonical_hash(evidence),'evidence':evidence,'nativeParityGranted':False}


def make_windows_exit_admission(reader_factory):
    """F10 callback: reader_factory(capture) gives archive-owned read_bytes(path)."""
    def callback(*, captures, **_):
        results=[]
        for capture in captures:
            if capture.get('platform')=='windows':
                try:
                    result=verify_windows_exit_admission(capture,read_bytes=reader_factory(capture))
                except (OSError,ValueError,TypeError,KeyError) as exc:
                    result={'status':'blocked','issues':[str(exc)],'captureHash':canonical_hash(capture)}
                results.append(result)
        issues=[f"{r['captureHash']}: {issue}" for r in results for issue in r['issues']]
        if not results:
            issues.append('Windows exit admissions unavailable')
        return {'status':'blocked' if issues else 'pass','issues':issues,'captureHashes':sorted(r['captureHash'] for r in results),'results':results,'evidenceHash':canonical_hash(results),'nativeParityGranted':False}
    return callback


def windows_exit_admission_issues(capture, reader):
    """Mandatory origin guard: reader(safe relative proof path) -> exact bytes.

    Reader must resolve only capture-bound archive objects. This function never
    reads live paths or accepts caller-provided pass/verified labels.
    """
    return verify_windows_exit_admission(capture, read_bytes=reader)['issues']
