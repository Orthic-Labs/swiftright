#!/usr/bin/env python3
"""Offline actual receipts review; writes only independent-review-v1 output."""
from pathlib import Path
import json,hashlib,gzip,sys
ROOT=Path(__file__).resolve().parents[5];sys.path.insert(0,str(ROOT))
from factory.native.macos.check_evidence import verify
from factory.native.macos.capture import digest
from factory.core.artifacts import canonical_hash,validate_artifact
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.gate.mac_origin_admission import mac_origin_admission_issues
PACKET=Path(__file__).resolve().parent.parent;ACTUAL=PACKET/'actual'
def load(path):return json.loads(Path(path).read_text())
def sha(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def main():
 plan=load(PACKET/'root-run-plan.json');owned=load(PACKET/'root-owned-process.json');process=load(PACKET/'root-process.json')
 assert owned['argv']==plan['argv'] and owned['ownedProcessGroup'] is True and owned['pid']==owned['pgid']
 assert process['exitCode']==0
 for channel in ('stdout','stderr'):assert digest(PACKET/f'capture.{channel}.bin').removeprefix('sha256:')==process[channel+'Sha256']
 assert plan['candidateOnly'] is True and plan['frozenTupleBound'] is False and plan['permissionRequests'] is False
 pins={}
 for name,expected in plan['sourcePins'].items():
  path=ROOT/'factory/native/macos'/name
  if not path.exists():path=ROOT/name
  assert digest(path).removeprefix('sha256:')==expected.removeprefix('sha256:');pins[str(path.relative_to(ROOT))]=digest(path)
 summarypath=next(ACTUAL.glob('*/summary.json'));directory=summarypath.parent;summary=load(summarypath)
 assert summary['candidateOnly'] is True and summary['acceptance']=='not-promoted'
 assert [r['run'] for r in summary['runs']]==list(range(1,21))
 manifest=load(plan['argv'][plan['argv'].index('--manifest')+1]);source=Path(plan['argv'][plan['argv'].index('--manifest')+1]).parent/manifest['sourceFile']
 assert digest(source)==manifest['sourceHash']==summary['sourceHash']
 config=load(directory/'origin-reader-config.json');archive=load(directory/'origin-archive-manifest.json')
 assert digest(directory/'origin-reader-config.json')==archive['readerConfigHash']
 assert archive['status']=='PASS' and archive['candidateOnly'] is True
 reader=ArchiveByteReader(mac_roots=config['macRoots'],mac_path_map=config['macPathMap'])
 consumed={};cache={}
 def archived(cap,ref):
  # No live fallback: every guard-consumed reference must have explicit durable map.
  logical=ref['path'];assert logical in config['macPathMap'],logical
  target=Path(config['macPathMap'][logical]);assert target.is_relative_to(ACTUAL) or target.is_relative_to(Path(archive['toolArchiveManifest']).parent),target
  key=json.dumps(ref,sort_keys=True)
  if key not in cache:cache[key]=reader(capture=cap,reference=ref)
  consumed[logical]={'target':str(target),'sha256':sha(cache[key]),'bytes':len(cache[key])}
  return cache[key]
 archive_file_pins={}
 for logical,physical in config['macPathMap'].items():
  target=Path(physical)
  if target.parent.name=='files':
   expected='sha256:'+target.name.split('-',1)[0];assert digest(target)==expected
   archive_file_pins[logical]=expected
 pids={k:[] for k in ('plain','instrumented','compositor','externalAX','externalAXClient')};caps=[];imagehashes=set();times=[]
 for row in summary['runs']:
  rd=directory/f'run-{row["run"]:03d}';cap=load(rd/'capture.json');validate_artifact(cap)
  assert digest(rd/'capture.json')==row['captureHash'];assert cap['case']==summary['case'];assert cap['meta']['run']==row['run']
  assert cap['meta']['conditions']['candidateOnly'] is True and cap['meta']['conditions']['observationalOnly'] is True
  issues=mac_origin_admission_issues(cap,lambda ref:archived(cap,ref));assert not issues,(row['run'],issues)
  origin=cap['meta']['conditions']['macOrigin'];assert canonical_hash(json.loads(archived(cap,origin['case'])))==cap['case']['hash']
  assert archived(cap,origin['source'])==source.read_bytes()
  assert archived(cap,origin['adapter'])==(ROOT/'factory/native/macos/CaptureHost.swift').read_text().replace('__WITNESS_TYPE__',manifest['witnessType']).encode()
  assert archived(cap,origin['auxiliaryAX']['source'])==(ROOT/'factory/native/macos/AXClient.swift').read_bytes()
  assert summary['adapterSourceHash']==digest(ROOT/'factory/native/macos/CaptureHost.swift')
  for mode in ('plain','instrumented','compositor'):
   raw=load(rd/f'{mode}.raw.json');assert type(raw['pid']) is int and raw['pid']>0;pids[mode].append(raw['pid'])
   assert raw['status']=='OBSERVED'
   expected_raw=row['compositorRawHash'] if mode=='compositor' else row[mode]['rawHash'];assert digest(rd/f'{mode}.raw.json')==expected_raw
  ax=load(rd/'external-ax.raw.json');assert ax['status']=='OBSERVED' and ax['permissionRequests'] is False
  assert ax['ownerHash']==summary['binaryHash'] and ax['ownerPath']==origin['binary']['path']
  assert ax['windowTitle']=='SwiftRightFactory-'+summary['case']['id']
  for key,field in [('externalAX','pid'),('externalAXClient','clientPID')]:assert type(ax[field]) is int and ax[field]>0;pids[key].append(ax[field])
  assert digest(rd/'external-ax.raw.json')==row['externalAXRawHash'];assert row['instrumentationPixelsEqual'] is True
  events=cap['events'];raw=load(rd/'instrumented.raw.json');assert [x['timeNs'] for x in events]==[raw['monoStartNs'],raw['monoEndNs']]
  assert raw['monoEndNs']>=raw['monoStartNs'];assert digest(rd/'instrumented.raw.json')==cap['provenance']['sourceHash'];assert canonical_hash(load(rd/'clock.json'))==cap['meta']['clock']['correlationHash']
  owner=load(rd/'owned-window-process.json');assert owner['pid']==ax['pid'] and owner['binaryHash']==ax['ownerHash'] and owner['processGroupOwned'] is True;assert owner['client']['binaryHash']==origin['auxiliaryAX']['binary']['sha256']
  assert cap['tuple']==json.loads(archived(cap,origin['case']))['tuple'];times.append([raw['monoStartNs'],raw['monoEndNs']])
  for image in cap['images']:
   mode=image['id'].split('.')[-1];assert image['hash']==digest(rd/f'{mode}.png')
  imagehashes.add(row['plain']['pngHash']);caps.append(cap['id'])
 assert len(set(sum(pids.values(),[])))==100
 assert caps==archive['captures'] and len(set(caps))==20
 # Reconstruct compressed toolbytes independently & compare exact durable reader targets.
 toolmanifest=Path(archive['toolArchiveManifest']);tools=load(toolmanifest);toolpins=[]
 for entry in tools['entries']:
  physical=toolmanifest.parent/entry['archivePath'];compressed=physical.read_bytes();assert sha(compressed)==entry['archiveSha256'] and len(compressed)==entry['archiveBytes']
  raw=gzip.decompress(compressed) if entry['compression']=='gzip' else compressed
  assert sha(raw)==entry['sha256'] and len(raw)==entry['bytes']
  for logical in set([entry['logicalPath'],entry['realPath']]):
   target=Path(config['macPathMap'][logical]);assert sha(target.read_bytes())==entry['sha256']
  toolpins.append({'logicalPath':entry['logicalPath'],'realPath':entry['realPath'],'sha256':entry['sha256'],'archiveSha256':entry['archiveSha256']})
 # Production outer verifier, unchanged & without CLI write.
 verification=verify(ACTUAL);assert verification['status']=='PASS' and verification['cases'][0]['runs']==20
 return {'status':'CLEAR_ACTUAL_CANDIDATE_ORIGIN_20','scope':'offline read-only actual evidence, real schema/production checker/origin guard; no native/compiler execution','candidateOnly':True,'frozenTupleBound':False,'parityOrPromotionClaim':False,'case':summary['case'],'rootProcess':process,'sourcePins':pins,'productionChecker':verification,'originGuardRuns':20,'captureIds':caps,'independentPIDs':{k:{'count':len(v),'values':v} for k,v in pids.items()},'crossChannelUniquePIDs':100,'offscreenPlainPNGHashes':sorted(imagehashes),'renderClockIntervals':times,'archivedOnlyConsumedReferences':consumed,'configMapEntries':len(config['macPathMap']),'contentAddressedArchivedFilePins':archive_file_pins,'toolArchivePins':toolpins,'mainCompilerReceiptHash':digest(directory/'compiler-receipt.json'),'auxCompilerReceiptHash':digest(ACTUAL/'ax-compiler-receipt.json'),'interpretation':'Fresh Mac source-bound candidates. Historical case tuple sr1-observed-r09 retained as template; root plan identifies current Windows renderer tuple11/runtime374 prospective pairing. No frozen execution tuple, parity or promotion.'}
if __name__=='__main__':
 result=main();(Path(__file__).parent/'report.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps({'status':result['status'],'originGuardRuns':20,'crossChannelUniquePIDs':100,'consumedReferences':len(result['archivedOnlyConsumedReferences'])}))
