#!/usr/bin/env python3
# Genera logo.png (480x270) de los addons incluidos: formas sencillas propias, no marcas oficiales.
import os
from PIL import Image, ImageDraw
W, H, K = 480, 270, 4
HERE = os.path.dirname(os.path.abspath(__file__))

def canvas(bg):
    im = Image.new("RGBA", (W * K, H * K), bg)
    return im, ImageDraw.Draw(im)

def save(im, name):
    out = os.path.join(HERE, "..", "addons", name, "logo.png")
    im.resize((W, H), Image.LANCZOS).save(out)
    print("escrito", out)

def plex():
    im, d = canvas((31, 31, 31, 255)); s = K
    cx, cy = 240 * s, 135 * s
    pts = [(-45, -95), (10, -95), (75, 0), (10, 95), (-45, 95), (20, 0)]
    d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=(229, 160, 13, 255))
    save(im, "plex")

def radio():
    im, d = canvas((20, 48, 92, 255)); s = K
    cx, cy = 240 * s, 150 * s
    d.ellipse([cx - 14 * s, cy - 14 * s, cx + 14 * s, cy + 14 * s], fill=(255, 255, 255, 255))
    for r in (50, 85, 120):
        d.arc([cx - r * s, cy - r * s, cx + r * s, cy + r * s], 215, 325, fill=(120, 190, 255, 255), width=12 * s)
    d.rectangle([cx - 5 * s, cy, cx + 5 * s, cy + 80 * s], fill=(255, 255, 255, 255))
    save(im, "radio-browser")

def soma():
    im, d = canvas((16, 62, 66, 255)); s = K
    cx, cy = 240 * s, 135 * s
    d.ellipse([cx - 95 * s, cy - 95 * s, cx + 95 * s, cy + 95 * s], fill=(10, 30, 32, 255))
    d.ellipse([cx - 70 * s, cy - 70 * s, cx + 70 * s, cy + 70 * s], outline=(40, 120, 124, 255), width=4 * s)
    d.ellipse([cx - 30 * s, cy - 30 * s, cx + 30 * s, cy + 30 * s], fill=(255, 140, 60, 255))
    d.ellipse([cx - 6 * s, cy - 6 * s, cx + 6 * s, cy + 6 * s], fill=(10, 30, 32, 255))
    save(im, "somafm")

def archive():
    im, d = canvas((60, 60, 70, 255)); s = K
    cx = 240 * s
    d.polygon([(cx - 110 * s, 105 * s), (cx, 40 * s), (cx + 110 * s, 105 * s)], fill=(235, 235, 240, 255))
    for i in range(4):
        x = cx - 90 * s + i * 60 * s
        d.rectangle([x, 115 * s, x + 30 * s, 205 * s], fill=(235, 235, 240, 255))
    d.rectangle([cx - 110 * s, 212 * s, cx + 110 * s, 232 * s], fill=(235, 235, 240, 255))
    save(im, "internet-archive")

def peertube():
    # forma propia: reproductor naranja con dos satélites (la red federada), sin logotipo oficial
    im, d = canvas((19, 24, 32, 255)); s = K
    cx, cy = 240 * s, 135 * s
    d.ellipse([cx - 95 * s, cy - 95 * s, cx + 95 * s, cy + 95 * s], outline=(255, 120, 60, 255), width=5 * s)
    d.ellipse([cx - 62 * s, cy - 62 * s, cx + 62 * s, cy + 62 * s], fill=(255, 120, 60, 255))
    d.polygon([(cx - 20 * s, cy - 32 * s), (cx + 40 * s, cy), (cx - 20 * s, cy + 32 * s)], fill=(19, 24, 32, 255))
    for x, y, r in ((-95, -95, 16), (95, 95, 13), (95, -95, 10)):
        d.ellipse([cx + x * s - r * s, cy + y * s - r * s, cx + x * s + r * s, cy + y * s + r * s], fill=(255, 200, 150, 255))
    save(im, "peertube")

def youtube():
    # forma propia: pantalla roja con un triángulo de reproducción, no es el logotipo oficial
    im, d = canvas((16, 18, 24, 255)); s = K
    cx, cy = 240 * s, 135 * s
    d.rounded_rectangle([cx - 152 * s, cy - 86 * s, cx + 152 * s, cy + 86 * s], radius=42 * s, fill=(212, 46, 40, 255))
    d.polygon([(cx - 36 * s, cy - 50 * s), (cx + 54 * s, cy), (cx - 36 * s, cy + 50 * s)], fill=(250, 250, 250, 255))
    for x, y in ((-152, -86), (152, -86), (-152, 86), (152, 86)):
        d.ellipse([cx + x * s - 12 * s, cy + y * s - 12 * s, cx + x * s + 12 * s, cy + y * s + 12 * s], fill=(255, 190, 186, 255))
    save(im, "youtube")

def jellyfin():
    # forma propia: pantalla con un triangulo de reproduccion sobre fondo violeta/azul, no es el logotipo oficial
    im, d = canvas((20, 22, 46, 255)); s = K
    cx, cy = 240 * s, 135 * s
    d.rounded_rectangle([cx - 140 * s, cy - 84 * s, cx + 140 * s, cy + 84 * s], radius=30 * s, fill=(86, 70, 170, 255))
    d.rounded_rectangle([cx - 122 * s, cy - 66 * s, cx + 122 * s, cy + 66 * s], radius=18 * s, fill=(34, 150, 190, 255))
    d.polygon([(cx - 30 * s, cy - 44 * s), (cx + 50 * s, cy), (cx - 30 * s, cy + 44 * s)], fill=(250, 250, 250, 255))
    save(im, "jellyfin")

for f in (plex, radio, soma, archive, peertube, youtube, jellyfin):
    f()
