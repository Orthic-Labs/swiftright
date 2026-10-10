"""Analyze raw native timing control; no GPU-completion or scanout inference."""
import argparse
from collections import Counter
from decimal import Decimal
import hashlib
import json
from pathlib import Path

def ns(ticks, scale):return Decimal(ticks)*scale['numer']/scale['denom']
def summary(root):
    rows=[json.loads(line) for line in (root/'raw.jsonl').read_text().splitlines()]
    samples=[r for r in rows if r['kind']=='sample']
    mutations=[r for r in rows if r['kind']=='content-mutation-submit']
    begin=next((r for r in rows if r['kind']=='producer-stall-begin'),None)
    end=next((r for r in rows if r['kind']=='producer-stall-end'),None)
    scale=rows[0]['clocks']['machTimebase']
    during=[r for r in samples if begin and end and begin['clocks']['machAfter'] < r['callbackEntryClocks']['machBefore'] < end['clocks']['machBefore']]
    checks=[]
    ages=[]
    for r in samples:
        c=r['callbackEntryClocks']
        checks.append(c['machBefore'] <= c['cmHostSystemUnits'] <= c['machAfter'])
        if r.get('windowServerDisplayMachTime',0)>0:
            ages.append({'index':r['index'],'lowNs':str(ns(c['machBefore']-r['windowServerDisplayMachTime'],scale)),'highNs':str(ns(c['machAfter']-r['windowServerDisplayMachTime'],scale))})
    hashes={r['pixels']['sha256'] for r in samples if r.get('pixels')}
    packed=[r for r in samples if r.get('pixels',{}).get('pixelFormat')==1111970369 and r.get('pixelBufferIsPlanar') is False and r.get('pixelLockStatus')==0]
    packed_hashes={r['pixels']['sha256'] for r in packed}
    gaps=[b['clocks']['dispatchUptimeNs']-a['clocks']['dispatchUptimeNs'] for a,b in zip(mutations,mutations[1:])]
    value={'kind':'independent-native-timing-control-analysis','scope':'observational control; not frozen/case/parity evidence','samples':len(samples),'frameStatusRawCounts':dict(Counter(str(r.get('frameStatusRaw','missing')) for r in samples)),'contentMutations':len(mutations),'uniqueCapturedPixelHashes':len(hashes),'knownContentMutationObserved':len(hashes)>1,'rawClockCorrelation':{'machTimebase':scale,'cmHostSystemUnitsBracketedAtCallbackEntry':sum(checks),'callbackSamples':len(checks),'streamSynchronizationClockAvailable':sum(r.get('streamClockAvailable') is True for r in samples),'convertedPresentationHostTimeValid':sum(r.get('presentationConvertedToHost',{}).get('valid') is True for r in samples)},'intentionalProducerStall':{'requestedNs':begin.get('intentionalDurationNs') if begin else None,'measuredNs':end['clocks']['dispatchUptimeNs']-begin['clocks']['dispatchUptimeNs'] if begin and end else None,'largestMutationGapNs':max(gaps) if gaps else None,'sampleCallbacksEnteredDuringStall':len(during),'frameStatusesDuringStall':dict(Counter(str(r.get('frameStatusRaw','missing')) for r in during))},'windowServerEventAgeBoundsAtCallbackEntryNs':ages,'timestampSemantics':{'appkitDrawReturn':'CPU draw callback return only','samplePresentation':'CMSampleBuffer PTS; synchronizationClock conversion archived separately','windowServerDisplayMachTime':'SDK-documented WindowServer display event in mach absolute ticks; not physical scanout','callbackEntry':'consumer callback entry bracketed host clocks','GPUCompletion':'UNAVAILABLE','physicalDisplayScanout':'UNAVAILABLE'},'nativeErrors':[r for r in rows if r['kind']=='native-error'],'sourceHash':'sha256:'+hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'rawHash':'sha256:'+hashlib.sha256((root/'raw.jsonl').read_bytes()).hexdigest()}
    value['faultControlStatus']='PASS' if begin and end and len(hashes)>1 and value['intentionalProducerStall']['measuredNs']>=350_000_000 and gaps and max(gaps)>=350_000_000 else 'INCOMPLETE'
    value['uniqueCapturedByteRegionHashes']=value.pop('uniqueCapturedPixelHashes')
    value['knownContentMutationObserved']=len(packed_hashes)>1
    value['validatedPackedBGRASamples']=len(packed)
    value['validatedPackedBGRAPixelHashVariants']=len(packed_hashes)
    value['pixelReadScope']='verified nonplanar packed BGRA/lock-success only; legacy planar base-address hashes unqualified'
    value['producerStallControlStatus']='PASS' if begin and end and value['intentionalProducerStall']['measuredNs']>=350_000_000 and gaps and max(gaps)>=350_000_000 else 'INCOMPLETE'
    if not value['knownContentMutationObserved']:value['faultControlStatus']='INCOMPLETE'
    value['durationAndDecodeAvailability']={'validDurations':sum(r['duration']['valid'] for r in samples),'validDecodeTimes':sum(r['decodeTime']['valid'] for r in samples)}
    differences=[ns(r['presentationHostSystemUnits']-r['windowServerDisplayMachTime'],scale) for r in samples if r.get('presentationHostSystemUnits') and r.get('windowServerDisplayMachTime')]
    value['convertedPTSMinusWindowServerEventNs']={'count':len(differences),'min':str(min(differences)) if differences else None,'max':str(max(differences)) if differences else None,'scope':'observed API-converted host time versus native event tick value; not scanout'}
    (root/'analysis.json').write_text(json.dumps(value,sort_keys=True,indent=2)+'\n');return value
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);args=parser.parse_args()
    v=summary(args.root);print(json.dumps({k:v[k] for k in ('samples','validatedPackedBGRAPixelHashVariants','intentionalProducerStall','faultControlStatus')}))
