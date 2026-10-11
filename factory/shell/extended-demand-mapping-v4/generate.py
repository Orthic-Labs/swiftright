"""Bounded source/SDK component candidates; never registry or native admission."""
import pathlib,json,hashlib,importlib.util,re,copy,collections,sys
ROOT=pathlib.Path(__file__).resolve().parents[3];OUT=pathlib.Path(__file__).resolve().parent
PINS={'factory/shell/extended-demand-mapping-v3/mapping-v3.json':'575dc34e589b225dfe2769d03fef6ebf1fd3c1f49173f0f7d1fbbcbc1c4135cf','factory/shell/extended-demand-mapping-v3/raw-pins-v3.json':'193d8978362b9a29544820c2c7d4bb89d9fd147a83aa9fecac5ede5a8caccba9','factory/catalogue/module-provenance-spike/exact_validator.py':'83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5','factory/catalogue/public-ancestor-spike/full-source-census-v2/full-source-census-v2.json':'625c6a961d3e0ff8620b88fad85fb565c94d8af565e5100fd7d56e7ed1ba310f'}
SPECS=[('001','slice-editor','Binding','let row: Binding<EditorRow>','observed-nominal-component','Getter/setter overload remains unselected; transaction setter needs compiler usage receipt.'),('002','slice-editor','Button','Button("Up", action:','observed-nominal-component','Title initializer overload & action behavior remain unqualified.'),('007','settings-panel','TextField','<input','proposed-component','Settings search input only; remaining control variety needs separate declarations/adapters.'),('026','pdf-viewer','TextField','<input aria-label="Find in PDF"','proposed-component','Find text entry only; PDF search service & IME semantics remain external.'),('030','settings-panel','FocusState','onKeyDown={onNavKey}','proposed-component','Focus state building block only; key routing/roving policy remains journey logic.'),('045','legal-gate','RadioGroupPickerStyle','type="radio"','proposed-component','Radio style component only; selection/eligibility contract remains journey logic.'),('045','legal-gate','CheckboxToggleStyle','type="checkbox"','proposed-component','Checkbox style component only; acknowledgement contract remains journey logic.'),('052','pdf-viewer','NavigationSplitView','return <aside className="rk-pdf-outline"','proposed-component','Sidebar container candidate only; PDF outline/page service remains external.'),('057','media-player','Slider','type="range"','proposed-component','Range transport component only; playback clock/provider & progress animation remain external.')]
USRS={'Binding':'s:7SwiftUI7BindingV','Button':'s:7SwiftUI6ButtonV','TextField':'s:7SwiftUI9TextFieldV','FocusState':'s:7SwiftUI10FocusStateV','RadioGroupPickerStyle':'s:7SwiftUI21RadioGroupPickerStyleV','CheckboxToggleStyle':'s:7SwiftUI19CheckboxToggleStyleV','NavigationSplitView':'s:7SwiftUI19NavigationSplitViewV','Slider':'s:7SwiftUI6SliderV'}
def sha(b):return hashlib.sha256(b).hexdigest()
def check(x,msg):
 if not x:raise ValueError(msg)
def pin(p):b=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':sha(b),'bytes':len(b)}
def read(p,w=None):b=p.read_bytes();check(w is None or sha(b)==w.removeprefix('sha256:'),'input hash');return b
def load(p):return json.loads(p.read_text())
def sdk_binding(records,source,name):
 usr=USRS[name];hits=[r for r in records if r.get('usr')==usr];check(len(hits)==1,'exact SDK USR cardinality');r=hits[0]
 pos=[x for x in records if x.get('line')==r['line'] and x.get('column')==r['column']];check(len(pos)==1,'physical SDK cardinality')
 check(r['name']==name and r['kind']=='source.lang.swift.decl.struct' and r.get('effective_access')=='source.decl.effective_access.public' and not r.get('is_implicit'),'exact SDK nominal')
 line=source.splitlines()[r['line']-1];check(re.search(r'\bpublic struct '+re.escape(name)+r'\b',line) is not None,'SDK public source owner');check(line[r['column']-1:].startswith(name),'SDK source column')
 check(not r['sourcekitContext'],'SDK full nominal owner')
 return {'usr':usr,'compilerRecord':r,'sdkLine':r['line'],'sdkColumn':r['column'],'sdkExactLine':line}
