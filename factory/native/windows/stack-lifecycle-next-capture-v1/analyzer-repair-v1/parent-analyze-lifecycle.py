"""Offline source/record observation only; no native completion or timing qualification."""
import argparse, hashlib, json, pathlib, re
PATTERN = re.compile(r'^FACTORY_LIFECYCLE event=(\S+) utcEpochSeconds=([0-9.]+) tickMS=(\d+) pid=(\d+) thread=(\d+)$')
def analyze(root):
    root=pathlib.Path(root)
    timing_bytes=(root/'lifecycle-timing.json').read_bytes()
    outcome_bytes=(root/'capture-outcome.json').read_bytes()
    timing=json.loads(timing_bytes.decode('utf-8-sig'));outcome=json.loads(outcome_bytes.decode('utf-8-sig'))
    owned=outcome['ownedIdentity']
    if timing['ownedIdentity']!=owned: raise ValueError('timing owned identity mismatch')
    for key in ('compileReceiptHash','exeHash','stdoutSha256','stderrSha256'):
        if timing[key]!=outcome[key]: raise ValueError('timing/outcome hash join mismatch')
    streams=[s for s in outcome['rawStreams'] if s['name']=='stdout']
    if len(streams)!=1 or streams[0]['destinationClosed'] is not True: raise ValueError('stdout destination closure unconfirmed')
    raw=(root/'host.stdout.txt').read_bytes();sha=hashlib.sha256(raw).hexdigest()
    if sha!=outcome['stdoutSha256']: raise ValueError('stdout hash mismatch')
    markers=[]
    for number,line in enumerate(raw.decode('utf-8-sig').splitlines(),1):
        match=PATTERN.fullmatch(line)
        if not match: continue
        event,utc,tick,pid,thread=match.groups()
        if int(pid)!=owned['pid']: raise ValueError('lifecycle marker PID mismatch')
        markers.append({'line':number,'event':event,'utcEpochSeconds':utc,'systemTickMS':int(tick),'pid':int(pid),'thread':int(thread)})
    samples=timing['observations'];getter=[]
    for s in samples:
        if s['retainedHandle']<=0 or s['handlePid']!=owned['pid']:raise ValueError('retained kernel identity mismatch')
        if not(s['queryStartTicks']<=s['hasExitedStartTicks']<=s['hasExitedEndTicks']<=s['queryEndTicks']):raise ValueError('query chronology invalid')
        if s['frequency']<=0:raise ValueError('unknown Stopwatch frequency')
        getter.append({'phase':s['phase'],'hasExitedCallMS':(s['hasExitedEndTicks']-s['hasExitedStartTicks'])*1000/s['frequency'],'kernelBefore':s['kernelBefore'],'kernelAfter':s['kernelAfter'],'getExitCodeSucceeded':s['getExitCodeSucceeded'],'exitCode':s['exitCode'],'errors':s['errors']})
    return {'kind':'stack-lifecycle-offline-observation','qualification':'diagnostic-only','outcomeSha256':hashlib.sha256(outcome_bytes).hexdigest(),'timingSha256':hashlib.sha256(timing_bytes).hexdigest(),'stdoutSha256':sha,'rawHashesQualification':outcome['rawHashesQualification'],'markers':markers,'markerEventsObserved':[m['event'] for m in markers],'markerCount':len(markers),'sameHandleGetterObservations':getter,'clockSources':{'systemTickMS':'GetTickCount64 millisecond uptime, host &capturer API observations','utcEpochSeconds':'host Date wallclock','Stopwatch':'capturer local ticks/frequency; getter durations only'},'cleanupCertificate':outcome['cleanup'],'primaryError':outcome['primaryError']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    output=pathlib.Path(a.output)
    if output.exists():raise ValueError('fresh analysis output required')
    output.write_text(json.dumps(analyze(a.root),indent=2)+'\n')
