#!/usr/bin/env python3
# Genera addons/index.txt: la lista que lee la tienda del reproductor.
# Una línea por addon con los datos de su cabecera:  id | nombre | version | ficheros | descripcion
# El id es el nombre de la carpeta (es lo que se descarga: <raiz>/<id>/<fichero>).
# El addon "demo" no se lista: es el ejemplo que trae el reproductor.
import os, re
HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.join(HERE, "..", "addons")
SKIP = {"demo"}


def header(path):
    """campos de la cabecera de un addon (lineas "clave valor" del principio)"""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line[:1].isspace() and line.strip():
                if line.startswith("page ") or line.startswith("define "):
                    break
                m = re.match(r'^(addon|id|version|author|description)\s+(.*?)\s*$', line)
                if m:
                    out[m.group(1)] = m.group(2).strip().strip('"')
    return out


def main():
    rows = []
    for name in sorted(os.listdir(ADDONS)):
        if name in SKIP:
            continue
        d = os.path.join(ADDONS, name)
        main_addon = os.path.join(d, "main.addon")
        if not os.path.isfile(main_addon):
            continue
        h = header(main_addon)
        if not h.get("addon"):
            print("saltado (sin cabecera):", name)
            continue
        files = ["main.addon"]
        if os.path.isfile(os.path.join(d, "logo.png")):
            files.append("logo.png")
        desc = h.get("description", "").replace("|", "/")
        rows.append((h.get("addon", name), name, h.get("version", "1.0"), ",".join(files), desc))
    rows.sort(key=lambda r: r[0].lower())
    out = os.path.join(ADDONS, "index.txt")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("# BennuGD2 Media Player - addons de la tienda\n")
        f.write("# id | nombre | version | ficheros | descripcion\n")
        for r in rows:
            f.write("%s | %s | %s | %s | %s\n" % (r[1], r[0], r[2], r[3], r[4]))
    print("escrito", out, "(%d addons)" % len(rows))


if __name__ == "__main__":
    main()
