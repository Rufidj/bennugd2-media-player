#!/usr/bin/env python3
# Prepara las fuentes TrueType del reproductor (res/fonts/*) a partir de las fuentes Noto (licencia OFL).
#   - ui_latin.ttf : Noto Sans completo (latino, cirilico, griego)
#   - ui_jp.otf    : Noto Sans CJK JP recortado a ASCII + kana + JIS X 0208 (+ puntuacion y formas anchas)
import os, sys
from fontTools.ttLib import TTFont
from fontTools import subset

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "res", "fonts")
os.makedirs(out, exist_ok=True)
NOTO = "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"
CJK = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"

import shutil
shutil.copy(NOTO, os.path.join(out, "ui_latin.ttf"))

def jis0208():
    cps = set()
    for lead in range(0x81, 0xF0):
        for trail in range(0x40, 0xFD):
            try:
                cps.add(ord(bytes([lead, trail]).decode("shift_jis")))
            except Exception:
                pass
    return cps

def cjk_subset(face, name, cps):
    f = TTFont(CJK, fontNumber=face)
    opts = subset.Options()
    opts.layout_features = ["kern", "vert", "locl"]
    opts.hinting = False; opts.desubroutinize = True; opts.notdef_outline = True
    opts.name_IDs = ["*"]; opts.drop_tables += ["DSIG"]
    s = subset.Subsetter(opts); s.populate(unicodes=sorted(cps)); s.subset(f)
    p = os.path.join(out, name); f.save(p)
    print(name, os.path.getsize(p) // 1024, "KB", len(cps), "caracteres")

def dbcs(codec, lead_range, trail_range):
    cps = set()
    for lead in lead_range:
        for trail in trail_range:
            try:
                cps.add(ord(bytes([lead, trail]).decode(codec)))
            except Exception:
                pass
    return cps

base = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100))
punct = set(range(0x2000, 0x2070)) | set(range(0x3000, 0x3040)) | set(range(0xFF00, 0xFFF0))
cjk_subset(0, "ui_ja.otf", base | jis0208() | set(range(0x3040, 0x3100)) | punct)                       # JIS X 0208 + kana
cjk_subset(2, "ui_zh.otf", base | dbcs("gb2312", range(0xA1, 0xF8), range(0xA1, 0xFF)) | punct)         # GB2312 (chino simplificado)
cjk_subset(1, "ui_ko.otf", base | dbcs("euc_kr", range(0xB0, 0xCA), range(0xA1, 0xFF)) | set(range(0x1100, 0x1200)) | set(range(0x3130, 0x3190)) | punct)   # hangul KS X 1001
