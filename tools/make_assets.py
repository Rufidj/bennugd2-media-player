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
bg = Image.new("RGB", (1920, 1080))
d = ImageDraw.Draw(bg)
for y in range(1080):
    t = y / 1079.0
    d.line([(0, y), (1920, y)], fill=(int(6 + 4*t), int(14 + 40*t), int(46 + 92*t)))
glow = Image.new("RGB", (1920, 1080), (0, 0, 0))
ImageDraw.Draw(glow).ellipse([240, 570, 1680, 1350], fill=(20, 80, 190))
glow = glow.filter(ImageFilter.GaussianBlur(180))
bg = Image.blend(bg, Image.composite(glow, bg, Image.new("L", (1920, 1080), 255)), 0.45)
bg.save(f"{out}/bg_ps.png")

def wave(name, base, amp, n, phase, col, edge):
    W, H = 3840, 1080
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    pts = [(x, F*base + F*amp * math.sin(2*math.pi*n*x/1920.0 + phase) + 0.35*F*amp*math.sin(2*math.pi*2*n*x/1920.0 + phase*1.7)) for x in range(0, W + 1, 8)]
    dd.polygon(pts + [(W, H), (0, H)], fill=col)
    dd.line(pts, fill=edge, width=4)
    im.save(f"{out}/{name}.png")
wave("wave0", 470, 42, 1, 0.0, (120, 180, 255, 30), (190, 225, 255, 70))
wave("wave1", 545, 32, 2, 1.7, (90, 150, 255, 36), (170, 210, 255, 80))
wave("wave2", 615, 26, 2, 3.4, (160, 210, 255, 42), (220, 240, 255, 90))

def pill(name, w, h):
    k = 4
    im = Image.new("RGBA", (w*k, h*k), (0, 0, 0, 0)); dd = ImageDraw.Draw(im)
    dd.rounded_rectangle([3*k, 3*k, (w-3)*k, (h-3)*k], radius=(h//2-3)*k, fill=(255, 255, 255, 46), outline=(175, 215, 255, 215), width=3*k)
    im.resize((w, h), Image.LANCZOS).save(f"{out}/{name}.png")
pill("sel_pill", 1056, 72)

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
