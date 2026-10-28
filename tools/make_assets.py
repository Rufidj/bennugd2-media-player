#!/usr/bin/env python3
# Genera iconos y la hoja de la fuente del reproductor (res/*.png)
import os
from PIL import Image, ImageDraw, ImageFont
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "res")
F = 1.5       # la interfaz se dibuja a 1920x1080 (el diseño es 1280x720): los recursos salen x1.5
S, K = int(96 * F), 4  # tamano final y supermuestreo
W = (255, 255, 255, 255)

def icon(name, fn):
    im = Image.new("RGBA", (S*K, S*K), (0, 0, 0, 0))
    fn(ImageDraw.Draw(im), S*K)
    im.resize((S, S), Image.LANCZOS).save(f"{out}/{name}.png")

def tri(d, x0, y0, x1, y1, right=True):
    if right: d.polygon([(x0, y0), (x0, y1), (x1, (y0+y1)/2)], fill=W)
    else:     d.polygon([(x1, y0), (x1, y1), (x0, (y0+y1)/2)], fill=W)

def play(d, n):   tri(d, n*.30, n*.20, n*.78, n*.80)
def pause(d, n):
    d.rounded_rectangle([n*.26, n*.20, n*.43, n*.80], n*.03, fill=W)
    d.rounded_rectangle([n*.57, n*.20, n*.74, n*.80], n*.03, fill=W)
def stop(d, n):   d.rounded_rectangle([n*.24, n*.24, n*.76, n*.76], n*.05, fill=W)
def next_(d, n):
    tri(d, n*.18, n*.25, n*.50, n*.75); tri(d, n*.46, n*.25, n*.78, n*.75)
    d.rectangle([n*.80, n*.25, n*.86, n*.75], fill=W)
def prev(d, n):
    tri(d, n*.50, n*.25, n*.82, n*.75, False); tri(d, n*.22, n*.25, n*.54, n*.75, False)
    d.rectangle([n*.14, n*.25, n*.20, n*.75], fill=W)
def ff(d, n):  tri(d, n*.16, n*.25, n*.52, n*.75); tri(d, n*.48, n*.25, n*.84, n*.75)
def rw(d, n):  tri(d, n*.48, n*.25, n*.84, n*.75, False); tri(d, n*.16, n*.25, n*.52, n*.75, False)
def subs(d, n):
    d.rounded_rectangle([n*.12, n*.22, n*.88, n*.78], n*.08, outline=W, width=int(n*.05))
    d.rectangle([n*.22, n*.50, n*.42, n*.55], fill=W); d.rectangle([n*.48, n*.50, n*.78, n*.55], fill=W)
    d.rectangle([n*.22, n*.62, n*.58, n*.67], fill=W); d.rectangle([n*.64, n*.62, n*.78, n*.67], fill=W)
def vol(d, n):
    d.polygon([(n*.16, n*.40), (n*.30, n*.40), (n*.48, n*.24), (n*.48, n*.76), (n*.30, n*.60), (n*.16, n*.60)], fill=W)
    for r in (.14, .26):
        d.arc([n*(.48-r), n*(.5-r*1.3), n*(.48+r*2), n*(.5+r*1.3)], -50, 50, fill=W, width=int(n*.045))
def mute(d, n):
    vol(d, n); d.line([(n*.62, n*.36), (n*.86, n*.64)], fill=W, width=int(n*.05)); d.line([(n*.86, n*.36), (n*.62, n*.64)], fill=W, width=int(n*.05))
def folder(d, n):
    d.rounded_rectangle([n*.10, n*.28, n*.90, n*.80], n*.05, fill=W)
    d.rounded_rectangle([n*.10, n*.20, n*.42, n*.36], n*.04, fill=W)
def video(d, n):
    d.rounded_rectangle([n*.14, n*.18, n*.86, n*.82], n*.06, outline=W, width=int(n*.05)); tri(d, n*.42, n*.35, n*.66, n*.65)
