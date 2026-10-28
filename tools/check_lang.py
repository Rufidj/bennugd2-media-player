#!/usr/bin/env python3
# Comprueba que los textos que pide el codigo (tr("clave")) esten en todos los ficheros de lang/,
# y avisa de claves que sobran.  Uso:  python3 tools/check_lang.py   (sale con 1 si falta alguna)
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SOURCES = ["mediaplayer.prg", "addon_ui.prg", "addon.prg", "fileops.prg", "imageviewer.prg", "torrentplay.prg", "receive.prg", "resume.prg", "update.prg", "dlna.prg"]


def keys_used():
    keys = set()
    for name in SOURCES:
        with open(os.path.join(ROOT, name), encoding="utf-8") as f:
            keys |= set(re.findall(r'tr\("([^"]+)"\)', f.read()))
    return keys


def keys_in(path):
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line and not line.startswith("#") and "=" in line:
                out.add(line.split("=", 1)[0])
    return out


def main():
    used = keys_used()
    langs = sorted(glob.glob(os.path.join(ROOT, "lang", "*.txt")))
    bad = 0
    for path in langs:
        have = keys_in(path)
        missing = sorted(used - have)
        extra = sorted(k for k in have - used if not k.startswith("lang_"))
        if missing:
            bad = 1
            print("FALTAN en %s: %s" % (os.path.basename(path), ", ".join(missing)))
        if extra:
            print("sin usar en %s: %s" % (os.path.basename(path), ", ".join(extra)))
    print("%d claves de texto en %d idiomas%s" % (len(used), len(langs), "" if not bad else " - ¡faltan traducciones!"))
    return bad


if __name__ == "__main__":
    sys.exit(main())
