"""Archive targeted synthetic controls; no native process or remote action."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent

def h(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()

def write(name, obj):
    (OUT/name).write_text(json.dumps(obj, indent=2, sort_keys=True)+'\n')

argv = [str(ROOT/'factory/.venv/bin/python'), '-m', 'unittest',
        'factory.gate.test_windows_exit_admission', '-v']
started = datetime.now(timezone.utc).isoformat()
child = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
stdout, stderr = child.communicate(timeout=60)
finished = datetime.now(timezone.utc).isoformat()
(OUT/'controls.stdout.bin').write_bytes(stdout)
(OUT/'controls.stderr.bin').write_bytes(stderr)
write('controls-process.json', {'kind':'synthetic-unit-controls-only', 'synthetic':True,
      'nativeQualification':False, 'argv':argv, 'cwd':str(ROOT), 'pid':child.pid,
      'startedAt':started, 'finishedAt':finished, 'exitCode':child.returncode,
      'tool': {'path':str(Path(argv[0]).resolve()),
               'hash':h(Path(argv[0]).resolve().read_bytes())},
      'stdoutHash':h(stdout), 'stderrHash':h(stderr),
      'sourceBindings':[{'path':name,'hash':h((ROOT/name).read_bytes())} for name in (
          'factory/gate/windows_exit_admission.py',
          'factory/gate/test_windows_exit_admission.py')]})
if child.returncode:
    sys.exit(child.returncode)
sys.path.insert(0,str(ROOT))
from factory.gate.test_windows_exit_admission import Fixture
fixture=Fixture()
write('synthetic-fixture.json', {'synthetic':True,'testOnly':True,
      'capture':fixture.capture, 'rawTextObjects':fixture.objects,
      'rawBytes':{name:raw.hex() for name,raw in fixture.raw.items()},
      'hostBytes':{name:raw.hex() for name,raw in fixture.host.items()},
      'runtimeBytes':{name:raw.hex() for name,raw in fixture.runtime.items()},
      'compilerBytes':fixture.compiler.hex()})
write('synthetic-structural-result.json', fixture.result())
write('report.json', {'kind':'windows-exit-admission-guard-control-review-v1',
      'status':'ready-for-independent-source-review', 'tests':11, 'exitCode':child.returncode,
      'syntheticFixturesOnly':True,'nativeQualifications':0,'remoteActions':0,
      'guardAPI':'windows_exit_admission_issues(capture, reader) -> list[str]',
      'coreWorkflowEdited':False,
      'faultFamilies':['legacy HasExited without kernel signal',
        'primary failure despite valid cleanup', 'nonzero/noninteger kernel wait',
        'PID/path/start/WM_CLOSE ownership', 'terminal stream count/completion/closure',
        'stream raw hashes/missing bytes', 'source/compile/exe/runtime/tool joins',
        'case/run/strict exit/duplicate row', 'reference coverage/path/hash/duplicate JSON',
        'direct label/caller-pass spoof'],
      'fixtureScope':'All mocked source/tool/exe/DLL/receipt bytes synthetic; no native qualification claim.'})
files = [Path('factory/gate/windows_exit_admission.py'),
         Path('factory/gate/test_windows_exit_admission.py')]
files += [p.relative_to(ROOT) for p in OUT.iterdir() if p.is_file() and p.name!='root-stage-manifest.json']
write('root-stage-manifest.json', {'kind':'windows-exit-admission-guard-stage-v1',
      'scope':'new guard/tests/owned audit evidence only',
      'files':[{'path':str(p),'hash':h((ROOT/p).read_bytes()),'bytes':(ROOT/p).stat().st_size}
               for p in sorted(files)]})
print(h((OUT/'root-stage-manifest.json').read_bytes()))
