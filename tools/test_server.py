#!/usr/bin/env python3
# ---------------------------------------------------------------------------------------------
# Servidor de pruebas del reproductor (para probar las cuentas y la API de Xtream sin pagar nada).
#
#   python3 tools/test_server.py [puerto] [direccion]
#
# Levanta un HTTP con:
#   /addons/index.txt, /addons/lists.txt   -> el catálogo de la tienda (con tres listas de prueba)
#   /basic/list.m3u                         -> lista que pide usuario y clave (HTTP Basic)
#   /form/login                             -> login con formulario que devuelve un token JSON
#   /form/list.m3u                          -> lista que pide ese token
#   /player_api.php                         -> la API de Xtream Codes (categorías, canales, series)
#   /stream/canal1.ts                       -> un canal (no es un vídeo de verdad, solo da error al abrir)
#
# En el reproductor:  MP_STORE_URL=http://127.0.0.1:8310/addons
# y en la Tienda se instalan las listas "TV de pago (prueba)", "TV de pago (formulario)" y "Xtream (prueba)".
# El usuario y la clave de todas ellas son  usuario1 / clave-secreta .
#
# Para probarlo en la PS5, dale la IP del PC:  python3 tools/test_server.py 8310 192.168.1.50
# ---------------------------------------------------------------------------------------------
import argparse
import base64
import http.server
import json
import socketserver
import sys
import urllib.parse

USER = "usuario1"
PASSWORD = "clave-secreta"
TOKEN = "TOKEN-12345"

LIST = """#EXTM3U
#EXTINF:-1 tvg-logo="",Canal de prueba
{base}/stream/canal1.ts
"""

INDEX = """# BennuGD2 Media Player - catalogo de addons de prueba
"""

CATEGORIES = {
    "live": [{"category_id": "1", "category_name": "Deportes", "parent_id": False},
             {"category_id": "2", "category_name": "General", "parent_id": False}],
    "vod": [{"category_id": "10", "category_name": "Peliculas", "parent_id": False}],
    "series": [{"category_id": "20", "category_name": "Series", "parent_id": False}],
}

STREAMS = {
    "1": [{"num": 1, "name": "Canal A", "stream_id": "1001", "stream_icon": "",
           "container_extension": "ts", "category_id": "1"},
          {"num": 2, "name": "Canal B", "stream_id": "1002", "stream_icon": "",
           "container_extension": "ts", "category_id": "1"}],
    "2": [{"num": 3, "name": "Canal C", "stream_id": "1003", "stream_icon": "",
           "container_extension": "ts", "category_id": "2"}],
    "10": [{"num": 4, "name": "Pelicula de prueba", "stream_id": "2001", "stream_icon": "",
            "container_extension": "mp4", "category_id": "10"}],
}

SERIES = [{"series_id": "77", "name": "Serie de prueba", "cover": ""}]


class Handler(http.server.BaseHTTPRequestHandler):
    base = ""

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s %s\n" % (self.command, self.path))

    def _send(self, body, code=200, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ------------------------------------------------------------------ la API de Xtream Codes
    def xtream(self, query):
        if query.get("username", [""])[0] != USER or query.get("password", [""])[0] != PASSWORD:
            return self._send(json.dumps({"user_info": {"auth": 0}}), 401, "application/json")
        action = query.get("action", [""])[0]
        if action.endswith("_categories"):
            kind = "live" if action.startswith("get_live") else ("vod" if action.startswith("get_vod") else "series")
            return self._send(json.dumps(CATEGORIES[kind]), 200, "application/json")
        if action.endswith("_streams"):
            cat = query.get("category_id", [""])[0]
            streams = STREAMS.get(cat, [])
            return self._send(json.dumps(streams), 200, "application/json")
        if action == "get_series":
            return self._send(json.dumps(SERIES), 200, "application/json")
        if action == "get_series_info":
            return self._send(json.dumps({
                "info": {"name": "Serie de prueba"},
                "episodes": [{"id": "501", "episode_num": 1, "title": "Episodio 1"},
                             {"id": "502", "episode_num": 2, "title": "Episodio 2"}],
            }), 200, "application/json")
        if action == "":
            return self._send(json.dumps({
                "user_info": {"username": USER, "auth": 1, "status": "Active"},
                "server_info": {"url": self.base, "port": str(PORT), "timezone": "UTC"},
            }), 200, "application/json")
        return self._send(json.dumps({"error": "accion desconocida"}), 404, "application/json")

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        base = self.base
        if url.path == "/addons/index.txt":
            return self._send(INDEX)
        if url.path == "/addons/lists.txt":
            return self._send(
                "# catalogos de prueba\n"
                "TV de pago (prueba) | {b}/basic/list.m3u | Lista que pide usuario y clave | mode=basic\n"
                "TV de pago (formulario) | {b}/form/list.m3u | Lista con login por formulario | mode=form;login={b}/form/login;t=token\n"
                "Xtream (prueba) | {b}/player_api.php | Panel con la API de Xtream Codes | mode=xtream\n".format(b=base))
        if url.path == "/player_api.php":
            return self.xtream(query)
        if url.path == "/basic/list.m3u":
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return self._send("401: hace falta usuario y clave", 401)
            if base64.b64decode(auth[6:]).decode("utf-8", "replace") != "%s:%s" % (USER, PASSWORD):
                return self._send("401: usuario o clave incorrectos", 401)
            return self._send(LIST.format(base=base))
        if url.path == "/form/list.m3u":
            if query.get("token", [""])[0] != TOKEN and self.headers.get("Authorization", "") != TOKEN:
                return self._send("401: token incorrecto", 401)
            return self._send(LIST.format(base=base))
        if url.path == "/stream/canal1.ts":
            if not self.headers.get("Authorization") and query.get("token", [""])[0] != TOKEN:
                return self._send("401: falta la cuenta", 401)
            return self._send(LIST.format(base=base))
        return self._send("no encontrado", 404)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        if url.path != "/form/login":
            return self._send("no encontrado", 404)
        fields = urllib.parse.parse_qs(body)
        if not fields:
            try:
                fields = {k: [v] for k, v in json.loads(body).items()}
            except Exception:
                fields = {}
        if fields.get("username", [""])[0] != USER or fields.get("password", [""])[0] != PASSWORD:
            return self._send(json.dumps({"error": "usuario o clave incorrectos"}), 401, "application/json")
        return self._send(json.dumps({"status": "ok", "token": TOKEN}), 200, "application/json")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    global PORT
    ap = argparse.ArgumentParser(description="servidor de pruebas del reproductor")
    ap.add_argument("port", nargs="?", type=int, default=8310, help="puerto (8310 por defecto)")
    ap.add_argument("host", nargs="?", default="127.0.0.1", help="direccion que pondra en el catalogo")
    args = ap.parse_args()
    PORT = args.port
    Handler.base = "http://%s:%d" % (args.host, args.port)
    with Server(("0.0.0.0", args.port), Handler) as httpd:
        sys.stderr.write("servidor de pruebas en %s\n" % Handler.base)
        sys.stderr.write("  MP_STORE_URL=%s/addons   usuario: %s  clave: %s\n" % (Handler.base, USER, PASSWORD))
        httpd.serve_forever()


if __name__ == "__main__":
    main()
