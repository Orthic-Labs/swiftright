from pathlib import Path
import tempfile,json,copy,sys,hashlib,importlib.util
ROOT=Path(__file__).resolve().parents[4];sys.path.insert(0,str(ROOT))
from factory.gate.test_mac_origin_admission import OriginFixture
spec=importlib.util.spec_from_file_location('reviewed_guard',Path(__file__).parent/'source-snapshot-v4/mac_origin_admission.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
results=[]
def probe(name,fn):
 with tempfile.TemporaryDirectory() as p:
  f=OriginFixture(Path(p));assert not g.mac_origin_admission_issues(f.capture,f.reader)
  fn(f)
  try:issues=g.mac_origin_admission_issues(f.capture,f.reader);results.append({'fault':name,'issues':issues,'incorrectlyAccepted':not issues})
  except Exception as e:results.append({'fault':name,'exception':type(e).__name__+': '+str(e)})
def mutate(f,fn):fn(f);f.refresh_receipt()
probe('missing-compiled-adapter',lambda f:mutate(f,lambda f:(f.receipt['compiler']['sourceBefore'].pop('CaptureHost.swift'),f.receipt['compiler']['sourceAfter'].pop('CaptureHost.swift'),f.receipt['compiler']['argv'].pop())))
probe('extra-unbound-source-argv',lambda f:mutate(f,lambda f:f.receipt['compiler']['argv'].append('/unbound/Other.swift')))
probe('compiler-before-resolver',lambda f:mutate(f,lambda f:f.receipt['compiler'].update(startedAtUtc='2026-10-10T23:59:58Z',endedAtUtc='2026-10-10T23:59:59Z')))
probe('resolver-stdout-unrelated-tool',lambda f:f.data.update({str(f.root/'streams/resolve.out'):b'/tmp/wrong\n'})) # fixture resolver output /tmp/swiftc already disagrees logical path
probe('claimed-AX-available-origin-omitted',lambda f:(f.summary.update(freshAXClient={'externalAX':'AVAILABLE','compilerStatus':'SUCCESS'}),f.refresh_summary()))
probe('sourceDrift-true',lambda f:mutate(f,lambda f:f.receipt.update(sourceDrift=True)))
probe('empty-compiler-argv',lambda f:mutate(f,lambda f:f.receipt['compiler'].update(argv=[])))
probe('missing-capture-case',lambda f:f.capture.pop('case'))
probe('extra-unbound-source-before-output',lambda f:mutate(f,lambda f:f.receipt['compiler']['argv'].insert(1,'/unbound/Other.swift')))
probe('malformed-adapter-record',lambda f:mutate(f,lambda f:f.receipt['compiler']['sourceBefore'].update({'CaptureHost.swift':None})))
probe('malformed-output-record',lambda f:mutate(f,lambda f:f.receipt['compiler'].update(outputBinary=[])))
probe('malformed-invocation-mode',lambda f:mutate(f,lambda f:f.receipt.update(invocationMode=[])))
probe('extra-unbound-flag',lambda f:mutate(f,lambda f:f.receipt['compiler']['argv'].insert(1,'-DUNBOUND')))
print(json.dumps({'kind':'independent-isolated-mac-origin-production-faults-v4','syntheticFixtures':True,'nativeRuns':0,'faults':results},indent=2))
