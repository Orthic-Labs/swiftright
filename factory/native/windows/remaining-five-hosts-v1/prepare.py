"""Source-only five exact v8 seeded hosts. No process/compiler/native invocation."""
from pathlib import Path, PureWindowsPath
import hashlib,json
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
BASE=ROOT/'factory/native/windows/round1-seeded-hosts-v1/stack-overlay/package'
MAC=ROOT/'factory/oracle/mac/seed-origin-v8'
REMOTE=r'D:\Claude\swiftright\factory\native\windows\remaining-five-hosts-v1'
LABELS=('disabled','image','shapes.fill-stroke','text.bundled-font','toggle')
NEEDS={'disabled':[], 'image':['sfSymbolProvider'], 'shapes.fill-stroke':['centeredContinuousRoundedStroke'],
       'text.bundled-font':['roundedFontProvider','lineLimitShaping'], 'toggle':['nativeSwitchPainting']}
HOLDS={'disabled':['Disabled hit-testing/input qualification unattempted; enabled metadata only','Native observations require coordinated lock + fresh compiler proof','Font/theme parity remains held'],
       'image':['ABI0.6 has image_register RGBA bytes but no SF Symbol catalogue/provider; no star substitute','DisplayScale/colorScheme injection qualification held'],
       'shapes.fill-stroke':['ABI0.6 rect radius/border cannot attest SwiftUI continuous corner + centered stroke semantics; no rect-border approximation'],
       'text.bundled-font':['Exact witness requests rounded system design/medium/lineLimit2, not a Tinos asset','ABI0.6 has family/size/weight measure inputs but no attested rounded family provider or lineLimit shaping; no Segoe fallback'],
       'toggle':['ABI0.6 exposes switch/checkbox semantics + toggled state, not native switch paint','No hand-painted knobs/hosted replacement; state stimulus/hit-testing unattempted']}

