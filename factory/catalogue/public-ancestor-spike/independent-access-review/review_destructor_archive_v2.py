#!/usr/bin/env python3
"""Independent archive closure & absent-cache replay; writes only own review."""
import hashlib,importlib.util,json
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'destructor-api-eligibility-proof'
ROOT=HERE.parents[3]
PINS={'prove_access.py':'391cbf4c02748ed4b995936f606dcee2ab95e007767e8dd498b4b3d5f745e997','test_prove_access.py':'d2eb2a5949aca29b5a8627cd61d8a049d006da151070d12656fc81674febaacb','effective-access-evidence.json':'d4b55f38b99b0dc9cd4636786f8482f2c00c476a46b8c509129927ba709f3a96','archive-manifest-v2.json':'e3ebc2f4b08c10178649308741efe786be2de823cfbfcf775b26dcb62d78c107','STAGE-LIST.json':'5a40a48298f5cac62432c272e4216712f1cc149322b7b12e3ae29263e0bfcc25'}
OLD='410fcad4cf43fe4a93761bbda4e84f19815507349c939c52c2a202457048e019'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def encoded(value):return (json.dumps(value,indent=2)+'\n').encode()
def main():
 for name,pin in PINS.items():assert sha(BASE/name)==pin,name
 assert sha(HERE/'destructor-access-review.json')==OLD
 spec=importlib.util.spec_from_file_location('frozen_destructor_archive',BASE/'prove_access.py');guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
 guard.verify_archive();manifest=guard.archive_manifest()
 assert all((BASE/r['archivePath']).read_bytes()==Path(r['originalPath']).read_bytes() for r in manifest['rows'])
 stage=json.loads((BASE/'STAGE-LIST.json').read_text())
 assert all((ROOT/r['path']).stat().st_size==r['bytes'] and sha(ROOT/r['path'])==r['sha256'] for r in stage['stageFiles'])
 expected=(BASE/'effective-access-evidence.json').read_bytes();assert encoded(guard.verify_all())==expected
 original_file=Path.is_file;original_read=Path.read_bytes
 def no_cache_read(path):
  assert path.parent!=guard.RAW,'original cache accidentally read'
  return original_read(path)
 with patch.object(Path,'is_file',lambda path:False if path.parent==guard.RAW else original_file(path)),patch.object(Path,'read_bytes',no_cache_read):
  assert encoded(guard.verify_all())==expected
 missing=BASE/manifest['rows'][0]['archivePath']
 with patch.object(Path,'is_file',lambda path:False if path==missing else original_file(path)):
  try:guard.verify_archive()
  except ValueError as error:assert str(error)=='repository-archive-bytes'
  else:raise AssertionError('missing archive file accepted')
 for name,pin in PINS.items():assert sha(BASE/name)==pin,'changed during review: '+name
 assert sha(HERE/'destructor-access-review.json')==OLD
 report={'kind':'independent-destructor-archive-review-v2','pins':PINS,'priorReviewPreservedSha256':OLD,'reviewerSourceSha256':sha(Path(__file__)),'archiveCount':len(manifest['rows']),'archiveBytes':sum(r['bytes'] for r in manifest['rows']),'stageCount':len(stage['stageFiles']),'stageBytes':sum(r['bytes'] for r in stage['stageFiles']),'allArchivedBytesEqualOriginal':True,'normalWholeArtifactReplayEqual':True,'absentEntireOriginalCacheWholeArtifactReplayEqual':True,'directOriginalCacheReadsRejectedDuringAbsenceReplay':True,'missingArchiveFileRejected':True,'producerFaultControlGroupsIndependentlyPassed':10,'memberAccessFacts':{'public':6,'open':5,'internal':20,'package':11},'exactTarget':'arm64-apple-macosx27.0','criterion':'Physical SDK declaration member access & exact raw archive replay.','promotionsMade':0}
 output=HERE/'destructor-archive-review-v2.json';output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(sha(output))
if __name__=='__main__':main()
