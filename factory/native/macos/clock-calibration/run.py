"""Build/run bounded headless calibration on internal disk; preserve exact inputs."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
INTERNAL = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/clock-calibration')

def reference(path):
    path = Path(path)
    return {'path': str(path), 'hash': 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()}

def main():
    out = HERE / 'evidence' / str(uuid.uuid4())
    out.mkdir(parents=True)
    work = INTERNAL / str(uuid.uuid4())
    work.mkdir(parents=True)
    assert work.resolve().is_relative_to(INTERNAL.resolve())
    source = work / 'ClockCalibration.swift'
    source.write_bytes((HERE / source.name).read_bytes())
    binary = work / 'clock-calibration'
    build = subprocess.run(['/usr/bin/xcrun', 'swiftc', '-O', str(source), '-o', str(binary)], capture_output=True, timeout=60)
    (out / 'build.stdout.txt').write_bytes(build.stdout)
    (out / 'build.stderr.txt').write_bytes(build.stderr)
    if build.returncode:
        raise RuntimeError('headless build failed')
    raw = out / 'raw.jsonl'
    raw.touch(exist_ok=False)
    run = subprocess.run([str(binary), str(raw)], capture_output=True, timeout=20)
    (out / 'run.stdout.txt').write_bytes(run.stdout)
    (out / 'run.stderr.txt').write_bytes(run.stderr)
    sdk = Path(subprocess.check_output(['/usr/bin/xcrun', '--show-sdk-path'], text=True).strip())
    header = sdk / 'System/Library/Frameworks/CoreMedia.framework/Headers/CMSync.h'
    support = {'header': reference(header), 'lineRanges': [[144, 178], [36, 49]],
               'semantics': {'hostClock': 'Uses mach_absolute_time, represented with large integer timescale.',
                             'convertHostToSystem': 'Scale conversion, not clock conversion; native mach units.',
                             'makeHostFromSystem': 'Converts native units to large integer CMTime timescale.'},
               'roundingGuarantee': 'Header does not specify rounding direction or maximum round-trip error.'}
    (out / 'sdk-support.json').write_text(json.dumps(support, indent=2, sort_keys=True) + '\n')
    receipt = {'kind': 'headless-host-clock-calibration', 'scope': 'independent observational scale conversion control',
               'recordedAt': datetime.now(timezone.utc).isoformat(), 'nativeSource': reference(source),
               'nativeBinary': reference(binary), 'launcher': reference(__file__), 'raw': reference(raw),
               'sdkSupport': reference(out / 'sdk-support.json'), 'exit': run.returncode,
               'runTimeoutSeconds': 20, 'GUIOrPermissionAPIs': False,
               'system': subprocess.check_output(['/usr/bin/sw_vers'], text=True),
               'toolchain': subprocess.check_output(['/usr/bin/xcrun', 'swiftc', '--version'], text=True)}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(out)
    if run.returncode:
        raise RuntimeError('headless calibration failed')

if __name__ == '__main__':
    main()
