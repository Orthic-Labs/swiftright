"""Join measured final artifacts to root-owned native preparer request."""
from pathlib import Path,PureWindowsPath
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','rounded-stroke','stack-overlay','custom-layout','bundled-font'),required=True)
p.add_argument('--revision',type=int,choices=range(1,21),default=1)
p.add_argument('--delivery',choices=('original','centered','circular','observation','colors','boundary','star-observation'),default='centered')
p.add_argument('--mac-revision',type=int,choices=range(1,11),default=1);a=p.parse_args()
repo=Path('/Volumes/D/claude/swiftright');base=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution'
stage_host=a.host+'-'+a.delivery if a.delivery!='original' and a.host in ('rounded-stroke','stack-overlay','custom-layout','bundled-font') or a.host=='image' and a.delivery=='star-observation' else a.host
packet=base/(stage_host+'-compile-r1');actual=packet/'actual-final-r1'
def sha(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=67108864
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for b in iter(lambda:stream.read(1048576),b''):h.update(b)
    return h.hexdigest()
receipt=json.loads((actual/'observation.json').read_text(encoding='utf-8-sig'))
serializer=repo/'factory/native/windows/padding-window-diagnosis-build-v1/dependencies/serializer-actual-r2/control.json'
renderer=repo/'factory/native/windows/staged-renderer-byte-archive-v1/swiftright_render.dll.bin'
assert sha(actual/'FactoryProbe.exe')==receipt['exeSha256']
remote=PureWindowsPath(r'D:\Claude\swiftright\.factory-work\hosts')/stage_host
argv=[str(repo/'factory/.venv/bin/python'),str(base/'prepare-pilot-native-capture-v1.py'),
 '--host',a.host,'--revision',str(a.revision),'--plan',str(packet/'plan-final-v4.json'),
 '--compile-receipt-hash',sha(actual/'observation.json'),
 '--compile-receipt-path',str(remote/'final-r1/observation.json'),
 '--compile-receipt-artifact-path',str(actual/'observation.json'),
 '--exe-hash',receipt['exeSha256'],'--exe-path',receipt['exePath'],'--exe-artifact-path',str(actual/'FactoryProbe.exe'),
 '--serializer-control-hash',sha(serializer),
 '--serializer-control-path',str(PureWindowsPath(r'D:\Claude\swiftright\.factory-work\hosts\rectangle\dependencies\serializer-actual-r2\control.json')),
 '--serializer-control-artifact-path',str(serializer),'--renderer-artifact-path',str(renderer),
 '--case-artifact-path',str(packet/'materialized-case.json')]
if a.host=='rounded-stroke' and a.delivery in ('centered','circular'):
 mac_run=base/f'rounded-stroke-full-viewport-v1/observed-mac20-r{a.mac_revision}/run-001'
 argv+=['--mac-sidecar-receipt-path',str(base/'rounded-stroke-full-viewport-v1/build-r1/receipt.json'),
 '--mac-sidecar-image-path',str(mac_run/'client.png'),
 '--mac-sidecar-manifest-path',str(mac_run/'manifest.json'),
 '--mac-sidecar-observation-path',str(mac_run/'observation.raw.json')]
subprocess.run(argv,timeout=45,check=True)
