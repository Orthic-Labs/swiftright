"""Prepare internal binary; window execution requires source-bound launch review."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
INTERNAL = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/timing-spike')
def sha(path): return 'sha256:' + hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,value): Path(path).write_text(json.dumps(value,sort_keys=True,indent=2)+'\n')
def owned(command, prefix, timeout=20):
    p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try: stdout,stderr=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGTERM)
        try:stdout,stderr=p.communicate(timeout=3)
        except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate()
        prefix.with_suffix('.stdout.txt').write_text(stdout);prefix.with_suffix('.stderr.txt').write_text(stderr)
        raise RuntimeError('owned timing control timed out')
    prefix.with_suffix('.stdout.txt').write_text(stdout);prefix.with_suffix('.stderr.txt').write_text(stderr)
    return p.returncode,stdout,p.pid
def prepare(out):
    out=out.resolve()
    assert out.is_relative_to(HERE/'evidence') and not out.exists()
    out.mkdir(parents=True)
    work=INTERNAL/str(uuid.uuid4());work.mkdir(parents=True)
    source=work/'TimingControl.swift';source.write_bytes((HERE/'TimingControl.swift').read_bytes())
    binary=work/'timing-control'
    code,_,_=owned(['/usr/bin/xcrun','swiftc','-parse-as-library','-O','-o',str(binary),str(source)],out/'build',120)
    if code:raise RuntimeError('native build failed')
    code,stdout,_=owned([str(binary),'--preflight'],out/'preflight')
    if code:raise RuntimeError('no-prompt preflight failed')
    value={'kind':'independent-macos-timing-control-prepared','scope':'observational adapter control, not case/tuple/parity','preparedAt':datetime.now(timezone.utc).isoformat(),'source':{'path':str(source),'hash':sha(source)},'binary':{'path':str(binary),'hash':sha(binary)},'permissions':json.loads(stdout),'evidenceRoot':str(out),'actualRunLimitSeconds':20,'nativeWatchdogSeconds':12,'nativeStreamSeconds':5}
    write(out/'prepared.json',value);return value
def outcome(code, stdout, rows):
    if code:
        return {'status':'FAILED','reason':f'native process exit {code}'}
    errors=[row.get('message') for row in rows if row.get('kind')=='native-error']
    if errors:
        return {'status':'FAILED','reason':'native capture error','nativeErrors':errors}
    if not rows:
        return {'status':'HELD' if 'HELD:' in stdout else 'FAILED','reason':'native no-prompt grant revoked or run declined' if 'HELD:' in stdout else 'native produced no raw evidence'}
    samples=sum(row.get('kind')=='sample' for row in rows)
    stopped=any(row.get('kind')=='capture-stop-completed' for row in rows)
    if not samples or not stopped:
        return {'status':'HELD','reason':'sample timing or completed stream unavailable','samples':samples}
    return {'status':'SAMPLE_TIMING_OBSERVED','samples':samples,'scope':'native sample timing control; faultcontrol analysis separate'}
def execute(prepared,review):
    p=json.loads(prepared.read_text());r=json.loads(review.read_text())
    assert r.get('approved') is True and r.get('sourceHash')==p['source']['hash'] and r.get('reviewer') in ('root','Oracle')
    assert sha(HERE/'TimingControl.swift')==p['source']['hash'] and sha(p['source']['path'])==p['source']['hash'] and sha(p['binary']['path'])==p['binary']['hash']
    binary=Path(p['binary']['path']).resolve();assert binary.is_relative_to(INTERNAL.resolve())
    out=Path(p['evidenceRoot']).resolve();assert out.is_relative_to(HERE/'evidence') and not (out/'raw.jsonl').exists()
    if p['permissions'].get('screenCaptureGranted') is not True:
        write(out/'hold.json',{'status':'HELD','reason':'no-prompt screen grant absent','permissionRequests':False});return
    write(out/'launch-review.json',r)
    code,stdout,pid=owned([str(binary),'--run','--out',str(out)],out/'run',20)
    rows=[json.loads(line) for line in (out/'raw.jsonl').read_text().splitlines()] if (out/'raw.jsonl').exists() else []
    decision=outcome(code,stdout,rows)
    write(out/'execution.json',{'exit':code,'ownedPID':pid,'binaryHash':sha(binary),'sourceHash':sha(p['source']['path']),'launcherHash':sha(__file__),'reviewHash':sha(review),'rawHash':sha(out/'raw.jsonl') if (out/'raw.jsonl').exists() else None,**decision})
    if decision['status']=='FAILED':raise RuntimeError('native timing control failed')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--prepare',type=Path);parser.add_argument('--prepared',type=Path);parser.add_argument('--review',type=Path);args=parser.parse_args()
    if args.prepare:print(json.dumps(prepare(args.prepare)))
    elif args.prepared and args.review:execute(args.prepared,args.review)
    else:parser.error('provide --prepare or --prepared plus --review')
