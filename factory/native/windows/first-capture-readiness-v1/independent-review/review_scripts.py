#!/usr/bin/env python3
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5];HERE=Path(__file__).resolve().parent;PACKET=HERE.parent
sys.path.insert(0,str(ROOT))
def pin(p):raw=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def main():
 from factory.tools.canonical_json import sha256
 stage=PACKET/'root-stage-manifest.json';assert pin(stage)['sha256']=='c5d3d6fcb519f80fd1ab3ac20b795ee9d8659feb7364a93785df94d5564fd4f7';m=json.loads(stage.read_bytes())
 for e in m['files']+m['dependencies']:assert pin(ROOT/e['path'])==e,e['path']
 assert pin(PACKET/'capture-first.ps1')['sha256']=='04309140da3957ae8a245ff357adb99d91f9a75e91307334b16b238d9d558c88'
 readiness=json.loads((PACKET/'readiness.json').read_bytes());package=ROOT/'factory/native/windows/disabled-primary-v7-20261010';plan=json.loads((package/'plan.json').read_bytes());compiled=json.loads((package/'observation.json').read_bytes());manifest_path=ROOT/'factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.manifest.json';manifest=json.loads(manifest_path.read_bytes());cases_path=ROOT/'factory/pipeline/inputs/cases.json';cases=json.loads(cases_path.read_bytes());matches=[c for c in cases if c['id']==plan['case']['id']];assert len(matches)==1 and sha256(matches[0])==plan['case']['hash']
 assert readiness['case']==plan['case']==manifest['case'];assert compiled['planSha256']==pin(package/'plan.json')['sha256'];assert compiled['exitCode']==0
 assert compiled['sourceHash']==plan['sourceHash']==manifest['sourceHash']==readiness['sourceHash'];assert compiled['exeSha256']==readiness['exeSha256'];assert compiled['rendererSha256']==plan['rendererSha256']==readiness['rendererSha256'];assert plan['manifestHash']=='sha256:'+pin(manifest_path)['sha256']
 for binding in plan['sourceBindings']:assert 'sha256:'+pin(package/binding['path'])['sha256']==binding['sha256']
 generated=manifest_path.with_name(manifest['sourceFile']);assert 'sha256:'+pin(generated)['sha256']==plan['sourceHash'];assert generated.read_bytes()==(package/'Sources/FactoryProbe/Witness.swift').read_bytes()
 assert readiness['nativeParity']=='hold' and readiness['frozenTupleBound'] is False and readiness['closureBinding'] is None
 for n in ('capture-first.ps1','run-first.ps1','first-task.ps1'):
  raw=(PACKET/n).read_bytes();q=HERE/'preimages'/(n+'.final-'+hashlib.sha256(raw).hexdigest()[:12]);q.write_bytes(raw)
 checks=[
  {'guard':'lock CAS','evidence':'FileShare.None compare trimmed free/owner while holding exclusive stream; flush before dispose; release only exact acquired owner'},
  {'guard':'controller visibility','evidence':'interactive GUID scheduled task uses System32 wscript→WScript.Shell.Run style0→PowerShell WindowStyle Hidden; no keyboard/mouse input or foreground API'},
  {'guard':'launch identity','evidence':'exact package path/case/exe pin, historical compiled plan equality, allsource bindings, GUI subsystem2 & staged DLL before/after; thread CBT activation/focus veto installed before bridge.run in pinned main.swift'},
  {'guard':'target identity','evidence':'live currentPID/path/starttime & HWND-PID equality precede bottom/noactivate placement, FromHandle & UIA traversal; UIAroot Current.ProcessId equality; same gate invoked throughout pixels'},
  {'guard':'bounded cleanup','evidence':'6min free-lock wait,10min retained own scheduled task,6sec startup,5sec pixel channel,15sec child exit; own path/PID/starttime matches before taskkill; no Dell file/task deletion'},
  {'guard':'readback labels','evidence':'UIA starts owned HWND only; PrintWindow flags3 & CopyFromScreen separate repeated PNGs; natural occlusion25point grid recorded; controlled qualification/provider export false; parity hold & tuple/closure absent'}]
 report={'status':'CLEAR-SCRIPT-REVIEW','scope':'One staged r09 disabled-case observational replay; no renderer/ABI edits or tuple migration','reviewer':pin(Path(__file__)),'ownerStage':pin(stage),'scripts':[pin(PACKET/n) for n in ('run-first.ps1','first-task.ps1','capture-first.ps1')],'sourceCaseJoins':{'case':plan['case'],'casesInput':pin(cases_path),'caseRawCanonicalHash':sha256(matches[0]),'generatedSource':pin(generated),'manifest':pin(manifest_path),'sourceBindings':plan['sourceBindings'],'compileReceipt':pin(package/'observation.json'),'exeSha256':compiled['exeSha256'],'rendererSha256':compiled['rendererSha256']},'checks':checks,'rootDispatchRequirements':['Windows PowerShell parse0 for these exact script bytes','Remote exact plan/compile/source/pixelhelper/exe/DLL pin preflight','Fresh run directory & exact desktop-lock owner'],'localPowerShellAvailable':False,'nativeLaunches':0,'productionEdits':0,'nativeParity':'hold','frozenTupleBound':False,'closureBinding':None}
 out=HERE/'script-clearance.json';out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(pin(out)))
if __name__=='__main__':main()
