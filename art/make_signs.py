"""
Nova Poshta wall signs: the logo mark, the wordmark (two tiles) and digits
0-9 for the branch number, each as a red plate hung high on a wall.

Every sign comes in two sprites: Facing S (on a north wall, the right-hand
edge of the tile) and Facing E (on a west wall, the left-hand edge). Plates
run edge to edge, so signs placed side by side along a wall read as one
board: [mark][НОВА][ПОШТА][1][2].

Frames are 128x256 (2x); the floor diamond's top corner is at (64, 192), one
storey is 192 px. Rendered at 4x and scaled down.

  python make_signs.py      -> art/signs/*.png and art/signs/tiles.json
then
  build-tilepack.ps1 -Spec art/signs/tiles.json -Media <mod>/42/media
"""
import json
import os
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "signs")
LOGO = os.path.join(HERE, "Nova_Poshta_2022_logo.png")
FONT = r"C:\Windows\Fonts\seguibl.ttf"

S = 4                       # supersampling
Z0, Z1 = 136, 182           # plate bottom / top above the floor, 2x px
OFF = 0.03                  # out from the wall, in tiles
RED = (218, 41, 28, 255)
RED_DARK = (150, 24, 16, 255)
TEX_W, TEX_H = 288, 184     # plate texture for one tile (4x)


def plate(width_tiles=1):
    im = Image.new("RGBA", (TEX_W * width_tiles, TEX_H), RED)
    d = ImageDraw.Draw(im)
    edge = 10
    d.rectangle([0, 0, im.width, edge], fill=RED_DARK)
    d.rectangle([0, TEX_H - edge, im.width, TEX_H], fill=RED_DARK)
    return im


def white_from_red(img):
    """The logo's red as a white shape on transparency."""
    img = img.convert("RGBA")
    red = img.getchannel("G").point(lambda g: max(0, min(255, int((255 - g) * 255 / 220))))
    alpha = ImageChops.multiply(red, img.getchannel("A"))
    out = Image.new("RGBA", img.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out.crop(out.getbbox())


def paste_centered(dst, src, max_w, max_h, cx=None):
    k = min(max_w / src.width, max_h / src.height)
    src = src.resize((max(1, int(src.width * k)), max(1, int(src.height * k))), Image.LANCZOS)
    cx = dst.width / 2 if cx is None else cx
    dst.alpha_composite(src, (int(cx - src.width / 2), int((dst.height - src.height) / 2)))


def on_wall(tex, facing):
    """The plate texture laid onto the wall face of one 128x256 frame."""
    W, H = tex.size
    hz = Z1 - Z0
    if facing == "S":   # north wall: (64,192) -> (128,224); out = +y = (-64,+32) per tile
        x0, y0, dy = 64 - 64 * OFF, 192 + 32 * OFF, 32
    else:               # west wall: (0,224) -> (64,192); out = +x = (+64,+32) per tile
        x0, y0, dy = 0 + 64 * OFF, 224 + 32 * OFF, -32
    # Output pixel (X, Y) at 4x -> texture (s, t): X = S*x0 + S*64*s/W,
    # Y = S*(y0 - Z1) + S*dy*s/W + S*hz*t/H. Inverse, as PIL wants it:
    a = W / (S * 64)
    c = -x0 * W / 64
    # t = (Y - S*(y0 - Z1) - dy*(X - S*x0)/64) * H/(S*hz)
    kt = H / (S * hz)
    d = -dy / 64 * kt
    e = kt
    f = (-S * (y0 - Z1) + dy * S * x0 / 64) * kt
    big = tex.transform((128 * S, 256 * S), Image.AFFINE, (a, 0, c, d, e, f),
                        resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0))
    return big.resize((128, 256), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    logo = Image.open(LOGO)
    lw, lh = logo.size
    mark = white_from_red(logo.crop((0, 0, int(lw * 0.36), lh)))
    word = white_from_red(logo.crop((int(lw * 0.36), 0, lw, lh)))
    font = ImageFont.truetype(FONT, int(TEX_H * 0.95))

    signs = []                       # (custom name, texture)
    p = plate()
    paste_centered(p, mark, TEX_W * 0.8, TEX_H * 0.78)
    signs.append(("Logo", p))

    p = plate(2)
    paste_centered(p, word, p.width * 0.86, TEX_H * 0.74)
    signs.append(("WordLeft", p.crop((0, 0, TEX_W, TEX_H))))
    signs.append(("WordRight", p.crop((TEX_W, 0, 2 * TEX_W, TEX_H))))

    for n in range(10):
        p = plate()
        g = Image.new("RGBA", (TEX_W, TEX_H * 2), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((TEX_W / 2, TEX_H), str(n), font=font, fill=(255, 255, 255, 255), anchor="mm")
        paste_centered(p, g.crop(g.getbbox()), TEX_W * 0.8, TEX_H * 0.72)
        signs.append(("Digit%d" % n, p))

    tiles = []
    index = 0
    for name, tex in signs:
        tex = tex.filter(ImageFilter.GaussianBlur(0.6))
        for facing in ("S", "E"):
            png = "delnp_01_%d.png" % index
            on_wall(tex, facing).save(os.path.join(OUT, png))
            props = {
                "CanScrap": "",
                "CustomName": name,
                "Facing": facing,
                "GroupName": "NovaPoshta",
                "IsHigh": "",
                "IsMoveAble": "",
                "Material": "SmallMetalPlates",
                "MoveType": "WallObject",
                "PickUpWeight": "10",
                "attachedN" if facing == "S" else "attachedW": "",
            }
            tiles.append({"index": index, "png": png, "props": props})
            index += 1

    spec = {"pack": "delnovaposhta", "tileset": "delnp_01", "columns": 8, "rows": 4, "tiles": tiles}
    with open(os.path.join(OUT, "tiles.json"), "w", encoding="utf-8") as fh:
        json.dump(spec, fh, ensure_ascii=False, indent=2)

    # Preview: a board on each wall of one corner, as placed in the game.
    prev = Image.new("RGBA", (128 * 5, 256 + 64), (90, 90, 90, 255))
    order = [0, 2, 4, 2 * (3 + 1), 2 * (3 + 2)]       # logo, word L/R, digits 1, 2
    for k, i in enumerate(order):
        fr = Image.open(os.path.join(OUT, "delnp_01_%d.png" % i))
        prev.alpha_composite(fr, (64 * k, 32 * k))
    prev.save(os.path.join(OUT, "preview.png"))
    print("signs:", len(tiles), "sprites")


if __name__ == "__main__":
    main()