def back(d, n):
    d.polygon([(n*.40, n*.22), (n*.18, n*.50), (n*.40, n*.78), (n*.40, n*.60), (n*.82, n*.60), (n*.82, n*.40), (n*.40, n*.40)], fill=W)

def cloud(d, n):
    d.ellipse([n*.14, n*.42, n*.42, n*.74], fill=W); d.ellipse([n*.58, n*.44, n*.88, n*.74], fill=W)
    d.ellipse([n*.26, n*.26, n*.60, n*.66], fill=W); d.ellipse([n*.44, n*.30, n*.76, n*.68], fill=W)
    d.rectangle([n*.28, n*.55, n*.72, n*.74], fill=W)

def note(d, n):   # corchea
    d.ellipse([n*.20, n*.62, n*.46, n*.84], fill=W); d.ellipse([n*.52, n*.54, n*.78, n*.76], fill=W)
    d.rectangle([n*.40, n*.20, n*.47, n*.72], fill=W); d.rectangle([n*.72, n*.12, n*.79, n*.64], fill=W)
    d.polygon([(n*.40, n*.20), (n*.79, n*.12), (n*.79, n*.28), (n*.40, n*.36)], fill=W)

def addon(d, n):   # pieza de puzzle
    d.rounded_rectangle([n*.18, n*.34, n*.70, n*.86], n*.05, fill=W)
    d.ellipse([n*.34, n*.18, n*.54, n*.40], fill=W)
    d.ellipse([n*.62, n*.52, n*.84, n*.74], fill=W)

def lang(d, n):   # globo terraqueo
    w = int(n*.05); c = n/2; r = n*.34
    d.ellipse([c-r, c-r, c+r, c+r], outline=W, width=w)
    d.ellipse([c-r*.45, c-r, c+r*.45, c+r], outline=W, width=w)
    d.line([(c-r, c), (c+r, c)], fill=W, width=w)
    d.arc([c-r, c-r*.55, c+r, c+r*.55], 0, 180, fill=W, width=w)

for k, f in dict(addon=addon, note=note, cloud=cloud, lang=lang, play=play, pause=pause, stop=stop, next=next_, prev=prev, ff=ff, rw=rw,
                 subs=subs, vol=vol, mute=mute, folder=folder, video=video, back=back).items():
    icon(k, f)

