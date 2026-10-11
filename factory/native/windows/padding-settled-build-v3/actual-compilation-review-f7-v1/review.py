"""Read-only actual compiler receipt/binary/archive review. Never starts children."""
from pathlib import Path,PureWindowsPath
from datetime import datetime
import argparse,json,hashlib,struct,re
PACKET=Path(__file__).resolve().parent.parent
EXPECTED_STAGE='sha256:6a83289103471c1d4b2221c81479bbe3cd5aea501eec3e35c0aaccb309a20800'
def digest(raw):return hashlib.sha256(raw).hexdigest()
def pairs(rows):
 d={}
 for k,v in rows:
  if k in d:raise ValueError('duplicate JSON key')
  d[k]=v
 return d
def load(raw):return json.loads(raw.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=lambda _:(_ for _ in ()).throw(ValueError('nonfinite JSON')))
def ticks(value):
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',value)
 if not m:raise ValueError('timestamp ISO shape')
 base=datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00'))
 return int(base.timestamp())*10_000_000+int((m[2] or '').ljust(7,'0'))
def review(archive):
 refs={};issues=[]
 def read(path):
  raw=(archive/path).read_bytes();refs[path]='sha256:'+digest(raw);return raw
 def expect(value,message):
  if not value:raise ValueError(message)
 try:
  stage=(PACKET/'root-stage-manifest.json').read_bytes();expect('sha256:'+digest(stage)==EXPECTED_STAGE,'frozen source stage drift')
  root=PACKET.parents[3]
  for row in load(stage)['files']:
   raw=(root/row['path']).read_bytes();expect('sha256:'+digest(raw)==row['hash'] and len(raw)==row['bytes'],'frozen producer dependency drift')
  planraw=(PACKET/'package/plan.json').read_bytes();plan=load(planraw);record=load(read('observation.json'))
  expect(record['kind']=='factory-padding-settled-compile-only-owned-handle-v1','compiler receipt kind')
  for key in ('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','compilerHash','compilerPath','rendererSha256'):
   expect(record[key]==plan[key],'compiler context '+key)
  expect(record['planSha256']==digest(planraw),'actual plan join')
  request=plan['compileRequest'];package=request['packagePath'];scratch=request['scratchPath']
  dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
  argv=f'build --package-path "{package}" --scratch-path "{scratch}" -c release -Xlinker /MANIFEST:EMBED -Xlinker "{dep}" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
  expect(record['argv']==argv and record['cwd']==package and record['target']=='windows-x86_64' and record['configuration']=='release','actual production compiler invocation')
  expect(type(record['pid']) is int and record['pid']>0,'positive actual compiler PID')
  expect(type(record['exitCode']) is int and record['exitCode']==0,'compiler exit0')
  expect(type(record['kernelWait']) is int and record['kernelWait']==0,'retained compiler kernel signal0')
  for key,value in (('timedOut',False),('ownedExited',True),('streamDrainComplete',True),('nativeWindowOpened',False)):
   expect(type(record[key]) is bool and record[key] is value,'strict compiler state '+key)
  expect(record['error'] is None and record['cleanupError'] is None,'actual compilation failure retained')
  expect(record['cleanupAction']=='natural-exit-no-termination' and record['descendantOwnership']=='not-observed','exact natural compiler completion')
  expect(record['nativeParity']=='hold' and record['frozenTupleBound'] is False and record['closureBinding'] is None,'observational scope retained')
  expect(ticks(record['startedAt'])<=ticks(record['processStartedAt'])<=ticks(record['finishedAt']),'compiler timestamp order')
  states=record['rawStreams'];expect(len(states)==2 and {x['name'] for x in states}=={'stdout','stderr'},'exact two compiler streams')
  rawhashes=record['rawFileHashes'];expect(len(rawhashes)==2 and {x['path'] for x in rawhashes}=={'compile.stdout.bin','compile.stderr.bin'},'exact raw hash records')
  files=record['files'];expect(len(files)==3 and {x['path'] for x in files}=={'compile.stdout.bin','compile.stderr.bin','FactoryProbe.exe'},'actual output file records')
  for state in states:
   for key,value in (('copyCompleted',True),('destinationClosed',True),('sealed',True),('taskIsCompleted',True),('taskIsFaulted',False),('taskIsCanceled',False)):
    expect(type(state[key]) is bool and state[key] is value,'terminal compiler stream '+key)
   expect(state['taskStatus']=='RanToCompletion' and state['closureTaskStatus']=='RanToCompletion' and state['taskException']=='','terminal stream task')
   closure=state['closure']
   for key,value in (('flushCompleted',True),('destinationClosed',True),('completedWithinDeadline',True),('deadlineExpired',False)):
    expect(type(closure[key]) is bool and closure[key] is value,'terminal closure '+key)
   expect(type(closure['deadlineMilliseconds']) is int and closure['deadlineMilliseconds']==5000,'closure deadline')
   expect(state['hashQualification']=='sealed-raw' and closure['error']=='' and closure['flushDisposition']=='requested-terminal-copy','stream flush authority')
   path='compile.'+state['name']+'.bin';raw=read(path);claimed=next(x for x in rawhashes if x['path']==path)
   expect(claimed['state']==state and claimed['hash']['sha256']==digest(raw) and claimed['hash']['qualification']=='sealed-raw','actual sealed stream raw hash/state')
   expect(next(x for x in files if x['path']==path)['sha256']==digest(raw),'raw file index join')
  exe=read('FactoryProbe.exe');expect(record['exeSha256']==digest(exe),'actual exe bytes')
  expect(record['exePath']==str(PureWindowsPath(scratch)/'out/Products/Release-windows-x86_64/FactoryProbe.exe'),'exact produced path')
  expect(len(exe)>=64 and exe[:2]==b'MZ','PE header');pe=struct.unpack_from('<I',exe,60)[0]
  expect(pe>=64 and pe+94<=len(exe) and exe[pe:pe+4]==b'PE\0\0','PE offset/signature')
  expect(struct.unpack_from('<H',exe,pe+4)[0]==34404 and struct.unpack_from('<H',exe,pe+92)[0]==2,'actual x64 GUI PE')
  expect(type(record['exeMachine']) is int and record['exeMachine']==34404 and type(record['exeSubsystem']) is int and record['exeSubsystem']==2,'recorded PE values')
  expect(next(x for x in files if x['path']=='FactoryProbe.exe')['sha256']==digest(exe),'exe file index join')
  modules=record['runtimeModules'];expected={'x86_64-unknown-windows-msvc.swiftmodule','x86_64-unknown-windows-msvc.swiftdoc'}
  expect(len(modules)==2 and {PureWindowsPath(x['archivePath']).name for x in modules}==expected,'exact freshly built runtime module pair')
  for row in modules:
   name=PureWindowsPath(row['archivePath']).name;raw=read('runtime-module-archive/'+name)
   expect(PureWindowsPath(row['archivePath'])==PureWindowsPath(package)/'build-settled-r1/runtime-module-archive'/name,'module archive path')
   expect(str(PureWindowsPath(row['path'])).startswith(scratch+'\\') and PureWindowsPath(row['path']).name==name,'module produced source path')
   expect(row['sha256']==digest(raw) and type(row['bytes']) is int and row['bytes']==len(raw)>0,'module raw bytes')
   expect(row['runtimeSourceCommit']==plan['runtimeSourceCommit'] and row['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash'],'module runtime context')
 except (ValueError,TypeError,KeyError,AttributeError,OverflowError,OSError,UnicodeError,struct.error) as error:issues.append(str(error))
 return {'kind':'actual-padding-compilation-local-review','acceptedObservationalCompile':not issues,'issues':issues,'rawRefs':refs,'nativeActions':0,'qualification':'hold','scope':'frozen producer +reported actual driver invocation/kernel/streams +archived exe/module bytes; no backend/native/parity attestation'}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('archive',type=Path);a=p.parse_args();print(json.dumps(review(a.archive),indent=2))