def h(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def save(path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def copy(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())

def prepare():
 pins=json.loads((MAC/'input-pins.json').read_bytes())
 base_plan=json.loads((BASE/'plan.json').read_bytes())
 policy='''import Foundation
// Explicit provider requirements, never expected pixels or native substitutions.
enum FactoryNativeProviderRequirement: String, CaseIterable {
    case sfSymbolProvider, centeredContinuousRoundedStroke, roundedFontProvider
    case lineLimitShaping, nativeSwitchPainting
}
func factoryProviderHold(_ requirements: [FactoryNativeProviderRequirement]) -> String? {
    guard !requirements.isEmpty else { return nil }
    return requirements.map { $0.rawValue }.sorted().joined(separator: ";")
}
'''
 rows=[]
 for label in LABELS:
  entry=next(x for x in pins['rows'] if x['block']=='swiftui.'+label)
  for role in ('case','manifest','source','witness'):
   raw=(MAC/entry[role]['path']).read_bytes()
   assert h(raw)==entry[role]['sha256'] and len(raw)==entry[role]['bytes']
  manifest=json.loads((MAC/entry['manifest']['path']).read_bytes())
  case=json.loads((MAC/entry['case']['path']).read_bytes())
  package=OUT/label/'package';sources=package/'Sources/FactoryProbe';sources.mkdir(parents=True,exist_ok=True)
  for rel in ('Package.swift','Sources/FactoryProbe/FactoryFill.swift','Sources/FactoryProbe/FactoryTextGeometry.swift',
              'Sources/FactoryProbe/FactoryViewport.swift','Sources/FactoryProbe/FactoryContainer.swift',
              'runtime-source-receipt.json','runtime-source-tree.json'):
   copy(BASE/rel,package/rel)
  copy(MAC/entry['source']['path'],sources/'Witness.swift')
  copy(MAC/entry['manifest']['path'],package/'witness.manifest.json')
  copy(MAC/entry['case']['path'],package/'case.json')
  copy(MAC/entry['witness']['path'],package/'reference-witness.swift')
  (sources/'FactoryProviderPolicy.swift').write_text(policy)
  main=(BASE/'Sources/FactoryProbe/main.swift').read_text().replace('Witness_stack_overlay()',manifest['witnessType']+'()')
  dark=manifest.get('environmentInputs',{}).get('colorScheme')=='dark'
  main=main.replace('let themeDark = "dark" == "dark"','let themeDark = '+('true' if dark else 'false'))
  needs=', '.join('.'+x for x in NEEDS[label])
  injection='''        let requirements: [FactoryNativeProviderRequirement] = [NEEDS]
        if let hold = factoryProviderHold(requirements) {
            print("FACTORY_PROVIDER_HOLD \\(hold)"); return 78
        }
'''.replace('NEEDS',needs)
  main=main.replace('        let bridge = try Bridge.load',injection+'        let bridge = try Bridge.load')
  (sources/'main.swift').write_text(main)
  plan=dict(base_plan)
  for key in ('seedLineage','seedCaptureSourceMatched'):plan.pop(key,None)
  remote_package=str(PureWindowsPath(REMOTE)/label/'package');scratch=str(PureWindowsPath(remote_package)/'build-v2-r1'/'scratch')
  plan.update(case=manifest['case'],sourceHash=manifest['sourceHash'],manifestHash=h((package/'witness.manifest.json').read_bytes()),
              hostMode='renderer',executionEligible=False,seedCaptureSourceMatched=False,replays=1,
              environmentInputs=manifest.get('environmentInputs',{}),
              compileRequest={'kind':'swiftpm-windows-gui-release/1','packagePath':remote_package,
                'scratchPath':scratch,'compilerPath':plan['compilerPath'],'target':'windows-x86_64','configuration':'release'},
              providerRequirements=NEEDS[label],providerHold=HOLDS[label],
              observationScope='Same exact v8 witness; disabled candidate only, other providers fail before DLL/window creation',
              prospectiveNativeCandidate=(label=='disabled'),freshCompilerRequired=True,
              channelsUnavailable=HOLDS[label],nativeParity='hold',frozenTupleBound=False,closureBinding=None)
  bindings=[{'path':str(p.relative_to(package)).replace('\\','/'),'sha256':h(p.read_bytes())}
            for p in sorted(package.rglob('*')) if p.is_file() and (p.name=='Package.swift' or 'Sources' in p.relative_to(package).parts or p.name in ('witness.manifest.json','case.json','reference-witness.swift'))]
  plan['sourceBindings']=bindings
  plan['v8SourceAdmission']={'inputPinsHash':h((MAC/'input-pins.json').read_bytes()),
       'independentReviewHash':h((MAC/'full-admission-review/v8-independent-review.json').read_bytes()),
       'caseFileHash':h((package/'case.json').read_bytes()),'referenceWitnessHash':entry['witness']['sha256'],
       'sameSourceHash':entry['source']['sha256'],'MacCaptureCount':0,
       'scope':'Independent v8 canonical source admission, not actual Mac capture or compiler-origin receipt'}
  plan['runtimeModuleOrigin']={'receiptHash':h((ROOT/'factory/native/windows/module-origin-37429120-20261011/module-provenance-run-r4/module-provenance-receipt.json').read_bytes()),
       'acceptedReplayHash':h((ROOT/'factory/native/windows/module-origin-37429120-20261011/r6-verification.json').read_bytes()),
       'independentReviewHash':h((ROOT/'factory/native/windows/module-provenance/independent-final-actual-review.json').read_bytes()),
       'scope':'Exact374 source lineage context; fresh SwiftPM host build recompiles runtime, must archive its own produced module bytes; not prebuilt module reuse'}
  save(package/'plan.json',plan)
  rows.append({'label':label,'case':plan['case'],'sourceHash':plan['sourceHash'],'planHash':h((package/'plan.json').read_bytes()),
               'remotePackage':remote_package,'providerRequirements':NEEDS[label],'holds':HOLDS[label],
               'prospectiveNativeCandidate':label=='disabled'})
 dep=OUT/'dependencies';dep.mkdir(exist_ok=True)
 for src,name in [(MAC/'input-pins.json','mac-v8-input-pins.json'),(MAC/'full-admission-review/v8-independent-review.json','mac-v8-independent-review.json'),
    (ROOT/'factory/native/windows/module-origin-37429120-20261011/module-provenance-run-r4/module-provenance-receipt.json','module-origin-receipt.json'),
    (ROOT/'factory/native/windows/module-origin-37429120-20261011/r6-verification.json','module-origin-accepted-replay.json'),
    (ROOT/'factory/native/windows/module-provenance/independent-final-actual-review.json','module-origin-independent-review.json')]:copy(src,dep/name)
 save(OUT/'readiness.json',{'kind':'remaining-five-windows-hosts-source-v1','sourceOnly':True,'compilerRuns':0,'nativeRuns':0,'stagedWrites':0,
   'runtimeCommit':base_plan['runtimeSourceCommit'],'rendererHash':'sha256:'+base_plan['rendererSha256'],'nativeParity':'hold',
   'rows':rows,'dispatch':'Root-reviewed source & actual controls first; fresh compiler archive before any native observation',
   'priority':'disabled observational candidate; image/shapes/font/toggle provider-held, no substitutions'})
 if __name__=='__main__':print('prepared five source-only packages')

if __name__=='__main__':prepare()
