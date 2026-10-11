from pathlib import Path,PurePosixPath
import hashlib,json,tarfile,copy,shutil
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
P=ROOT/'factory/runtime-additions/copy-cost-macos-candidate-v1'
def sha(b):return hashlib.sha256(b).hexdigest()
def get(p):return (ROOT/p).read_bytes()
def js(p):return json.loads(get(p))
def verify(r,pathkey='path',hashkey='sha256',sizekey='bytes'):
 b=get(r[pathkey]);assert sha(b)==r[hashkey] and len(b)==r[sizekey];return b
stage=P/'evidence/corrections-v2/CORRECTION-STAGE-MANIFEST-v2.json';sd=json.loads(stage.read_bytes())
for r in sd['files']:verify(r)
assert sha((P/'STAGE-MANIFEST.json').read_bytes())=='4bebd68a329b55c3c66ef043739bad8ae56970b48b332f8f007b662ad3e89699'
for r in json.loads((P/'STAGE-MANIFEST.json').read_bytes())['files']:verify(r)
c=json.loads((P/'evidence/corrections-v2/correction-v2.json').read_bytes());em=json.loads((P/'evidence/evidence-manifest.json').read_bytes())
for x in c['dynamicLinkageCorrections']:
 b=get(x['capture']);assert len(b)==x['captureBytes'] and sha(b)==x['captureSha256'];separator=b'\n--- stderr ---\n';assert b.count(separator)==1
 stdout,stderr=b.split(separator);assert len(stdout)==x['capturedStdoutBytes'] and len(stderr)==x['capturedStderrBytes']
 actual=next(y for y in em['dynamicLinkage'] if y['variant']==x['variant'])
 assert sha(stdout)==x['capturedStdoutSha256']==actual['stdoutSha256']
 assert sha(stderr)==x['capturedStderrSha256']==actual['stderrSha256']
archive_results=[]
for x in c['frameworkArchiveCorrections']:
 for prefix in ['source','corrected']:
  b=get(x[prefix+'Archive']);assert len(b)==x[prefix+'ArchiveBytes'] and sha(b)==x[prefix+'ArchiveSha256']
 with tarfile.open(ROOT/x['sourceArchive']) as old,tarfile.open(ROOT/x['correctedArchive']) as new:
  om={m.name:m for m in old.getmembers()};nm={m.name:m for m in new.getmembers()};assert len(om)==len(old.getmembers()) and len(nm)==len(new.getmembers())
  alias=x['addedAlias'];assert set(nm)-set(om)=={alias['path']} and set(om)-set(nm)==set()
  a=nm[alias['path']];assert a.issym() and a.linkname==alias['target']=='A'
  for name,m in om.items():
   n=nm[name];assert m.get_info()==n.get_info(),name
   if m.isfile():assert old.extractfile(m).read()==new.extractfile(n).read()
  leaf=x['frameworkLeaf'];data=new.extractfile(leaf).read();assert sha(data)==x['frameworkLeafSha256']
  # Resolve intermediate directory symlink inside archive namespace without filesystem extraction.
  link=next(m for m in nm.values() if m.issym() and m.name==leaf.split('/')[0]+'/'+Path(leaf).name)
  target=str(PurePosixPath(link.name).parent/link.linkname);assert target.startswith(leaf.split('/')[0]+'/Versions/Current/')
  resolved=target.replace(leaf.split('/')[0]+'/Versions/Current/',str(PurePosixPath(alias['path']).parent/alias['target'])+'/')
  assert resolved==leaf and new.extractfile(resolved).read()==data
  archive_results.append({'archive':x['correctedArchive'],'sha256':x['correctedArchiveSha256'],'onlyAddedMember':alias,'leafSha256':sha(data),'regularFileBytesPreserved':True,'topLevelAliasResolvesToVerifiedLeaf':True})
oldreport=ROOT/'factory/runtime-additions/copy-cost-two-host-review-v1/macos-review-v1/report.json';r=json.loads(oldreport.read_bytes())
for name in ['current','candidate']:
 rr=r['results'][name];decl=c['testMethodAccounting'][name]
 assert [rr['methodsExecuted'],rr['methodsPassed'],rr['methodsFailed'],rr['failedAssertions']]==[decl['executedMethods'],decl['passedMethods'],decl['failedMethods'],decl['failedAssertions']]
report={'schema':'copy-cost-macos-correction-independent-review-v2','status':'verified-offline-correction','correctionStageSha256':sha(stage.read_bytes()),'correctionSha256':sha((P/'evidence/corrections-v2/correction-v2.json').read_bytes()),'original21FileStageUnchanged':True,'linkageFraming':{'separatorHex':b'\n--- stderr ---\n'.hex(),'separatorBytes':16,'bothStdoutAndStderrHashesReconstructedExactly':True},'frameworkArchives':archive_results,'methodAccounting':c['testMethodAccounting'],'scope':'V2 resolves framed-output hash interpretation & missing framework directory alias. Static load commands remain static linkage evidence; no runtime loaded-image identities, new execution, causal attribution, production promotion or native qualification.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
for src,dst in [(stage,'correction-stage.json'),(P/'evidence/corrections-v2/correction-v2.json','correction-v2.json')]:shutil.copyfile(src,OUT/'snapshots'/dst)
print(json.dumps(report,indent=2))
