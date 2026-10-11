from pathlib import Path
import json,hashlib,importlib.util
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/paired-padding-settled-v4';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('paired_padding_v4_review',P/'report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
rr=m.reader(R);mr=m.reader(m.MAC);cfg,case,recipe,accept=m.source_inputs(rr);f8=m.load_f8(rr);mac=m.mac_rows(mr,f8,cfg,case);peer=m.peer_facts(rr)
assert len(mac)==20 and peer['started']==18 and peer['eligible']==15 and peer['invalidHost']==[3,16]
assert all('id' not in row and 'origin' not in row for row in mac)
original=[]
class CoherentChangedReader:
 def __call__(self,**kw):
  raw=mr(**kw)
  if kw['reference']['path'].endswith('external-ax.raw.json'):
   data=json.loads(raw.decode('utf-8-sig'))
   for n in f8._walk(data['steps'][0]['tree']):
    if n.get('role')=='AXStaticText' and n.get('value')!=data.get('windowTitle'):n['value']='COHERENT_FORGED_LABEL'
   return json.dumps(data).encode()
  return raw
changed=m.mac_rows(CoherentChangedReader(),f8,cfg,case)
assert changed[0]['labels']!=mac[0]['labels']
assert f8.compare_accessibility(mac[0]['labels'],[])['exactSequenceMatch'] is False
assert f8.compare_accessibility([{'role':'AXStaticText','value':'FORGED'}],[])['exactSequenceMatch'] is False
actual=json.loads((P/'gate-results.json').read_text())['report'];assert actual['status']=='blocked' and not actual['parityGranted'] and actual['captureIds']==[]
assert any('macos has 0 runs' in issue for issue in actual['issues'])
controls=m.controls();assert controls['tampered-reader-bytes']=='rejected'
source=(P/'report.py').read_text();assert "p.write_bytes(raw)" in source and "spec_from_file_location('paired_padding_f8',p)" in source
assert 'WIN_ROOT' not in source and "pinned_repo(r,PEER,PINS['peer'])" in source
report={'verdict':'HOLD_NATIVE_ENVELOPE_INTEGRATION_AND_CONTROL_CLAIMS','fixed':['Windows raw parsing removed; facts use immutable peer pin, no Windows semantic comparison claim','F8 executes verified reader bytes in isolated temporary source','No frozen data mutation in controls','Actual seeded source case &Mac20 raw source AX/layout retained; F9 no hardcodedBox layout; F10 no forcedblocked status'],'findings':[{'id':'mac-native-envelopes-not-integrated','proof':'Twenty supplied mac rows lack capture id/origin, case is full case instead of typed ref; actual F10 reports captureIds=[], missing-origin, macos0runs &ID issues. Integration actualMacCaptures20 describes supplied rows, not admitted native captures. Windows native envelopes also missing.','required':'State raw-only Mac20/F10supplied20/admitted0 explicitly or construct production-compatible truthful envelopes with actual origin proof &IDs; retain all holds.'},{'id':'vacuous-control-label-fault','proof':'Baseline Mac label vs emptyWindows already exactSequenceMatch=false; mutated label produces same false. It does not prove label mutation rejects. Three other control states are literals.','required':'Baseline passing comparison then concrete mutated label failure; actual admission controls for claimed gates with exact reason.'},{'id':'injected-reader-coherent-fault-not-rejected','proof':'mac_rows with reader returning coherently changed valid JSON accepted all20 changedAXlabel rows despite original referencepins; current appendedX fault only tests invalidJSON. Real production ArchiveByteReader still validates disk bytes, so this is control/interface coverage defect, not unchecked actualdisk fallback.','required':'Independently validate returned hash or test actual reader on temporary fixture byte drift with exact archive rejection.'}], 'counts':{'macRaw':20,'windowsRequested':20,'windowsStarted':18,'windowsEligiblePeerFacts':15,'invalidHost':[3,16],'deadline':[18],'notStarted':[19,20],'f10AdmittedMac':0,'f10AdmittedWindows':0},'actualGateIssues':actual['issues'],'producerControlsReplay':controls,'reviewExecution':'Offline Python production read/parser/F8 controls only; no original source/evidence mutation, compiler/native/remote actions','pins':{str(p.relative_to(R)):sha(p) for p in [P/'report.py',P/'report.json',P/'gate-results.json',P/'fault-controls.json',P/'stage-manifest.json']}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'))
