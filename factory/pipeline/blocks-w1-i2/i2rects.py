"""Device-pixel rectangles of the I2 cells (pure Python, shared by i2fit.py and the gate tool factory/tools/pair_resample_report.py). Every edge is floor(v + 0.5) of the layout
position in device pixels (make_cases.py refuses any lead that would put an edge on an exact half pixel, where float noise decides)."""
import math

S = 2.5


def snap(v):
    return math.floor(v + 0.5)


def cell_rects(c):
    """-> dict(image=[x0,y0,x1,y1] the snapped image rect, visible=[...] what can be seen (the clip for a fill, else the image rect), frame=[...] the frame rect)."""
    ox, oy = c["originPx"]
    if not c.get("mode"):
        fw, fh = c["framePx"]
        r = [snap(ox), snap(oy), snap(ox + fw), snap(oy + fh)]
        return dict(image=r, visible=r, frame=r)
    fw, fh = c["fw"], c["fh"]                       # frame in points
    sw, sh = c["sw"] / S, c["sh"] / S               # image in points at scale 2.5
    k = min(fw / sw, fh / sh) if c["mode"] == "fit" else max(fw / sw, fh / sh)
    iw, ih = sw * k, sh * k
    ix, iy = ox + (fw - iw) / 2 * S, oy + (fh - ih) / 2 * S
    image = [snap(ix), snap(iy), snap(ix + iw * S), snap(iy + ih * S)]
    frame = [snap(ox), snap(oy), snap(ox + fw * S), snap(oy + fh * S)]
    visible = image if c["mode"] == "fit" else frame
    return dict(image=image, visible=visible, frame=frame, imageFloat=[ix, iy, iw * S, ih * S])
