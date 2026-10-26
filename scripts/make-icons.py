#!/usr/bin/env python3
"""Erzeugt das App-Icon von FritzTV (Apple TV: 3 Ebenen + Top-Shelf-Bilder, Mac: AppIcon).

Motiv: Bildschirm mit Zimmerantenne und orangem Play-Symbol in den Farben der App.
Aufruf aus dem Projektordner:  python3 scripts/make-icons.py   (braucht Pillow)
Danach `./setup.sh` bzw. `xcodegen generate`, damit Xcode die Asset-Kataloge kennt.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # Supersampling gegen Treppenkanten

ACCENT_TOP = (255, 190, 112)
ACCENT_BOTTOM = (255, 128, 52)
BG_TOP = (36, 41, 76)
BG_BOTTOM = (10, 12, 20)
FRAME_TOP = (70, 77, 110)
FRAME_BOTTOM = (36, 40, 60)
SCREEN_TOP = (24, 30, 52)
SCREEN_BOTTOM = (9, 11, 19)
ANTENNA = (205, 210, 228)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical_gradient(w, h, top, bottom):
    img = Image.new("RGBA", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        px.line([(0, y), (w, y)], fill=lerp(top, bottom, y / max(h - 1, 1)) + (255,))
    return img


def background(w, h):
    """Hintergrund: diagonaler Verlauf mit warmem Schein unten rechts (deckend)."""
    # Diagonaler Verlauf über eine kleine Fläche, dann hochskalieren (schnell und weich)
    small = Image.new("RGBA", (64, 64))
    sp = small.load()
    for y in range(64):
        for x in range(64):
            t = min(1.0, (x * 0.45 + y * 0.9) / (63 * 1.35))
            sp[x, y] = lerp(BG_TOP, BG_BOTTOM, t) + (255,)
    img = small.resize((w, h), Image.BICUBIC)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    r = int(h * 0.55)
    cx, cy = int(w * 0.78), int(h * 0.95)
    g.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT_BOTTOM + (95,))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.22))
    img.alpha_composite(glow)
    return img


def rounded_mask(w, h, box, radius):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def paste_gradient(canvas, box, radius, top, bottom):
    x0, y0, x1, y1 = [int(v) for v in box]
    grad = vertical_gradient(x1 - x0, y1 - y0, top, bottom)
    mask = rounded_mask(x1 - x0, y1 - y0, (0, 0, x1 - x0 - 1, y1 - y0 - 1), int(radius))
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(grad, (x0, y0), mask)
    canvas.alpha_composite(layer)


def middle_layer(w, h, cx, cy, u):
    """Gerät: Gehäuse, Bildschirm, Antenne (transparent)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sw, sh = 1.45 * u, 0.95 * u
    left, top = cx - sw / 2, cy - sh / 2 + 0.10 * u
    right, bottom = left + sw, top + sh

    # Antenne hinter dem Gehäuse
    d = ImageDraw.Draw(img)
    base = (cx, top + 0.02 * u)
    tips = [(cx - 0.38 * u, top - 0.42 * u), (cx + 0.30 * u, top - 0.48 * u)]
    width = max(2, int(0.055 * u))
    for tip in tips:
        d.line([base, tip], fill=ANTENNA + (255,), width=width)
        r = 0.055 * u
        d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=ANTENNA + (255,))

    # Schatten des Gehäuses
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left, top + 0.06 * u, right, bottom + 0.06 * u], radius=0.17 * u, fill=(0, 0, 0, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(0.07 * u)))

    # Gehäuse und Bildschirm
    paste_gradient(img, (left, top, right, bottom), 0.17 * u, FRAME_TOP, FRAME_BOTTOM)
    inset = 0.075 * u
    paste_gradient(img, (left + inset, top + inset, right - inset, bottom - inset), 0.11 * u,
                   SCREEN_TOP, SCREEN_BOTTOM)
    # dezenter Glanz oben auf dem Bildschirm
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle(
        [left + inset, top + inset, right - inset, top + inset + 0.22 * u], radius=0.11 * u,
        fill=(255, 255, 255, 14))
    img.alpha_composite(sheen)
    return img


