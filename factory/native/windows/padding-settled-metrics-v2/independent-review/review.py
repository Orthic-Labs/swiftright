from pathlib import Path
import hashlib,json
ROOT=Path('/Volumes/D/claude/swiftright')
P=ROOT/'factory/native/windows/padding-settled-metrics-v2'
OLD=ROOT/'factory/native/windows/padding-settled-metrics-v1/package'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((P/'source-manifest.json').read_text())
assert sha(P/'source-manifest.json')=='8b9dbf4e7b7a0c506eda61c428cc790acda0d92dea05217af0aaa6737ac12c8f'
for row in m['packageFiles']:
 p=P/'package'/row['path']; assert sha(p)==row['sha256'].removeprefix('sha256:'); assert p.stat().st_size==row['bytes']
assert len(m['packageFiles'])==m['fileCount']==13
actual={str(p.relative_to(P/'package')) for p in (P/'package').rglob('*') if p.is_file()}
assert actual=={r['path'] for r in m['packageFiles']}
for rel in m['unchangedFiles']: assert (P/'package'/rel).read_bytes()==(OLD/rel).read_bytes()
plan=json.loads((P/'package/plan.json').read_text())
for row in plan['sourceBindings']: assert sha(P/'package'/row['path'])==row['sha256'].removeprefix('sha256:')
main=(P/'package/Sources/FactoryProbe/main.swift').read_text()
old=(OLD/'Sources/FactoryProbe/main.swift').read_text()
assert main.replace('"scale": Double(scale)','"scale": scale').replace('"scale": Double(host.scale)','"scale": host.scale')==old
payload=(P/'package/Sources/FactoryProbe/MetricsPayload.swift').read_text()
logger=(P/'package/Sources/FactoryProbe/MetricsLogging.swift').read_text()
control=(P/'serializer-control/main.swift').read_text()
assert sha(P/'serializer-control/main.swift')==m['serializerControl']['mainSha256']
assert sha(P/'package/Sources/FactoryProbe/MetricsPayload.swift')==m['serializerControl']['sharedSourceSha256']
for x in ['Double(value.bridgeScale)','Double(value.clientScale)','"logicalWidth": value.logicalWidth','"logicalHeight": value.logicalHeight','let logicalWidth: Double, logicalHeight: Double','throw NSError','NSUnderlyingErrorKey: error']:
 assert x in payload,x
for x in ['Double(owned.size.logicalWidth)','Double(owned.size.logicalHeight)','Double(event.x)','Double(event.y)','try emit(payload)','try factoryPaddingMetricsJSONText']:
 assert x in logger,x
assert 'try?' not in payload+logger
assert main.index('try window.commit(')<main.index('try metricsLog.emit(["record": "first-layout"')<main.index('firstLayoutLogged = true')
assert main.index('try metricsLog.event(')<main.index('firstWindowMetricsEventSeen = true')
for x in ['factoryPaddingMetricsSnapshotPayload(values','factoryPaddingMetricsJSONText(payload','UInt64.max','18446744073709551615','Double.infinity','error.domain == "FactoryMetricsLogSerialization"','SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0']:
 assert x in control,x
files=[P/'source-manifest.json',P/'serializer-control/main.swift',P/'README.md']+[P/'package'/r['path'] for r in m['packageFiles']]
result={'kind':'independent-padding-metrics-v2-source-review','disposition':'CLEAR_SOURCE_ONLY','findings':[], 'checks':{'manifestRows':13,'planBindings':len(plan['sourceBindings']),'unchangedPredecessorFiles':len(m['unchangedFiles']),'mainDelta':'Three JSON scale casts only; every other main byte preserved','floatingJSON':'All production floating JSON scalars explicitly Double; raw integer identity fields preserved','ordering':'Real onReady ABI snapshot before graph flush; first-event seen flag after successful snapshot; first-layout flag after commit plus successful serialization','errors':'Serializer throws validity/encoding/UTF8 errors; encoding retains underlying error. Ready/event/commit route errors to requestQuit; close errors retained in final nonzero host status','headless':'Shared production snapshot/serializer called for five fixtures, UInt64.max precision assertion & invalid-infinity domain assertion; legacy CGFloat validity printed','executions':'Python source/hash replay only; zero compiler/native/remote executions'},'sourcePins':{str(p.relative_to(ROOT)):sha(p) for p in files},'qualification':'Source repair eligible for actual Windows headless control; no native outcome emitted'}
(P/'independent-review/report.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'disposition':result['disposition'],'reportSha256':sha(P/'independent-review/report.json')}))
