"""Bounded, exact RGB check; geometry comparison records scale explicitly."""
from pathlib import Path
from collections import Counter
import argparse, hashlib, json
from PIL import Image

p=argparse.ArgumentParser();p.add_argument('--windows-root',type=Path,required=True);p.add_argument('--count',type=int,choices=(1,20),required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
mac=Path('factory/oracle/mac/rectangle-fixed-r11-root-v1/observed-mac20-v2/swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.73250c091e3660b1')
def measure(path,scale):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=4194304
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    with Image.open(path) as image:
        assert image.width*image.height<=2000000
        image=image.convert('RGBA');colors=Counter(image.getdata())
        red={c:n for c,n in colors.items() if c[0]>=180 and c[1]<100 and c[2]<100 and c[3]>=200}
        assert red,'no red pixels'
        color=max(red,key=red.get)
        xs=[];ys=[]
        for y in range(image.height):
            for x in range(image.width):
                if image.getpixel((x,y))==color:xs.append(x);ys.append(y)
        bbox=[min(xs),min(ys),max(xs)+1,max(ys)+1]
        return {'path':str(path),'sha256':h.hexdigest(),'rgba':list(color),'redPixelCount':red[color],'redColors':len(red),'viewportPixels':[image.width,image.height],'scale':scale,'viewportDip':[image.width/scale,image.height/scale],'dominantRedBoundsDip':[v/scale for v in bbox]}
rows=[]
for index in range(1,a.count+1):
    wroot=a.windows_root/('native-%02d'%index)
    pixels=json.loads((wroot/'native.pixels.json').read_text(encoding='utf-8-sig'));scale=pixels['dpi']/96
    w=measure(wroot/'native.printwindow.png',scale)
    repeat=measure(wroot/'native.printwindow.repeat.png',scale)
    mroot=mac/('run-%03d'%index);m=measure(mroot/'plain.png',1)
    metrics=json.loads((mroot/'compositor.raw.json').read_text())
    bounds=metrics['witnessHostMetrics']['boundsPoints'];native_viewport=[bounds['width'],bounds['height']]
    rows.append({'run':index,'mac':m,'macNativeViewportDip':native_viewport,'macNativeMetricsPath':str(mroot/'compositor.raw.json'),'windows':w,'windowsRepeat':repeat,'exactRgba':m['rgba']==w['rgba'],'geometry':m['dominantRedBoundsDip']==w['dominantRedBoundsDip'],'viewport':native_viewport==w['viewportDip'],'windowsPixelsRepeat':w['sha256']==repeat['sha256']})
r={'kind':'factory-rectangle-color-correction-comparison-v1','runs':rows,'comparedCount':a.count,'exactRgbaCount':sum(x['exactRgba'] for x in rows),'geometryCount':sum(x['geometry'] for x in rows),'viewportCount':sum(x['viewport'] for x in rows),'repeatCount':sum(x['windowsPixelsRepeat'] for x in rows),'normalisation':'none; dimensions divided by recorded host scale','qualified':False,'sourceHash':'sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d'}
with a.output.open('x') as f:json.dump(r,f,indent=2);f.write('\n')
print(json.dumps({k:v for k,v in r.items() if k!='runs'}))
