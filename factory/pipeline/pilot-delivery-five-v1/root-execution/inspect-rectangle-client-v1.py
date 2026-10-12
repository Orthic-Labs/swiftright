"""Inspect actual full-client paint without claiming cropped-witness placement."""
from collections import Counter
import hashlib
import json
from pathlib import Path
from PIL import Image

base = Path('factory/oracle/mac/rectangle-fixed-r11-root-v1/observed-mac20-v2/swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.73250c091e3660b1/run-001')
windows = Path('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-count20-r2/actual-native-r1/files/native/count20-r1/native-01')

def read(path, cap=4*1024*1024):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size <= cap
    return path.read_bytes()

def inspect(path, scale, viewport=None):
    raw = read(path)
    with Image.open(path) as source:
        assert source.width * source.height <= 2_000_000
        image = source.convert('RGBA')
        crop = [0, 0, image.width, image.height]
        if viewport:
            width, height = [int(value * scale) for value in viewport]
            assert width == image.width and 0 < height <= image.height
            crop = [0, image.height - height, width, image.height]
            image = image.crop(crop)
        colors = Counter(image.getdata())
        reds = {color: count for color, count in colors.items()
                if color[0] >= 180 and color[1] < 100 and color[2] < 100 and color[3] >= 200}
        assert reds
        color = max(reds, key=reds.get)
        left, top, right, bottom = image.width, image.height, -1, -1
        for index, pixel in enumerate(image.getdata()):
            if pixel == color:
                x, y = index % image.width, index // image.width
                left, top, right, bottom = min(left,x), min(top,y), max(right,x), max(bottom,y)
        return {'path': str(path), 'sha256': 'sha256:'+hashlib.sha256(raw).hexdigest(),
                'scale': scale, 'clientCropPixels': crop,
                'clientPixels': list(image.size), 'dominantRedRgba': list(color),
                'dominantRedBoundsDip': [value/scale for value in (left,top,right+1,bottom+1)],
                'dominantRedPixels': reds[color],
                'topColors': [{'rgba':list(c),'pixels':n} for c,n in colors.most_common(8)],
                'qualification': False,
                'cropRule': 'native window image minus measured content height; titlebar only'}

metrics = json.loads(read(base/'compositor.raw.json'))
scale = metrics['image']['scale']
bounds = metrics['witnessHostMetrics']['boundsPoints']
mac = inspect(base/'compositor.png', scale, [bounds['width'],bounds['height']])
win_metrics = json.loads(read(windows/'native.pixels.json'))
win = inspect(windows/'native.printwindow.png', win_metrics['dpi']/96)
result = {'kind':'factory-full-client-rectangle-diagnosis-v1','mac':mac,'windows':win,
          'clientRgbaAgrees':mac['dominantRedRgba']==win['dominantRedRgba'],
          'clientShapeBoundsAgree':mac['dominantRedBoundsDip']==win['dominantRedBoundsDip'],
          'qualified':False,'nativeActions':0}
out=Path('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-full-client-diagnosis-r1.json')
with out.open('x') as stream:json.dump(result,stream,indent=2);stream.write('\n')
print(json.dumps(result))
