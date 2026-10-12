"""Strict full-client paint comparison & necessary placement/artifact fault controls.

No pixel resampling, color normalization, masks, or synthetic qualification.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

def read(path, cap=4*1024*1024):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap
    return path.read_bytes()

def image(path):
    with Image.open(path) as source:
        assert source.width*source.height<=2_000_000
        return source.convert('RGBA')

def evaluate(left,right,left_scale,right_scale,left_viewport,right_viewport):
    scale=left_scale==right_scale and left_scale>0
    viewport=left_viewport==right_viewport
    size=left.size==right.size
    actual_size=list(left.size)==[int(x*left_scale) for x in left_viewport]
    actual_size=actual_size and list(right.size)==[int(x*right_scale) for x in right_viewport]
    # Checking every RGBA byte also detects holes & non-witness artifacts.
    exact=size and hashlib.sha256(left.tobytes()).digest()==hashlib.sha256(right.tobytes()).digest()
    return {'scaleAgrees':scale,'viewportAgrees':viewport,'imageSizeAgrees':size,
            'sizeJoinsRecordedScale':actual_size,'exactRgbaBytes':exact,
            'paintAgrees':bool(scale and viewport and size and actual_size and exact)}

parser=argparse.ArgumentParser()
parser.add_argument('--mac-archive',type=Path,required=True)
parser.add_argument('--windows-run',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
m=json.loads(read(args.mac_archive/'manifest.json'))
raw=json.loads(read(args.mac_archive/'observation.raw.json'))
for row in m['rows']:
    data=read(args.mac_archive/row['path'])
    assert len(data)==row['bytes'] and 'sha256:'+hashlib.sha256(data).hexdigest()==row['sha256']
assert raw['captureScale']==m['captureScale'] and raw['viewportPoints']==m['viewportDip']
left=image(args.mac_archive/'client.png')
w=json.loads(read(args.windows_run/'native.pixels.json'))
right=image(args.windows_run/'native.printwindow.png')
right_scale=w['dpi']/96
assert w["width"]>0 and w["height"]>0 and right_scale>0
right_viewport=[w["width"]/right_scale,w["height"]/right_scale]
actual=evaluate(left,right,m['captureScale'],right_scale,m['viewportDip'],right_viewport)
actual['windowsRecordedClientPixels']=[w['width'],w['height']]
actual['windowsImageJoinsClientRect']=list(right.size)==[w['width'],w['height']]
actual['paintAgrees']=actual['paintAgrees'] and actual['windowsImageJoinsClientRect']
if left.size==right.size:
    difference=ImageChops.difference(left,right)
    channels=difference.split();mask=channels[0]
    for channel in channels[1:]:mask=ImageChops.lighter(mask,channel)
    actual['differingPixelCount']=sum(1 for pixel in mask.getdata() if pixel!=0)
    actual['differingPixelBounds']=mask.getbbox()
else:
    actual['differingPixelCount']=None;actual['differingPixelBounds']=None
paint_pixel=next(((n%left.width,n//left.width) for n,pixel in enumerate(left.getdata()) if pixel!=(255,255,255,255)),None)
assert paint_pixel is not None,'reference has no witness paint on explicit white viewport'
controls=[]
assert evaluate(left,left.copy(),2.5,2.5,[320,240],[320,240])['paintAgrees']
controls.append({'name':'synthetic-identical-positive','passes':True,'nativeEvidence':False})
for name,kind in [('mac-placement-shift','shift'),('red-pixel-hole','hole'),
                  ('unexpected-background-artifact','artifact'),('one-color-byte','color'),
                  ('wrong-recorded-scale','scale'),('wrong-recorded-client-size','viewport')]:
    changed=left.copy();scale=2.5;viewport=[320,240]
    if kind=='shift':changed=ImageChops.offset(changed,2,0)
    elif kind=='hole':changed.putpixel(paint_pixel,(255,255,255,255))
    elif kind=='artifact':changed.putpixel((30,30),(0,255,0,255))
    elif kind=='color':pixel=changed.getpixel(paint_pixel);changed.putpixel(paint_pixel,((pixel[0]+1)%256,*pixel[1:]))
    elif kind=='scale':scale=1.0
    else:viewport=[319,240]
    verdict=evaluate(changed,left,scale,2.5,viewport,[320,240])
    assert not verdict['paintAgrees'],name+' fault escaped production predicate'
    controls.append({'name':name,'rejected':True,'nativeEvidence':False})
report={'kind':'factory-full-viewport-paint-comparison-v2','macArchive':str(args.mac_archive),
        'windowsRun':str(args.windows_run),'actual':actual,'faultControls':controls,
        'normalisation':'none; compare all RGBA bytes at identical recorded raster scale',
        'qualified':False,'eligibility':'diagnostic; exact source/case/tuple/production-reader joins pending',
        'nativeActions':0}
with args.output.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
