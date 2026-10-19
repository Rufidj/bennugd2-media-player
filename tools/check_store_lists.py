#!/usr/bin/env python3
# Comprueba addons/lists.txt: la lista de listas de TV y radio que ofrece la tienda del reproductor.
# Descarga cada direccion y avisa si no responde, si no parece una lista M3U, si tarda demasiado o si
# trae mas entradas de las que el reproductor puede mostrar (2047: se quedaria cortada).
#
#   python3 tools/check_store_lists.py [--no-download]
#
# El navegador del reproductor lee "#EXTINF:-1[,tvg-logo=...] Titulo" y la linea siguiente con la
# direccion; las listas de TDTChannels e iptv-org usan ese mismo formato.
import argparse
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LISTS = os.path.join(HERE, "..", "addons", "lists.txt")
UA = "BennuGD2-MediaPlayer-Lists-Checker/1.0"
MAX_ENTRIES = 2047          # wl_t[2048] en mediaplayer.prg
MAX_BYTES = 8 << 20         # libmod_video: no baja mas de 8 MB de una vez


def rows(path):
    """lineas utiles de lists.txt: (fichero, direccion, descripcion)"""
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n").strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 3 or not parts[0] or not parts[1]:
                print(f"{path}:{n}: linea mal formada: {line}")
                continue
            out.append((parts[0], parts[1], parts[2], n))
    return out


def check(name, url, line):
    ok = True
    if not re.match(r"^https?://", url):
        print(f"  linea {line}: {name}: la direccion no es http(s)")
        return False
    if name.endswith(".m3u"):
        print(f"  linea {line}: {name}: el nombre no lleva .m3u (la tienda lo añade)")
    if not args.no_download:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=45) as r:
                data = r.read(MAX_BYTES + 1)
                status = r.status
        except urllib.error.HTTPError as e:
            print(f"  linea {line}: {name}: HTTP {e.code}")
            return False
        except Exception as e:                                # red, DNS, TLS...
            print(f"  linea {line}: {name}: {e}")
            return False
        if status != 200:
            print(f"  linea {line}: {name}: HTTP {status}")
            return False
        if len(data) > MAX_BYTES:
            print(f"  linea {line}: {name}: mas de 8 MB, no se descargaria entera")
            ok = False
        text = data.decode("utf-8", "replace")
        entries = [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
        if not entries or not any("://" in ln for ln in entries):
            print(f"  linea {line}: {name}: no parece una lista M3U ({len(data)} bytes)")
            return False
        if len(entries) > MAX_ENTRIES:
            print(f"  linea {line}: {name}: {len(entries)} entradas (el reproductor muestra {MAX_ENTRIES})")
            ok = False
        print(f"  linea {line}: {name}: {len(entries)} entradas, {len(data) // 1024} KiB")
    return ok


def main():
    global args
    ap = argparse.ArgumentParser(description="comprueba addons/lists.txt (listas de la tienda)")
    ap.add_argument("--no-download", action="store_true", help="solo comprueba el formato del fichero")
    args = ap.parse_args()
    rows_ = rows(LISTS)
    print(f"{LISTS}: {len(rows_)} listas")
    bad = 0
    for name, url, desc, line in rows_:
        if not check(name, url, line):
            bad += 1
        elif not desc:
            print(f"  linea {line}: {name}: sin descripcion")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
