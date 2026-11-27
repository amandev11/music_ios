#!/usr/bin/env python3
"""Builds every app icon from the raw artwork folder.

usage: python3 tools/build_icons.py <Logos folder>
Outputs (committed): assets/icons/*.png, assets/icon/icon.png, lib/core/app_icons.dart,
native/android/res/{mipmap-*,drawable-nodpi,values}, ios_icons/*.png
"""
import os, sys, io
import numpy as np
from PIL import Image, ImageFilter
import cv2

SRC = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024

# id, display name, file, (cx, cy, zoom of min side), mode
ICONS = [
    ("aura", "Aura", "IMG_2578.JPG", (.5, .5, 1.0), None),
    ("keystone", "Keystone", "7E3344E9-7641-4783-97D1-05ACB194AC7C.PNG", (.5, .5, .8), None),
    ("deck", "Deck", "EEBE9F3A-E54B-4E87-A3B3-F07AE25F38A3.GIF", (.5, .5, 1.0), "cut_deck"),
    ("volt", "Volt", "IMG_2564.JPG", (.5, .46, .8), None),
    ("axis", "Axis", "IMG_2565.JPG", (.5, .5, .85), None),
    ("starlight", "Starlight", "IMG_2566.JPG", (.5, .5, 1.0), None),
    ("pressing", "Pressing", "IMG_2567.JPG", (.5, .5, 1.0), "cut_ink"),
    ("midnights", "Midnights", "IMG_2571.JPG", (.5, .5, 1.0), None),
    ("glassnote", "Glass Note", "IMG_2573.JPG", (.5, .5, 1.0), None),
    ("halo", "Halo", "IMG_2575.JPG", (.5, .5, 1.0), None),
    ("pulse", "Pulse", "IMG_2577.JPG", (.5, .5, 1.0), None),
    ("ember", "Ember", "IMG_2579.JPG", (.5, .5, 1.0), None),
    ("mercury", "Mercury", "IMG_2580.JPG", (.5, .5, 1.0), None),
    ("genesis", "Genesis", "IMG_2581.JPG", (.5, .5, 1.0), None),
    ("prism", "Prism", "IMG_2583.JPG", (.5, .5, 1.0), None),
    ("dust", "Dust", "IMG_2584.JPG", (.5, .5, 1.0), None),
    ("voyager", "Voyager", "IMG_2585.JPG", (.5, .5, 1.0), None),
    ("crate", "Crate", "IMG_2586.JPG", (.5, .5, 1.0), None),
    ("molten", "Molten", "IMG_2587.JPG", (.5, .5, 1.0), None),
    ("nightspin", "Nightspin", "IMG_2588.JPG", (.5, .5, 1.0), None),
    ("vortex", "Vortex", "IMG_2589.JPG", (.5, .47, 1.0), None),
    ("chrome", "Chrome", "IMG_2590.JPG", (.5, .5, 1.0), None),
    ("cobalt", "Cobalt", "IMG_2591.JPG", (.5, .5, 1.0), None),
    ("afterglow", "Afterglow", "IMG_2592.JPG", (.5, .45, 1.0), None),
    # Third-party marks, included at the owner's request for personal, non-distributed builds.
    ("soundstar", "Soundstar", "IMG_2563.jpg", (.5, .5, 1.0), None),
    ("spotify", "Spotify", "IMG_2570.JPG", (.5, .5, 1.0), None),
    ("applemusic", "Apple Music", "IMG_2576.JPG", (.5, .5, 1.0), None),
    # Keycap marks supplied by the owner.
    ("keycapkeystone", "Keystone Keycap", "KEYCAP_KEYSTONE.png", (.5, .5, 1.0), None),
    ("keycapmusic", "Music Keycap", "KEYCAP_MUSIC.png", (.5, .5, 1.0), None),
    ("applewordmark", "Music Wordmark", "IMG_2574.JPG", (.5, .5, 1.0), "pad_black"),
]

