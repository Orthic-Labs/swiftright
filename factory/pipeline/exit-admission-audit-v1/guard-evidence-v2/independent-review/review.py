from pathlib import Path
import hashlib,json
from factory.gate.test_windows_exit_admission import Fixture
from factory.gate.windows_exit_admission import verify_windows_exit_admission
R=Path(__file__).resolve().parents[5];F=Path(__file__).resolve().parents[1];O=Path(__file__).parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((F/'root-stage-manifest.json').read_text())
for x in m['files']:
 p=R/x['path'];assert sha(p)==x['hash'].removeprefix('sha256:') and p.stat().st_size==x['bytes']
assert sha(R/'factory/gate/windows_exit_admission.py')=='20078311fc6dcfb8c43a3ab10582cf8d0490a003e3a8d5eb779cf91ac329ca59'
assert sha(R/'factory/gate/test_windows_exit_admission.py')=='b66819ba918467b3d40a695860a635a7b6d8d28665aca91fbe7ec4aa1d628a19'
checks=[]
faults=[('argv',lambda f:f.objects['compile'].update(argv='unrelated.exe --no-source')),('cwd',lambda f:f.objects['compile'].update(cwd='D:\\foreign')),('compilerPath',lambda f:f.objects['compile'].update(compilerPath='C:\\foreign\\swift.exe')),('target',lambda f:f.objects['compile'].update(target='linux-x86_64')),('output',lambda f:f.objects['compile'].update(exePath='D:\\foreign\\x.exe')),('status',lambda f:f.objects['outcome']['cleanup'].update(status='hold-cleanup')),('waitbool',lambda f:f.objects['outcome']['cleanup'].update(kernelWaitResult=False)),('waitstring',lambda f:f.objects['outcome']['cleanup'].update(kernelWaitResult='0')),('flags',lambda f:f.objects['compile'].update(argv=f.objects['compile']['argv'].replace('/SUBSYSTEM:WINDOWS','/SUBSYSTEM:CONSOLE')))]
for name,mutate in faults:
 f=Fixture();assert f.result()['status']=='pass';mutate(f);f.rebind();result=f.result();assert result['status']=='blocked';checks.append({'fault':name,'issues':result['issues']})
for c in (None,[],1,{}, {'platform':'windows','meta':[]}):assert verify_windows_exit_admission(c,read_bytes=lambda _:b'')['status']=='blocked'
actual=R/'factory/native/windows/round1-seeded-native-v5/single-stack-overlay-r1/replays/run-001/native-01/capture-outcome.json';j=json.loads(actual.read_text(encoding='utf-8-sig'));assert j['primaryError']=='Owned renderer child deadline' and j['cleanup']['kernelWaitResult']==0
f=Fixture();f.objects['outcome']['primaryError']=j['primaryError'];f.rebind();assert f.result()['issues']==['primary or stream failure forbids qualified capture']
report={'kind':'independent-windows-exit-admission-guard-v2','decision':'clear-for-structural-reader-backed-exit-admission','sourceStageSha256':sha(F/'root-stage-manifest.json'),'sourcePins':m['files'],'independentIsolatedFaults':checks,'suppliedTestCount':14,'actualFailedStack':{'path':str(actual.relative_to(R)),'sha256':sha(actual),'primaryError':j['primaryError'],'kernelWaitResult':0,'admission':'blocked via isolated actual-primary-error replay'},'reviewedAuthority':['Exact raw compileRequest derives SwiftPM package/scratch/release/manifest/entry/GUI flags; buildargv/cwd/toolpath/target/configuration/output exact request joins','Compiler actualbytes join plan/build hash; archived host/runtime inputs &full sourcebinding entries join actualbytes','Production six terminal cleanup statuses +typed boolean signal/confirm/integer0 wait required','Malformed metadata/raw objects failclosed; duplicateJSON/nonfinite reject','Synthetic positive scope only; capturehash/raw evidence independent; nativeParityGrantedfalse'],'nextAction':'Integrate frozen guard with archive-owned reader &capture schema validation'}
p=O/'report.json';p.write_text(json.dumps(report,indent=2)+'\n');print(sha(p));print('stage',sha(F/'root-stage-manifest.json'))
