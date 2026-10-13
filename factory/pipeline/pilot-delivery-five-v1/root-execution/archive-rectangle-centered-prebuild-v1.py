"""Bounded read-only archive of successful or failed centered compiler evidence."""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--attempt',type=int,choices=range(5,11),default=5)
p.add_argument('--phase',choices=('prebuild','final'),default='prebuild');a=p.parse_args()
base=Path('/Volumes/D/claude/swiftright/factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-build-r1')
out=base/f'archive-{a.phase}-r{a.attempt}';out.mkdir()
remote=f'D:/Claude/swiftright/.factory-work/hosts/rectangle/{a.phase}-r{a.attempt}'
def sha(path,cap=8388608):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for b in iter(lambda:stream.read(1048576),b''):h.update(b)
    return h.hexdigest()
for name in ('observation.json','compile.stdout.bin','compile.stderr.bin'):
    subprocess.run(['scp','-q','win:'+remote+'/'+name,str(out/name)],timeout=20,check=True)
r=json.loads((out/'observation.json').read_text(encoding='utf-8-sig'))
assert r['phase']==a.phase
assert r['ownedExited'] and r['originalHandleRetained'] and r['kernelWait']==0
assert r['streamsSealed'] and r['streamDrainComplete'] and r['jobActiveCount']==r['cleanupJobActive']==0
for stream in ('stdout','stderr'):
    path=out/('compile.'+stream+'.bin')
    assert path.stat().st_size==r[stream+'Bytes'] and sha(path)==r[stream+'Sha256']
if r['exitCode']==0:
    assert r['exePath'].startswith('D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle\\package\\')
    subprocess.run(['scp','-q','win:'+r['exePath'].replace('\\','/'),str(out/'FactoryProbe.exe')],timeout=20,check=True)
    assert sha(out/'FactoryProbe.exe',67108864)==r['exeSha256'] and (out/'FactoryProbe.exe').stat().st_size==r['exeBytes']
    if a.phase=='final':
        planpath=base/'import-fix-r2/centered-final-prep-r6/plan-final-v4.json'
        assert sha(planpath)==r['planSha256']
        plan=json.loads(planpath.read_text())
        assert plan['case']==r['case'] and plan['expectedHostHash']=='sha256:'+r['exeSha256']
summary={'exitCode':r['exitCode'],'error':r['error'],'streamsSealed':True,'ownedExited':True,
 'receiptSha256':sha(out/'observation.json'),'qualified':False,'remoteRoot':remote,'attempt':a.attempt}
(out/'archive-summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
