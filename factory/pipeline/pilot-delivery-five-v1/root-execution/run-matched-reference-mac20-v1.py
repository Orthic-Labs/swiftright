"""Twenty sequential genuine Mac observations with original process supervision."""
from pathlib import Path
import hashlib,json,subprocess,argparse
ap=argparse.ArgumentParser()
ap.add_argument("--host",choices=("rounded-stroke","custom-layout","stack-overlay"),required=True)
ap.add_argument("--plan",type=Path,required=True)
a=ap.parse_args()

REPO=Path('/Volumes/D/claude/swiftright')
PACKET=REPO/f'factory/pipeline/pilot-delivery-five-v1/root-execution/{a.host}-full-viewport-v1'
INTERNAL=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')/f'{a.host}-full-viewport-r1'
OUT=PACKET/'observed-mac20-r1'
LOGS=REPO/f'.factory-work/root-logs/{a.host}-full-viewport-mac20-r1'
BUILD=PACKET/'build-r1/receipt.json'
PLAN=a.plan if a.plan.is_absolute() else REPO/a.plan
PLAN.resolve().relative_to(REPO)
def raw(p,cap=4*1024*1024):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<=cap
    return p.read_bytes()
def sha(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
build=json.loads(raw(BUILD));prior=json.loads(raw(PLAN))
binary=Path(build['executable']['path'])
assert binary==INTERNAL/'capture-host' and sha(raw(binary))==build['executable']['sha256']
assert prior['sourceHash']==build['sources'][0]['sha256']
assert build['host']==a.host and build['exitCode']==0 and build['originalHandleRetained'] is True
for source in build['sources']:
    assert sha(raw(REPO/source['path']))==sha(raw(Path(source['internalPath'])))==source['sha256']
assert not OUT.exists() and not LOGS.exists()
OUT.mkdir();LOGS.mkdir()
internal=INTERNAL/'mac20-r1';internal.mkdir()
runs=[]
for number in range(1,21):
    name=f'run-{number:03d}';log=LOGS/name;target=OUT/name;png=internal/(name+'.png')
    command=['python3',str(REPO/'factory/tools/supervise-job-v2.py'),'--seconds','15','--rss-mib','1024',
     '--log-mib','2','--out',str(log),'--',str(binary),'--png',str(png),'--scale','2.5']
    result=subprocess.run(command,stdout=subprocess.DEVNULL,timeout=25)
    assert result.returncode==0,f'{name} native job failed; preserve logs'
    observation=json.loads(raw(log/'stdout.bin'));supervision=json.loads(raw(log/'receipt.json'));start=json.loads(raw(log/'start.json'))
    assert supervision['exitCode']==0 and supervision['budgetFailure'] is None
    assert supervision['ownedGroupQuiescent'] is True and supervision['quiescenceKnown'] is True
    assert observation['pid']==start['pid']==supervision['pid']
    assert start['argv']==[str(binary),'--png',str(png),'--scale','2.5']
    assert observation['status']=='OBSERVED' and observation['captureScale']==2.5
    assert observation['viewportPoints']==[320,240] and observation['imagePixels']==[800,600]
    assert observation['hostBoundsPoints']=={'x':0,'y':0,'width':320,'height':240}
    assert observation['pngPath']==str(png)
    assert observation['permissionRequests'] is False and observation['screenCaptureAttempted'] is False
    assert observation['accessibilityAttempted'] is False and observation['inputActions']==0
    assert sha(raw(binary))==build['executable']['sha256']
    target.mkdir();rows=[]
    for source,member in [(png,'client.png'),(log/'stdout.bin','observation.raw.json'),(log/'stderr.bin','stderr.bin'),
                         (log/'receipt.json','supervision.json'),(log/'start.json','original-start.json')]:
        data=raw(source)
        if source.parent==log and source.name in ('stdout.bin','stderr.bin'):
            stream='stdout' if source.name=='stdout.bin' else 'stderr'
            assert supervision[stream]['bytes']==len(data) and 'sha256:'+supervision[stream]['sha256']==sha(data)
        with (target/member).open('xb') as handle:handle.write(data)
        rows.append({'path':member,'bytes':len(data),'sha256':sha(data)})
    manifest={'kind':'factory-full-viewport-mac-count1-archive-v1','rows':rows,
     'sourceHash':build['sources'][0]['sha256'],'hostSourceHash':build['sources'][1]['sha256'],
     'hostHash':build['executable']['sha256'],'buildReceiptPath':str(BUILD.relative_to(REPO)),
     'buildReceiptHash':sha(raw(BUILD)),'case':prior['case'],
     'referenceContext':{'tupleRendererHash':prior['tuple']['rendererHash'],'runtimeCommit':prior['tuple']['runtimeCommit'],
                         'sdk':prior['tuple']['sdk'],'macosBuild':prior['tuple']['macosBuild']},
     'captureScale':2.5,'viewportDip':[320,240],'hostAlignment':'center','hostBackground':'explicit opaque white',
     'qualified':False,'originalPid':observation['pid'],'originalTerminalProof':True,'permissionRequests':False}
    (target/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    runs.append({'run':name,'pid':observation['pid'],'pngHash':rows[0]['sha256'],'manifestHash':sha(raw(target/'manifest.json')),
                 'peakRssBytes':supervision['peakGroupRssBytes'],'seconds':supervision['seconds']})
summary={'host':a.host,'kind':'factory-full-viewport-mac20-v1','case':prior['case'],'sourceHash':build['sources'][0]['sha256'],
 'hostHash':build['executable']['sha256'],'runs':runs,'repeatability':len({r['pngHash'] for r in runs})==1,
 'captureScale':2.5,'viewportDip':[320,240],'qualified':False,'productionArchiveAdmission':'pending-paired-source-case-tuple-joins',
 'processesStarted':20,'allOriginalProcessesTerminal':True,'permissionsRequested':False}
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'runs':len(runs),'repeatability':summary['repeatability'],'allOriginalProcessesTerminal':True,'qualified':False}))
