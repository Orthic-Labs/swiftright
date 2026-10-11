"""Offline source/record observation only; no native completion or timing qualification."""
import argparse, hashlib, json, pathlib, re
EXPECTED_PLAN_SHA256='9e385e4e50b46c109103cf28b9d8e93be01298fed6c35f2426a1d6a3cdaacef1'
EXPECTED_COMPILE_SHA256='99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8'
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
    # Source &actual compiler bytes close owned identity lineage; neither outcome labels nor timing hashes suffice.
    plan_raw=(root.parent/'plan.json').read_bytes();compile_raw=(root.parent/'observation.json').read_bytes()
    if hashlib.sha256(plan_raw).hexdigest()!=EXPECTED_PLAN_SHA256:raise ValueError('source plan hash mismatch')
    if hashlib.sha256(compile_raw).hexdigest()!=EXPECTED_COMPILE_SHA256:raise ValueError('actual compile receipt hash mismatch')
    plan=json.loads(plan_raw.decode('utf-8-sig'));compiled=json.loads(compile_raw.decode('utf-8-sig'))
    owned_raw=(root/'owned-process.json').read_bytes();original_owned=json.loads(owned_raw.decode('utf-8-sig'))
    if owned!=original_owned or type(owned['pid']) is not int or owned['pid']<=0 or not isinstance(owned['startedAt'],str) or not owned['startedAt']:raise ValueError('original owned process mismatch')
    if owned['path']!=compiled['exePath'] or outcome['exeHash']!=compiled['exeSha256']:raise ValueError('owned actual compiled exe mismatch')
    if outcome['sourceHash']!=plan['sourceHash'] or compiled['sourceHash']!=plan['sourceHash'] or compiled['planSha256']!=EXPECTED_PLAN_SHA256:raise ValueError('source identity mismatch')
    if outcome['compileReceiptHash']!=EXPECTED_COMPILE_SHA256:raise ValueError('outcome actual compile receipt mismatch')
    if outcome['rawHashesQualification']!='sealed-raw' or timing['rawHashesQualification']!='sealed-raw':raise ValueError('raw streams unsealed qualification')
    streams=outcome['rawStreams']
    if not isinstance(streams,list) or len(streams)!=2 or sorted(s['name'] for s in streams)!=['stderr','stdout']:raise ValueError('two exact raw streams required')
    raw_by_name={};raw_hashes={}
    for name in ('stdout','stderr'):
        state=next(s for s in streams if s['name']==name)
        for field in ('copyCompleted','destinationClosed','sealed','taskIsCompleted'):
            if state.get(field) is not True:raise ValueError(name+' raw '+field+' unconfirmed')
        for field in ('taskIsFaulted','taskIsCanceled'):
            if state.get(field) is not False:raise ValueError(name+' raw '+field+' invalid')
        if type(state.get('sourceIsAsync')) is not bool or state.get('taskException')!='' or state.get('taskStatus')!='RanToCompletion' or state.get('closureTaskStatus')!='RanToCompletion' or state.get('hashQualification')!='sealed-raw':raise ValueError(name+' raw terminal state invalid')
        closure=state.get('closure')
        if not isinstance(closure,dict):raise ValueError(name+' raw closure missing')
        for field in ('flushCompleted','destinationClosed','completedWithinDeadline'):
            if closure.get(field) is not True:raise ValueError(name+' raw closure '+field+' unconfirmed')
        if closure.get('deadlineExpired') is not False or closure.get('error')!='':raise ValueError(name+' raw closure failed')
        raw_by_name[name]=(root/('host.'+name+'.txt')).read_bytes();raw_hashes[name]=hashlib.sha256(raw_by_name[name]).hexdigest()
        if raw_hashes[name]!=outcome[name+'Sha256'] or raw_hashes[name]!=timing[name+'Sha256']:raise ValueError(name+' hash mismatch')
    raw=raw_by_name['stdout'];sha=raw_hashes['stdout']
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
    return {'kind':'stack-lifecycle-offline-observation','qualification':'diagnostic-only','outcomeSha256':hashlib.sha256(outcome_bytes).hexdigest(),'timingSha256':hashlib.sha256(timing_bytes).hexdigest(),'stdoutSha256':sha,'stderrSha256':raw_hashes['stderr'],'sourcePlanSha256':EXPECTED_PLAN_SHA256,'compileReceiptSha256':EXPECTED_COMPILE_SHA256,'ownedProcessSha256':hashlib.sha256(owned_raw).hexdigest(),'rawHashesQualification':outcome['rawHashesQualification'],'markers':markers,'markerEventsObserved':[m['event'] for m in markers],'markerCount':len(markers),'sameHandleGetterObservations':getter,'clockSources':{'systemTickMS':'GetTickCount64 millisecond uptime, host &capturer API observations','utcEpochSeconds':'host Date wallclock','Stopwatch':'capturer local ticks/frequency; getter durations only'},'cleanupCertificate':outcome['cleanup'],'primaryError':outcome['primaryError']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    output=pathlib.Path(a.output)
    if output.exists():raise ValueError('fresh analysis output required')
    output.write_text(json.dumps(analyze(a.root),indent=2)+'\n')
