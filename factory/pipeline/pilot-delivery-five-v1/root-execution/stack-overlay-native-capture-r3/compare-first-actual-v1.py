"""Bounded diagnostic of exact archived Stack pixels; no normalisation."""
from pathlib import Path
import hashlib, json
from PIL import Image, ImageChops
root = Path('/Volumes/D/claude/swiftright')
base = root / 'factory/pipeline/pilot-delivery-five-v1/root-execution'
out = Path(__file__).parent
mac_root = base / 'stack-overlay-full-viewport-v1/observed-mac20-r1'
mac = mac_root / 'run-001/client.png'
win = out / 'actual-native-r1/files/native/count1-r1/native-01/native.printwindow.png'
def digest(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size <= 4194304
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''): h.update(chunk)
    return h.hexdigest()
m = json.loads((mac_root / 'manifest.json').read_text())
row = next(r for r in m['rows'] if r['path'] == 'run-001/client.png')
assert row['bytes'] == mac.stat().st_size and row['sha256'].removeprefix('sha256:') == digest(mac)
w = json.loads((out/'actual-native-r1/actual-native-centered-count1-manifest.json').read_text(encoding='utf-8-sig'))
wr = next(r for r in w['files'] if r['path'] == 'native/count1-r1/native-01/native.printwindow.png')
assert wr['bytes'] == win.stat().st_size and wr['sha256'] == digest(win)
a, b = Image.open(mac).convert('RGB'), Image.open(win).convert('RGB')
assert a.size == b.size == (800,600)
d = ImageChops.difference(a,b)
report = dict(mac=str(mac.relative_to(root)), windows=str(win.relative_to(root)),
    macSha256=digest(mac), windowsSha256=digest(win), size=list(a.size),
    differentPixels=sum(p != (0,0,0) for p in d.getdata()), differenceBounds=d.getbbox(),
    nonWhiteBounds=[ImageChops.difference(i,Image.new('RGB',i.size,'white')).getbbox() for i in (a,b)],
    centerRGB=[i.getpixel((400,300)) for i in (a,b)],
    witnessSha256=m['witnessSha256'], normalisation=None, qualified=False)
with (out/'first-pixel-comparison-v1.json').open('x') as f: json.dump(report,f,indent=2); f.write('\n')
print(json.dumps(report))
