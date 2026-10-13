#!/usr/bin/env python3
"""Source-only controls for fresh Count20 r11 issuer/guard/launch packet."""
from __future__ import annotations
import copy, hashlib, json, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
BASE=ROOT/'factory/oracle/mac/padding-origin-r11-source-v1'
PACKET=BASE/'windows-replay-count20-r11-source-v2'
MAP=BASE/'windows-replay-count20-r11-source-v1/count20-r11-input-map.pending.json'
EXPECTED_CASE='sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de'
EXPECTED_TUPLE='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011'
def validate(m):
    assert m['status']=='source-ready-fresh-metadata-required'
    assert m['candidateOnly'] is True and m['count']==20
    assert m['freshTuple']['caseHash']==EXPECTED_CASE and m['freshTuple']['tupleID']==EXPECTED_TUPLE
    assert m['freshMetadataContract']['requiredFreshCaseHash']==EXPECTED_CASE
    assert m['freshMetadataContract']['requiredFreshTupleID']==EXPECTED_TUPLE
    assert m['freshMetadataContract']['requiredHistoricalDonorRelabel'] is False
    assert m['freshMetadataContract']['runID'] is None and m['freshMetadataContract']['runRoot'] is None and m['freshMetadataContract']['metadataManifest'] is None
    assert m['effects']=={'compilerActions':0,'nativeWindowActions':0,'remoteActions':0,'lockActions':0}
    assert len(m['executionOverlay']['files'])==9
    return True
def main():
    m=json.loads(MAP.read_text());validate(m)
    faults={}
    for name,mut in [('stale-case',lambda x:x['freshTuple'].__setitem__('caseHash','sha256:'+'0'*64)),('tuple-id-drift',lambda x:x['freshTuple'].__setitem__('tupleID','sr1-source-bound-r11-20261011')),('admit-donor',lambda x:x.__setitem__('candidateOnly',False)),('invented-metadata',lambda x:x['freshMetadataContract'].__setitem__('runID','made-up'))]:
        q=copy.deepcopy(m);mut(q)
        try: validate(q)
        except (AssertionError,KeyError): faults[name]='rejected'
        else: raise AssertionError(name)
    for name in ('issue-count20-fresh-r11.ps1','guard-count20-fresh-r11.ps1','launch-count20-fresh-r11.ps1'):
        text=(PACKET/name).read_text()
        assert 'reuse-admitted-source-equivalent-v4' in text and ('nativeWindowActions' in text or 'nativeActions' in text) and 'fresh' in text.lower()
    print(json.dumps({'status':'PASS','positive':'fresh-r11-source-map','faults':faults,'nativeWindowActions':0,'lockActions':0,'compilerActions':0},sort_keys=True))
if __name__=='__main__':main()
