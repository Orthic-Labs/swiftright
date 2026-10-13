#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
HERE=Path(__file__).parent
report=json.loads((HERE/'assessment.json').read_text())
assert report['kind']=='f12-unmapped-demand-assessment-v1'
assert report['counts']=={'inputDemandRows':107,'unmappedRows':61,'sourceInventoryOnlyRows':46,'assessedRows':61,'catalogueProposals':0,'registryMappings':0}
rows=report['rows']; assert len(rows)==61
keys=[(r['journeyId'],r['demand']) for r in rows]; assert len(set(keys))==len(keys)
for r in rows:
 assert r['status']=='unmapped' and r['sourceAssociationStatus']=='unmapped'
 assert r['sourceProof'] is False and r['proposalStatus']=='none-source-provable'
 assert r['catalogueExactMatches']==[] and r['registryCandidateIds']==[]
 assert r['reasonCode'] in {'swiftui-source-anchor-no-exact-catalogue-binding','cross-product-source-boundary-and-no-exact-catalogue-binding','non-swift-source-boundary'}
 assert r['evidenceRefs']
 for e in r['evidenceRefs']:
  b=Path(e['path'])
  # Source is external to this checkout; validate only recorded digest shape here.
  assert len(e['sha256'])==64 and all(c in '0123456789abcdef' for c in e['sha256'])
for name,info in report['inputs'].items():
 assert info['sha256'].startswith('sha256:') and len(info['sha256'])==71
print('PASS unmapped=61 proposals=0 registry-promotions=0')