def rgb(path):
    im = Image.open(os.path.join(SRC, path))
    if getattr(im, "is_animated", False):
        im.seek(0)
    return im.convert("RGB")

def square_crop(im, cx, cy, zoom):
    w, h = im.size
    side = min(w, h) * zoom
    x0 = min(max(cx * w - side / 2, 0), w - side)
    y0 = min(max(cy * h - side / 2, 0), h - side)
    return im.crop((int(x0), int(y0), int(x0 + side), int(y0 + side)))

def to_master(im):
    im = im.resize((S, S), Image.LANCZOS)
    if im.width < 400:  # unreachable, kept for clarity
        pass
    return im

def upscale(im):
    # Low-res sources get a gentle sharpen after the Lanczos upscale.
    big = im.resize((S, S), Image.LANCZOS)
    if min(im.size) < 700:
        big = big.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    return big

def cut_ink(im):
    """Black-on-white halftone: ink darkness becomes alpha, so the white vanishes."""
    g = np.asarray(im.convert("L"), dtype=np.float32) / 255.0
    a = np.clip((1 - g) * 1.15, 0, 1)
    out = np.zeros(g.shape + (4,), np.uint8)
    out[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")

def cut_flood(im, tol=22):
    """Removes a flat light backdrop by flooding in from the borders."""
    a = np.asarray(im.convert("RGB")).copy()
    h, w, _ = a.shape
    bg = np.median(np.concatenate([a[:6].reshape(-1, 3), a[-6:].reshape(-1, 3), a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)]), axis=0)
    mask = np.zeros((h + 2, w + 2), np.uint8)
    work = a.copy()
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        cv2.floodFill(work, mask, seed, (0, 0, 0), (tol,) * 3, (tol,) * 3, cv2.FLOODFILL_MASK_ONLY | cv2.FLOODFILL_FIXED_RANGE | (255 << 8))
    bgm = mask[1:-1, 1:-1] > 0
    alpha = np.where(bgm, 0, 255).astype(np.uint8)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    alpha = cv2.GaussianBlur(alpha, (0, 0), 1.4)
    out = np.dstack([a, alpha])
    return Image.fromarray(out, "RGBA")