# Hoja de fuente 16x16 ISO-8859-1, celdas fijas CW x CH, blanco con alfa
def font(name, path, size, cw, ch):
    f = ImageFont.truetype(path, size)
    im = Image.new("RGBA", (cw*16, ch*16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for c in range(32, 256):
        if 127 <= c < 160: continue
        w = d.textlength(chr(c), font=f)
        d.text(((c % 16)*cw + (cw-w)/2, (c//16)*ch + 2), chr(c), font=f, fill=W)
    im.save(f"{out}/{name}.png")
M = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
font("font_ui", M, 39, 24, 51)
font("font_sub", M, 60, 38, 78)

# degradados, anillo de foco y marcador de la barra de progreso
sb = Image.new("RGBA", (64, 256)); st = Image.new("RGBA", (64, 128))
for i in range(256): sb.paste((0, 0, 0, int(i * 215 / 255)), (0, i, 64, i + 1))
for i in range(128): st.paste((0, 0, 0, int((127 - i) * 215 / 127)), (0, i, 64, i + 1))
sb.save(f"{out}/shade_bot.png"); st.save(f"{out}/shade_top.png")
def disc(name, size, r, alpha):
    im = Image.new("RGBA", (size*K, size*K), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = size*K/2; d.ellipse([c-r*K, c-r*K, c+r*K, c+r*K], fill=(255, 255, 255, alpha))
    im.resize((size, size), Image.LANCZOS).save(f"{out}/{name}.png")
disc("ring", 144, 69, 70); disc("knob", 39, 18, 255)

# ---- aspecto "PlayStation": fondo degradado, olas, selector en pastilla y simbolos de botones (estetica propia, sin logotipos)
import math
from PIL import ImageFilter
# ---- aspectos animados. Cada uno tiene su fondo, su pastilla de seleccion y sus propias piezas que el reproductor mueve
# (olas, cortinas de luz, sol y nubes, rejilla neon, brasas, estrellas). Las piezas salen a tamano real (x1.5)
import math
import numpy as np
from PIL import ImageFilter, ImageChops

def save_rgba(arr, name):
    os.makedirs(os.path.dirname(f"{out}/{name}"), exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(f"{out}/{name}.png")

def vgrad(top, bot, w=1920, h=1080):
    t = np.linspace(0, 1, h)[:, None, None]
    img = np.array(top, float)[None, None, :] * (1 - t) + np.array(bot, float)[None, None, :] * t
    return np.repeat(img, w, axis=1)

def glow_blob(w, h, cx, cy, rx, ry, col, power=2.0):
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    a = np.clip(1 - d, 0, 1) ** power
    return a[..., None] * np.array(col, float)[None, None, :]

def bg_save(key, arr):
    os.makedirs(f"{out}/skins/{key}", exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(f"{out}/skins/{key}/bg.png")

def dot(key, name, col, size=96, power=2.4, spike=0.0):
    y, x = np.mgrid[0:size, 0:size]; c = (size - 1) / 2.0
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    a = np.clip(1 - d, 0, 1) ** power
    if spike:
        a = np.maximum(a, spike * np.clip(1 - np.abs(x - c) / c, 0, 1) ** 6 * np.clip(1 - np.abs(y - c) / (c * 0.25), 0, 1) ** 2)
        a = np.maximum(a, spike * np.clip(1 - np.abs(y - c) / c, 0, 1) ** 6 * np.clip(1 - np.abs(x - c) / (c * 0.25), 0, 1) ** 2)
    arr = np.zeros((size, size, 4)); arr[..., :3] = col; arr[..., 3] = a * 255
    save_rgba(arr, f"skins/{key}/{name}")

def pill(key, col, style="round", w=1056, h=72):
    os.makedirs(f"{out}/skins/{key}", exist_ok=True)
    k = 4
    im = Image.new("RGBA", (w*k, h*k), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    if style == "chamfer":                                    # esquinas cortadas y doble linea (neon)
        c = 20
        pts = lambda m: [(m+c, m), (w-m, m), (w-m, h-m-c), (w-m-c, h-m), (m, h-m), (m, m+c)]
        dd.polygon([(x*k, y*k) for x, y in pts(4)], fill=col + (30,), outline=col + (170,), width=2*k)
        dd.line([(x*k, y*k) for x, y in pts(11) + [pts(11)[0]]], fill=col + (70,), width=k)
    else:
        th = 3 if style == "thick" else 2
        dd.rounded_rectangle([3*k, 3*k, (w-3)*k, (h-3)*k], radius=(h//2-3)*k, fill=col + (34,), outline=col + (120 if style != "thick" else 150,), width=th*k)
    im = im.resize((w, h), Image.LANCZOS)
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    if style == "chamfer": hd.polygon([(4+20, 4), (w-4, 4), (w-4, h-24), (w-24, h-4), (4, h-4), (4, 24)], outline=col + (110,), width=5)
    else: hd.rounded_rectangle([3, 3, w-3, h-3], radius=h//2-3, outline=col + (90 if style != "thick" else 130,), width=5)
    halo = halo.filter(ImageFilter.GaussianBlur(3 if style != "thick" else 5))
    Image.alpha_composite(halo, im).save(f"{out}/skins/{key}/pill.png")

# ---- PlayStation: olas con linea translucida y halo
def skin_wave(key, k, base, amp, n, phase, fill, edge):
    os.makedirs(f"{out}/skins/{key}", exist_ok=True)
    W, H = 3840, 1080
    pts = [(x, F*base + F*amp * math.sin(2*math.pi*n*x/1920.0 + phase) + 0.35*F*amp*math.sin(2*math.pi*2*n*x/1920.0 + phase*1.7)) for x in range(0, W + 1, 8)]
    fl = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(fl).polygon(pts + [(W, H), (0, H)], fill=fill + (26,))
    ln = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(ln).line(pts, fill=edge + (60,), width=3)
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(halo).line(pts, fill=edge + (70,), width=14)
    halo = halo.filter(ImageFilter.GaussianBlur(9))
    Image.alpha_composite(Image.alpha_composite(fl, halo), ln).save(f"{out}/skins/{key}/f{k}.png")

bg_save("ps", vgrad((6, 14, 46), (10, 54, 138)) + glow_blob(1920, 1080, 960, 960, 900, 560, (20, 80, 190), 1.5) * 0.7)
for k, (base, amp, n, ph, fill, edge) in enumerate([(470, 42, 1, 0.0, (120, 180, 255), (190, 225, 255)), (545, 32, 2, 1.7, (90, 150, 255), (170, 210, 255)), (615, 26, 2, 3.4, (160, 210, 255), (220, 240, 255))]):
    skin_wave("ps", k, base, amp, n, ph, fill, edge)
pill("ps", (175, 215, 255))

# ---- Aurora: cortinas de luz verticales que se mecen (mezcla aditiva)
bg_save("aurora", vgrad((3, 10, 24), (6, 52, 62)) + glow_blob(1920, 1080, 960, 1150, 1100, 420, (10, 90, 80), 1.6))
def curtain(name, col, w, seed):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:1080, 0:w]
    prof = np.exp(-(((x - w / 2.0) / (w * 0.27)) ** 2))                       # perfil horizontal suave
    rays = 0.65 + 0.35 * np.sin(x / 7.0 + rng.random() * 6.28) * np.sin(x / 19.0 + rng.random() * 6.28)
    vert = np.clip(1 - np.abs((y - 380) / 520.0), 0, 1) ** 1.6 * np.clip(y / 140.0, 0, 1)    # intensidad: mas fuerte arriba, se desvanece abajo
    a = prof * rays * vert
    arr = np.zeros((1080, w, 4)); arr[..., :3] = col; arr[..., 3] = a * 200
    save_rgba(arr, f"skins/aurora/{name}")
curtain("f0", (80, 255, 170), 520, 1); curtain("f1", (60, 220, 230), 420, 2); curtain("f2", (170, 120, 255), 460, 3)
pill("aurora", (160, 255, 220), "thick")

# ---- Atardecer: sol grande que se mece, nubes que cruzan y siluetas de tierra delante
bg_save("sunset", vgrad((24, 10, 56), (226, 96, 92)) + glow_blob(1920, 1080, 960, 760, 1100, 480, (255, 150, 60), 1.8) * 0.8)
def retro_sun(name, top, bot, size, stripes=True, half=False):
    y, x = np.mgrid[0:size, 0:size]; c = size / 2.0
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    a = np.clip((1 - d) * c / 3.0, 0, 1)                                            # borde nitido con antialias
    t = (y / float(size))[..., None]
    col = np.array(top, float) * (1 - t) + np.array(bot, float) * t
    if stripes:
        yy = (y / float(size))
        cut = (yy > 0.52) & (np.sin((yy - 0.52) * 70) > (0.55 - (yy - 0.52) * 2.4))        # bandas oscuras cada vez mas gruesas hacia abajo
        a = np.where(cut, 0, a)
    arr = np.zeros((size, size, 4)); arr[..., :3] = col; arr[..., 3] = a * 255
    glow = glow_blob(size, size, c, c, c * 1.0, c * 1.0, bot, 2.4)
    arr[..., :3] = np.where(a[..., None] > 0.05, arr[..., :3], glow); 
    if half: arr = arr[: size // 2]
    save_rgba(arr, name)
retro_sun("skins/sunset/f0", (255, 236, 130), (255, 90, 110), 760)
def cloud(name, w, h, col, seed):
    rng = np.random.default_rng(seed); im = Image.new("L", (w, h), 0); dd = ImageDraw.Draw(im)
    for i in range(14):
        cx = rng.uniform(0.15, 0.85) * w; cy = rng.uniform(0.35, 0.7) * h; rx = rng.uniform(0.08, 0.2) * w; ry = rng.uniform(0.18, 0.4) * h
        dd.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=int(rng.uniform(140, 255)))
    im = im.filter(ImageFilter.GaussianBlur(h * 0.16)); a = np.array(im, float)
    arr = np.zeros((h, w, 4)); arr[..., :3] = col; arr[..., 3] = a * 0.55
    save_rgba(arr, name)
cloud("skins/sunset/f1", 1000, 190, (255, 200, 170), 4); cloud("skins/sunset/f2", 760, 140, (255, 170, 190), 9)
def land(name, w=1920, h=330, col=(20, 8, 30)):
    os.makedirs(os.path.dirname(f"{out}/{name}"), exist_ok=True)
    pts = [(x, h * 0.45 + 40 * math.sin(x / 210.0) + 22 * math.sin(x / 83.0 + 1.3) + 0.00006 * (x - 960) ** 2 * 0.2) for x in range(0, w + 1, 6)]
    im = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0)); ImageDraw.Draw(im).polygon([(x * 2, y * 2) for x, y in pts] + [(w * 2, h * 2), (0, h * 2)], fill=col + (255,))
    im.resize((w, h), Image.LANCZOS).save(f"{out}/{name}.png")
land("skins/sunset/f3")
pill("sunset", (255, 200, 170))

# ---- Neon: rejilla en perspectiva, sol a rayas y lineas que avanzan hacia ti
HZ = 560
neon = vgrad((8, 2, 24), (42, 8, 70)) + glow_blob(1920, 1080, 960, HZ, 1000, 260, (200, 30, 160), 1.6) * 0.9
floor = Image.fromarray(np.clip(neon, 0, 255).astype(np.uint8), "RGB"); fd = ImageDraw.Draw(floor)
fd.rectangle([0, HZ, 1920, 1080], fill=(10, 3, 28))
for i in range(-22, 23):                                                           # lineas que convergen en el horizonte
    fd.line([(960 + i * 30, HZ), (960 + i * 260, 1080)], fill=(120, 40, 200), width=2)
fd.line([(0, HZ), (1920, HZ)], fill=(255, 90, 220), width=3)
os.makedirs(f"{out}/skins/neon", exist_ok=True); floor.save(f"{out}/skins/neon/bg.png")
la = np.zeros((10, 1920, 4)); prof = np.exp(-(((np.arange(10) - 4.5) / 1.6) ** 2)); la[..., :3] = (255, 80, 220); la[..., 3] = prof[:, None] * 255
save_rgba(la, "skins/neon/f0")
retro_sun("skins/neon/f1", (255, 230, 90), (255, 40, 170), 560, True, True)
pill("neon", (90, 240, 255), "chamfer")

# ---- Brasas: chispas que suben (mezcla aditiva) sobre un fondo rojo oscuro
bg_save("embers", vgrad((16, 3, 8), (92, 16, 30)) + glow_blob(1920, 1080, 960, 1160, 1200, 520, (210, 60, 20), 1.7) * 0.85)
dot("embers", "f0", (255, 130, 40)); dot("embers", "f1", (255, 215, 120), 80, 2.8)
pill("embers", (255, 175, 120), "thick")

# ---- Cosmos: nebulosa, estrellas que titilan y una estrella fugaz
rng = np.random.default_rng(7)
neb = vgrad((4, 4, 20), (10, 8, 40))
for cx, cy, rx, ry, col in [(420, 330, 520, 300, (60, 40, 150)), (1450, 700, 620, 340, (30, 80, 160)), (1000, 200, 400, 200, (110, 40, 130))]:
    neb += glow_blob(1920, 1080, cx, cy, rx, ry, col, 1.6) * 0.65
img = Image.fromarray(np.clip(neb, 0, 255).astype(np.uint8), "RGB"); gd = ImageDraw.Draw(img)
for i in range(260):                                                              # estrellas pequenas fijas
    sx, sy = rng.integers(0, 1920), rng.integers(0, 1080); v = int(rng.uniform(70, 200)); gd.point((sx, sy), fill=(v, v, min(255, v + 40)))
os.makedirs(f"{out}/skins/cosmos", exist_ok=True); img.save(f"{out}/skins/cosmos/bg.png")
dot("cosmos", "f0", (200, 220, 255), 96, 2.2, 0.9); dot("cosmos", "f1", (255, 225, 190), 96, 2.2, 0.9)
st = np.zeros((12, 520, 4)); xs = np.arange(520)[None, :]; ys = np.arange(12)[:, None]
st[..., :3] = (220, 235, 255); st[..., 3] = (np.clip(xs / 520.0, 0, 1) ** 2.4) * np.exp(-(((ys - 5.5) / (0.9 + 2.2 * xs / 520.0)) ** 2)) * 255
save_rgba(st, "skins/cosmos/f2")
pill("cosmos", (190, 210, 255))


# ---- skin.cfg de cada aspecto de fabrica (el mismo formato que usan los aspectos propios: ver SKINS.md) y su fuente
import shutil
FONTS = {"aurora": "lato/Lato-Medium.ttf", "sunset": "noto/NotoSerif-Regular.ttf", "neon": "noto/NotoSansMono-Bold.ttf", "embers": "lato/Lato-Bold.ttf", "cosmos": "lato/Lato-Light.ttf"}
CFG = {
"ps": """name=PlayStation
text=FFFFFF
select=FFFFFF
background=bg.png
pill=pill.png
layer=f0.png effect=scroll speed=22 loop=1920
layer=f1.png effect=scroll speed=45 loop=1920
layer=f2.png effect=scroll speed=67 loop=1920
""",
"aurora": """name=Aurora
font=font.ttf
text=D9F5EE
select=9AFFD8
background=bg.png
pill=pill.png
layer=f0.png effect=sway count=2 x=140 dx=750 y=360 amp=80 period=23 pulse=32 alpha=150 breathe=95 tilt=2.6 add=1
layer=f1.png effect=sway count=2 x=390 dx=750 y=360 amp=80 period=23 pulse=32 alpha=150 breathe=95 tilt=2.6 add=1
layer=f2.png effect=sway count=1 x=640 y=360 amp=80 period=23 pulse=32 alpha=150 breathe=95 tilt=2.6 add=1
""",
"sunset": """name=Atardecer
font=font.ttf
text=FFE3D3
select=FFD27A
background=bg.png
pill=pill.png
layer=f0.png effect=bob x=960 y=480 size=62 amp=10 period=4 pulse=1
layer=f1.png effect=drift count=2 x0=-450 dx=1220 y=120 dy=170 speed=45 dspeed=60 alpha=200
layer=f2.png effect=drift count=2 x0=-150 dx=1220 y=205 dy=170 speed=75 dspeed=60 alpha=180
layer=f3.png effect=static x=640 y=610 front=1
""",
"neon": """name=Neon
font=font.ttf
text=F2D9FF
select=5FF0FF
background=bg.png
pill=pill.png
layer=f1.png effect=bob x=640 y=280 amp=3 period=3.5
layer=f0.png effect=perspective count=12 horizon=373 period=3.3 alpha=170 add=1
""",
"embers": """name=Brasas
font=font.ttf
text=FFE0D0
select=FFC48A
background=bg.png
pill=pill.png
layer=f0.png effect=rise count=22 size=25-80 amp=28 period=5.5-10.5 y0=740 y1=-40 add=1
layer=f1.png effect=rise count=8 size=25-80 amp=28 period=5.5-10.5 y0=740 y1=-40 add=1
""",
"cosmos": """name=Cosmos
font=font.ttf
text=E6ECFF
select=C8D8FF
background=bg.png
pill=pill.png
layer=f0.png effect=twinkle count=24 size=18-54 alpha=70-255 period=5-12 y=10-630 add=1
layer=f1.png effect=twinkle count=8 size=18-54 alpha=70-255 period=5-12 y=10-630 add=1
layer=f2.png effect=shoot period=6.3 vx=21 vy=9 angle=-23 add=1
""",
}
for key, txt in CFG.items():
    d = f"{out}/skins/{key}"; os.makedirs(d, exist_ok=True)
    open(f"{d}/skin.cfg", "w", encoding="utf-8").write(txt)
    if key in FONTS: shutil.copy("/usr/share/fonts/truetype/" + FONTS[key], f"{d}/font.ttf")


# ---- plantilla para crear aspectos propios (skin_template/): imagenes de ejemplo + un skin.cfg comentado
TPL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skin_template")
os.makedirs(TPL, exist_ok=True)
Image.fromarray(np.clip(vgrad((10, 20, 60), (40, 10, 90)) + glow_blob(1920, 1080, 960, 1000, 1000, 500, (90, 40, 200), 1.6) * 0.8, 0, 255).astype(np.uint8), "RGB").save(f"{TPL}/bg.png")
_o = out; out = TPL; pill("_t", (200, 170, 255)); out = _o
os.replace(f"{TPL}/skins/_t/pill.png", f"{TPL}/pill.png"); shutil.rmtree(f"{TPL}/skins")
dot_arr = None
_o = out; out = TPL; os.makedirs(f"{TPL}/skins", exist_ok=True); dot("_t", "star", (210, 190, 255), 96, 2.4); out = _o
os.replace(f"{TPL}/skins/_t/star.png", f"{TPL}/star.png"); shutil.rmtree(f"{TPL}/skins")
open(f"{TPL}/skin.cfg", "w", encoding="utf-8").write(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "skin_template.cfg"), encoding="utf-8").read())

def symbol(name, col, kind):
    k = 4; n = 72
    im = Image.new("RGBA", (n*k, n*k), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    dd.ellipse([3*k, 3*k, (n-3)*k, (n-3)*k], fill=(8, 18, 56, 190), outline=(200, 225, 255, 120), width=3*k)
    c = n*k/2; r = 16*k; w = 6*k
    if kind == "cross":
        dd.line([(c-r, c-r), (c+r, c+r)], fill=col, width=w); dd.line([(c-r, c+r), (c+r, c-r)], fill=col, width=w)
    elif kind == "circle":
        dd.ellipse([c-r, c-r, c+r, c+r], outline=col, width=w)
    elif kind == "triangle":
        dd.polygon([(c, c-r-2*k), (c+r+3*k, c+r), (c-r-3*k, c+r)], outline=col, width=w)
        dd.line([(c, c-r-2*k), (c+r+3*k, c+r), (c-r-3*k, c+r), (c, c-r-2*k)], fill=col, width=w)
    else:
        dd.rectangle([c-r, c-r, c+r, c+r], outline=col, width=w)
    im.resize((n, n), Image.LANCZOS).save(f"{out}/{name}.png")
symbol("sym_cross", (110, 160, 255, 255), "cross")
symbol("sym_circle", (255, 95, 105, 255), "circle")
symbol("sym_triangle", (70, 215, 170, 255), "triangle")
symbol("sym_square", (255, 140, 210, 255), "square")