def main(capture=False):
 for p,w in PINS.items():read(ROOT/p,w)
 v3=load(ROOT/'factory/shell/extended-demand-mapping-v3/mapping-v3.json');census=load(ROOT/'factory/catalogue/public-ancestor-spike/full-source-census-v2/full-source-census-v2.json');CROOT=ROOT/'factory/catalogue/public-ancestor-spike/full-source-census-v2'
 catalogue=load(ROOT/v3['inputs']['catalogue']['path']);read(ROOT/v3['inputs']['catalogue']['path'],v3['inputs']['catalogue']['sha256']);cat={s['usr']:s for s in catalogue['symbols']}
 parser=ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py';sp=importlib.util.spec_from_file_location('pinned_sdk_parser',parser);m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
 files={p:pin(ROOT/p) for p in PINS}
 for descriptor in v3['inputs'].values():
  p=ROOT/descriptor['path'];read(p,descriptor['sha256']);check(p.stat().st_size==descriptor['bytes'],'prior input size');files[descriptor['path']]=pin(p)
 demand=load(ROOT/v3['inputs']['demand']['path']);inventory=load(ROOT/v3['inputs']['inventory']['path']);sdk={}
 for mod in ['SwiftUI','SwiftUICore']:
  sm=census['sourceCensus']['modules'][mod];im=census['sourceKitCensus']['modules'][mod]
  for d in [sm['sourceCopy'],im['output'],im['request']]:p=CROOT/d['path'];read(p,d['sha256']);files[str(p.relative_to(ROOT))]=pin(p)
  sdk[mod]=(m.entities(read(CROOT/im['output']['path']).decode()),read(CROOT/sm['sourceCopy']['path']).decode(),sm,im)
 snapshots={s['evidenceId']:s for r in v3['rows'] for s in r['v3Evidence']['sourceSnapshots']}
 selected=sorted({s[1] for s in SPECS});manifest=OUT/'evidence/source-snapshot-manifest.json'
 if capture:
  captured=[]
  for eid in selected:
   ref=snapshots[eid];p=pathlib.Path(ref['sourcePath']);b=p.read_bytes();dest=OUT/'evidence/source-snapshots'/f'{eid}-{sha(b)[:16]}.bin';dest.write_bytes(b);captured.append({'evidenceId':eid,'originalPath':str(p),'snapshot':pin(dest),'v3SnapshotHash':ref['sha256'],'matchesV3Snapshot':sha(b)==ref['sha256']})
  manifest.write_text(json.dumps({'kind':'current-journey-source-capture-v4','sources':captured},indent=2)+'\n')
 sman=load(manifest);files[str(manifest.relative_to(ROOT))]=pin(manifest);sources={r['evidenceId']:r for r in sman['sources']};components=[]
 for key,eid,name,anchor,state,remain in SPECS:
  src=sources[eid];p=ROOT/src['snapshot']['path'];b=read(p,src['snapshot']['sha256']);check(len(b)==src['snapshot']['bytes'],'source size');files[str(p.relative_to(ROOT))]=pin(p);lines=b.decode().splitlines();matches=[(i+1,l) for i,l in enumerate(lines) if anchor in l and not l.strip().startswith(('*','//','.rk-'))];check(bool(matches),'journey exact source anchor');ln,exact=matches[0]
  mod='SwiftUICore' if name=='Binding' else 'SwiftUI';records,source,sm,im=sdk[mod];binding=sdk_binding(records,source,name);cs=cat.get(binding['usr']);check(cs is not None and cs['status']=='inventory' and cs['path']=='SwiftUI.'+name,'catalogue exact USR')
  row=next(r for r in v3['rows'] if r['rowKey'].endswith(key));check(eid in [x['evidenceId'] for x in row['v3Evidence']['sourceSnapshots']],'journey inventory association')
  actual_journeys=sorted(d['journey_id'] for d in demand['journey_demands'] if row['demand'] in d['extended_demands']);check(actual_journeys==sorted(row['journeyIds']),'raw journey demand association');check(any(e['id']==eid and e['path']==src['originalPath'] for e in inventory['evidence']),'raw inventory source association')
  components.append({'rowKey':row['rowKey'],'demand':row['demand'],'journeyIds':row['journeyIds'],'state':state,'component':name,'catalogueIdentity':cs,'sdkBinding':{**binding,'physicalModule':mod,'sourceInput':pin(CROOT/sm['sourceCopy']['path']),'installedSdkSourceReference':sm['installedSdkSourceReference'],'rawIndexInput':pin(CROOT/im['output']['path']),'requestInput':pin(CROOT/im['request']['path'])},'journeySource':{**src,'line':ln,'exactLine':exact,'language':'Swift' if eid=='slice-editor' else 'TypeScript/React'},'remainingRequirement':remain,'registryBlockId':None,'nativeAcceptance':False,'compilerCallOverloadResolved':False})
 rows=copy.deepcopy(v3['rows'])
 for row in rows:
  cs=[c for c in components if c['rowKey']==row['rowKey']];row['v4Evidence']={'priorResolutionPreserved':row['v3Evidence']['resolution'],'components':cs,'sourceComponentState':'observed-nominal-component' if any(c['state']=='observed-nominal-component' for c in cs) else 'proposed-component' if cs else 'no-new-exact-component','fullDemandResolved':False,'registryPromotion':False}
  if row['v3Evidence']['resolution'] in ['unmapped-held','ambiguous-catalogue-held'] and not cs:row['v4Evidence']['constraint']={'reason':'Existing journey inventory has no observed SwiftUI SDK call selecting exact declaration; broad behavior demand cannot be discharged by catalogue-name similarity.','sourceLanguages':sorted({pathlib.Path(s['sourcePath']).suffix for s in row['v3Evidence']['sourceSnapshots']}),'requiredNextEvidence':'Exact Swift source/overload receipt or explicit host adapter decomposition tied to this journey.'}
 result={'kind':'extended-demand-mapping-v4-source-component-candidate','version':4,'status':'source-components-only-no-registry-or-native-promotion','denominator':v3['denominator'],'priorResolutionCounts':v3['resolutionCounts'],'componentCounts':{'demandsWithComponents':len({c['rowKey'] for c in components}),'components':len(components),'observedNominalComponents':sum(c['state']=='observed-nominal-component' for c in components),'proposedComponents':sum(c['state']=='proposed-component' for c in components),'newFullDemandResolutions':0,'registryMappedRows':0},'rows':rows,'inputs':list(sorted(files.values(),key=lambda r:r['path'])),'toolchainLineage':census['immutableReferences']['sourceKitToolchainEvidence'],'preservation':{'v3Mapping':pin(ROOT/'factory/shell/extended-demand-mapping-v3/mapping-v3.json'),'originalRowsPreserved':True,'runtimeRendererAbiChanges':False}}
 (OUT/'mapping-v4.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps(result['componentCounts']))
 return result,sdk
if __name__=='__main__':main('--capture' in sys.argv)
