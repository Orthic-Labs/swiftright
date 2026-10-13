from pathlib import Path
import hashlib,json
from PIL import Image,ImageChops
b=Path('factory/pipeline/pilot-delivery-five-v1/root-execution')
out=b/'custom-layout-native-capture-count20-r6';native=out/'actual-native-r1/files/native/count20-r1'
mac=b/'custom-layout-original-api-full-viewport-v6/observed-mac20-r1'
def sha(p):
 assert p.is_file() and not p.is_symlink() and p.stat().st_size<4194304
 return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):sha(p);return json.loads(p.read_text(encoding='utf-8-sig'))
coordinator=load(out/'actual-native-r1/files/control-count20-r6/coordinator.json')
assert coordinator['count']==20 and coordinator['status']=='completed-source-bound-observation' and coordinator['lockReleased'] and coordinator['wholeBatchExitConfirmed']
rows=[]
for i in range(1,21):
 w=native/f'native-{i:02d}';m=mac/f'run-{i:03d}'
 mf=load(m/'manifest.json');co=load(w/'capture-outcome.json');ex=load(w/'final-exit-certificate.json')
 assert co['sourceHash'].removeprefix('sha256:')==mf['witnessHash']=='afe77cdfbd5c73943aeebe52c515f2149c7951a4e3512f1678cda6625cdb58f7'
 for r in mf['files']:assert sha(m/r['path'])==r['sha256']
 assert not co['primaryError'] and co['rawHashesQualification']=='sealed-raw'
 assert sha(w/'host.stdout.txt')==co['stdoutSha256'] and sha(w/'host.stderr.txt')==co['stderrSha256']
 assert ex['sample']['kernelBefore']==ex['sample']['kernelAfter']==0 and ex['sample']['getExitCodeSucceeded']
 with Image.open(m/'client.png') as mi,Image.open(w/'native.printwindow.png') as wi:
  im=mi.convert('RGB');iw=wi.convert('RGB');assert im.size==iw.size==(800,600)
  diff=ImageChops.difference(im,iw)
  bounds=lambda img:ImageChops.difference(img,Image.new('RGB',img.size,img.getpixel((0,0)))).getbbox()
  rows.append(dict(run=i,macPNG=sha(m/'client.png'),windowsPNG=sha(w/'native.printwindow.png'),differentPixels=sum(p!=(0,0,0) for p in diff.getdata()),differenceBounds=diff.getbbox(),macContentBounds=bounds(im),windowsContentBounds=bounds(iw),windowsEXE=co['exeHash'],compileReceiptHash=co['compileReceiptHash']))
r=dict(kind='original-custom-layout-count20-full-viewport-comparison-v1',witnessSHA256=mf['witnessHash'],pairedRuns=20,exactRGBRuns=sum(r['differentPixels']==0 for r in rows),rows=rows,lockReleased=True,rawStreamsSealed=True,kernelExitConfirmed=True,normalisation=None,goldenPromoted=False,scope='original selected two-child LTR recipe case; repeatability/closed-lifecycle observed, no full recipe or frozen parity claim')
(out/'original-custom-layout-comparison-r1.json').open('x').write(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='rows'}))