def front_layer(w, h, cx, cy, u):
    """Play-Symbol und Signalbögen (transparent)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pcx, pcy = cx + 0.04 * u, cy + 0.10 * u
    s = 0.27 * u
    tri = [(pcx - 0.8 * s, pcy - s), (pcx - 0.8 * s, pcy + s), (pcx + 1.0 * s, pcy)]

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(tri, fill=ACCENT_BOTTOM + (170,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(0.09 * u)))

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(tri, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.012 * u))  # leicht gerundete Ecken
    mask = mask.point(lambda v: 255 if v > 110 else int(v * 255 / 110))
    y0, y1 = int(pcy - s), int(pcy + s)
    grad = vertical_gradient(w, max(y1 - y0, 1), ACCENT_TOP, ACCENT_BOTTOM)
    full = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    full.paste(grad, (0, y0))
    tri_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tri_layer.paste(full, (0, 0), mask)
    img.alpha_composite(tri_layer)

    # Signalbögen an der rechten Antennenspitze
    d = ImageDraw.Draw(img)
    sw, sh = 1.45 * u, 0.95 * u
    top = cy - sh / 2 + 0.10 * u
    tip = (cx + 0.30 * u, top - 0.48 * u)
    for i, rr in enumerate((0.20 * u, 0.34 * u)):
        box = [tip[0] - rr, tip[1] - rr, tip[0] + rr, tip[1] + rr]
        d.arc(box, start=-75, end=-15, fill=ACCENT_TOP + (255 - 70 * i,), width=max(2, int(0.05 * u)))
    return img


def downsample(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def tv_layers(w, h):
    W, H = w * SS, h * SS
    # Motiv reicht von 1,2 u über bis 0,58 u unter die Mitte: so bemessen, dass es mit Rand
    # in den sicheren Bereich passt (tvOS verschiebt die Ebenen beim Kippen).
    u = 0.44 * H
    cx, cy = W / 2, H / 2 + 0.31 * u
    return {
        "Back": downsample(background(W, H), w, h).convert("RGB"),
        "Middle": downsample(middle_layer(W, H, cx, cy, u), w, h),
        "Front": downsample(front_layer(W, H, cx, cy, u), w, h),
    }


def flatten(layers):
    base = layers["Back"].convert("RGBA")
    base.alpha_composite(layers["Middle"])
    base.alpha_composite(layers["Front"])
    return base


def top_shelf(w, h):
    W, H = w * SS, h * SS
    img = background(W, H)
    u = 0.44 * H
    cx, cy = W / 2, H / 2 + 0.31 * u
    img.alpha_composite(middle_layer(W, H, cx, cy, u))
    img.alpha_composite(front_layer(W, H, cx, cy, u))
    return downsample(img, w, h).convert("RGB")


def mac_icon(size):
    """macOS: abgerundetes Quadrat (824/1024) mit Schatten, Motif mittig."""
    S = 1024 * SS
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset, radius = 100 * SS, 185 * SS
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset + 12 * SS, S - inset, S - inset + 12 * SS], radius=radius, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * SS)))
    tile = background(S, S)
    mask = rounded_mask(S, S, (inset, inset, S - inset, S - inset), radius)
    tile_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile_layer.paste(tile, (0, 0), mask)
    u = 0.36 * (S - 2 * inset)
    cx, cy = S / 2, S / 2 + 0.06 * S
    motif = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    motif.alpha_composite(middle_layer(S, S, cx, cy, u))
    motif.alpha_composite(front_layer(S, S, cx, cy, u))
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(motif, (0, 0), mask)
    tile_layer.alpha_composite(clipped)
    canvas.alpha_composite(tile_layer)
    return downsample(canvas, size, size)


INFO = {"author": "xcode", "version": 1}


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def build_tvos():
    cat = os.path.join(ROOT, "App/tvOS/Assets.xcassets")
    write_json(os.path.join(cat, "Contents.json"), {"info": INFO})
    brand = os.path.join(cat, "App Icon & Top Shelf Image.brandassets")
    write_json(os.path.join(brand, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
             "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv",
             "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })
    for stack, sizes in (("App Icon.imagestack", [(400, 240, "1x"), (800, 480, "2x")]),
                         ("App Icon - App Store.imagestack", [(1280, 768, "1x"), (2560, 1536, "2x")])):
        sdir = os.path.join(brand, stack)
        write_json(os.path.join(sdir, "Contents.json"), {
            "info": INFO,
            "layers": [{"filename": f"{n}.imagestacklayer"} for n in ("Front", "Middle", "Back")],
        })
        rendered = {scale: tv_layers(w, h) for w, h, scale in sizes}
        for name in ("Front", "Middle", "Back"):
            ldir = os.path.join(sdir, f"{name}.imagestacklayer")
            write_json(os.path.join(ldir, "Contents.json"), {"info": INFO})
            idir = os.path.join(ldir, "Content.imageset")
            images = []
            for w, h, scale in sizes:
                fn = f"{name.lower()}{'' if scale == '1x' else '@' + scale}.png"
                os.makedirs(idir, exist_ok=True)
                rendered[scale][name].save(os.path.join(idir, fn))
                images.append({"filename": fn, "idiom": "tv", "scale": scale})
            write_json(os.path.join(idir, "Contents.json"), {"images": images, "info": INFO})
    for setname, (w, h) in (("Top Shelf Image.imageset", (1920, 720)),
                            ("Top Shelf Image Wide.imageset", (2320, 720))):
        idir = os.path.join(brand, setname)
        os.makedirs(idir, exist_ok=True)
        images = []
        for scale, factor in (("1x", 1), ("2x", 2)):
            fn = f"topshelf{'-wide' if 'Wide' in setname else ''}{'' if factor == 1 else '@2x'}.png"
            top_shelf(w * factor, h * factor).save(os.path.join(idir, fn))
            images.append({"filename": fn, "idiom": "tv", "scale": scale})
        write_json(os.path.join(idir, "Contents.json"), {"images": images, "info": INFO})
    return flatten(tv_layers(800, 480))


def build_macos():
    cat = os.path.join(ROOT, "App/macOS/Assets.xcassets")
    write_json(os.path.join(cat, "Contents.json"), {"info": INFO})
    idir = os.path.join(cat, "AppIcon.appiconset")
    os.makedirs(idir, exist_ok=True)
    master = mac_icon(1024)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            fn = f"icon_{pt}x{pt}{'' if scale == 1 else '@2x'}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(idir, fn))
            images.append({"filename": fn, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_json(os.path.join(idir, "Contents.json"), {"images": images, "info": INFO})
    return master


if __name__ == "__main__":
    tv_preview = build_tvos()
    mac_preview = build_macos()
    out = os.environ.get("ICON_PREVIEW_DIR")
    if out:
        tv_preview.save(os.path.join(out, "icon-preview-tvos.png"))
        mac_preview.save(os.path.join(out, "icon-preview-macos.png"))
    print("Icons erzeugt.")
