"""
Waybill form rebrand: covers the old logo marks of the source form (NP2.png,
1254 px, kept off the repo) and puts the Delirium Express logo in the header,
on the warehouse wall and on the truck. Then 1024 px, 256-colour palette:

  python rebrand_waybill.py NP2.png delirium_express_logo.png full.png
  -> resize + quantize into media/ui/DelNP_Waybill_UA.png
"""
import sys
import numpy as np
from PIL import Image, ImageFilter
src, logo_path, out_full = sys.argv[1:4]
im = Image.open(src).convert("RGB")
logo = Image.open(logo_path).convert("RGBA")
a = np.asarray(im).astype(float)

def fill(box, bad, blur=18):
    """Replace 'bad' pixels in box by a normalized blur of the good ones."""
    x0, y0, x1, y1 = box
    reg = a[y0:y1, x0:x1]
    good = (~bad).astype(float)
    out = reg.copy()
    def k(ch):
        for _ in range(3):
            for ax in (0, 1):
                p = np.pad(ch, [(blur, blur) if i == ax else (0, 0) for i in (0, 1)], mode="edge")
                c = np.cumsum(p, axis=ax)
                c = np.concatenate([np.zeros_like(np.take(c, [0], axis=ax)), c], axis=ax)
                n = ch.shape[ax]
                ch = (np.take(c, range(2 * blur + 1, 2 * blur + 1 + n), axis=ax) - np.take(c, range(0, n), axis=ax)) / (2 * blur + 1)
        return ch
    wsum = k(good)
    for c in range(3):
        est = k(reg[:, :, c] * good) / np.maximum(wsum, 1e-3)
        out[:, :, c] = np.where(bad, est, reg[:, :, c])
    a[y0:y1, x0:x1] = out

def red(reg): return (reg[:, :, 0] > reg[:, :, 1] + 60)

def sub(box): x0, y0, x1, y1 = box; return a[y0:y1, x0:x1]

# 1. header: old logo (red) on paper
hb = (34, 34, 672, 280)
r = sub(hb); m = r[:, :, 0] > r[:, :, 1] + 45; m = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(11))) > 0
fill(hb, m, 30)
# 2. warehouse wall emblem (red on paper)
wb = (262, 1002, 392, 1100)
m = red(sub(wb)); m = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
fill(wb, m, 14)
# 3. truck panel: white emblem on red
tb = (880, 985, 1040, 1135)
r = sub(tb); m = (r.sum(axis=2) > 420) & ~red(r)
m = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
fill(tb, m, 14)

res = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
def put(cx, cy, w):
    lg = logo.resize((w, round(w * logo.height / logo.width)), Image.LANCZOS)
    res.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))
put(353, 157, 500)
put(325, 1043, 180)
put(948, 1062, 225)
res = res.convert("RGB")
res.save(out_full)