def fit_rgba(rgba, frac):
    bbox = rgba.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0) + rgba.size
    rgba = rgba.crop(bbox)
    side = int(S * frac)
    rgba.thumbnail((side, side), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(rgba, ((S - rgba.width) // 2, (S - rgba.height) // 2), rgba)
    return canvas

def gradient(c1, c2):
    y = np.linspace(0, 1, S)[:, None, None]
    top, bot = np.array(c1, np.float32), np.array(c2, np.float32)
    arr = (top * (1 - y) + bot * y) * np.ones((S, S, 1), np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGB").convert("RGBA")

def edge_color(im):
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    ring = np.concatenate([a[:16].reshape(-1, 3), a[-16:].reshape(-1, 3), a[:, :16].reshape(-1, 3), a[:, -16:].reshape(-1, 3)])
    return tuple(int(v) for v in ring.mean(axis=0))

def adaptive_fg(master):
    """108dp canvas with the art inside the 66% safe zone and a replicated, blurred bleed around it."""
    out = 1728  # 108dp * 16
    inner = int(out * 0.72)
    a = np.asarray(master.resize((inner, inner), Image.LANCZOS))
    pad = (out - inner) // 2
    big = cv2.copyMakeBorder(a, pad, out - inner - pad, pad, out - inner - pad, cv2.BORDER_REFLECT)
    big = cv2.GaussianBlur(big, (0, 0), 38)
    big[pad:pad + inner, pad:pad + inner] = a
    return Image.fromarray(big).resize((432, 432), Image.LANCZOS)

def main():
    os.makedirs(f"{ROOT}/assets/icons", exist_ok=True)
    os.makedirs(f"{ROOT}/assets/icon", exist_ok=True)
    os.makedirs(f"{ROOT}/ios_icons", exist_ok=True)
    res = f"{ROOT}/native/android/res"
    for d in ("mipmap-xxxhdpi", "mipmap-anydpi-v26", "drawable-nodpi", "values"):
        os.makedirs(f"{res}/{d}", exist_ok=True)
    colors = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
    dart = []
    transparent_dir = f"{ROOT}/assets/icons/transparent"
    os.makedirs(transparent_dir, exist_ok=True)
    for iid, name, f, (cx, cy, z), mode in ICONS:
        im = rgb(f)
        if mode == "cut_ink":
            ink = fit_rgba(cut_ink(im), 0.88)
            ink.save(f"{transparent_dir}/{iid}.png", optimize=True)
            bg = gradient((255, 106, 43), (225, 52, 24))
            master = Image.alpha_composite(bg, ink).convert("RGB")
        elif mode == "cut_deck":
            cut = fit_rgba(cut_flood(im), 0.86)
            cut.save(f"{transparent_dir}/{iid}.png", optimize=True)
            bg = gradient((46, 52, 74), (14, 16, 26))
            sh = cut.copy()
            alpha = sh.getchannel("A").filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * .55))
            shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); shadow.putalpha(alpha)
            shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -22))
            master = Image.alpha_composite(Image.alpha_composite(bg, shadow), cut).convert("RGB")
        elif mode == "pad_black":
            top = im.crop((0, 0, im.width, int(im.height * 0.56)))
            canvas = Image.new("RGB", (im.width, im.width), (0, 0, 0))
            canvas.paste(top, (0, (im.width - top.height) // 2))
            master = upscale(canvas)
        else:
            master = upscale(square_crop(im, cx, cy, z))
        master.save(f"{ROOT}/ios_icons/_{iid}_1024.png") if False else None
        master.resize((256, 256), Image.LANCZOS).save(f"{ROOT}/assets/icons/{iid}.png", optimize=True)
        master.resize((180, 180), Image.LANCZOS).save(f"{ROOT}/ios_icons/{iid}@3x.png", optimize=True)
        master.resize((120, 120), Image.LANCZOS).save(f"{ROOT}/ios_icons/{iid}@2x.png", optimize=True)
        master.resize((192, 192), Image.LANCZOS).save(f"{res}/mipmap-xxxhdpi/ic_{iid}.png", optimize=True)
        adaptive_fg(master).save(f"{res}/drawable-nodpi/ic_{iid}_fg.png", optimize=True)
        r, g, b = edge_color(master)
        colors.append(f'    <color name="ic_{iid}_bg">#{r:02X}{g:02X}{b:02X}</color>')
        open(f"{res}/mipmap-anydpi-v26/ic_{iid}.xml", "w").write(
            '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@color/ic_{iid}_bg" />\n    <foreground android:drawable="@drawable/ic_{iid}_fg" />\n</adaptive-icon>\n')
        if iid == "keycapkeystone":
            master.save(f"{ROOT}/assets/icon/icon.png", optimize=True)
        dart.append(f"  AppIconDef('{iid}', '{name}'),")
    colors.append("</resources>")
    open(f"{res}/values/aurora_icon_colors.xml", "w").write("\n".join(colors) + "\n")
    open(f"{ROOT}/lib/core/app_icons.dart", "w").write(
        "// GENERATED by tools/build_icons.py - do not edit.\n\n"
        "/// One selectable app icon; [id] matches the Android alias and iOS alternate icon names.\n"
        "class AppIconDef {\n  const AppIconDef(this.id, this.name);\n  final String id;\n  final String name;\n  String get asset => 'assets/icons/$id.png';\n}\n\n"
        "const appIcons = <AppIconDef>[\n" + "\n".join(dart) + "\n];\n\nconst defaultIconId = 'keycapkeystone';\n")
    print("built", len(ICONS), "icons")

main()
