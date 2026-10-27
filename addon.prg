// ==========================================================================================================
//  addon.prg - intérprete del lenguaje de addons del reproductor (escrito en BennuGD, incluido por mediaplayer.prg)
//
//  Un addon es un archivo de texto (main.addon) con un lenguaje casi en inglés. El reproductor lo lee y lo ejecuta:
//  puede pedir páginas por HTTP (JSON o texto), recorrer los datos y mostrar carpetas, vídeos, canciones y radios.
//  No puede tocar archivos ni ejecutar programas. Guía: ADDONS.md
//
//  Hooks que debe definir quien incluya este archivo (el reproductor o el banco de pruebas):
//      ui_wait_frame()                     un fotograma de interfaz mientras el addon espera (red, teclado, pausa)
//      string host_ask(prompt, def, secret) pide un texto al usuario ("" y host_cancelled=1 si cancela)
//      host_message(text)                  muestra un mensaje en pantalla ("" lo quita)
//      host_log(text)                      registro del addon
//      string host_setting_get(name)       valor guardado de un ajuste ("\x01" si no existe)
//      host_setting_set(name, value)       guarda un ajuste
// ==========================================================================================================

const
    // tipos de valor
    VT_NULL = 0; VT_BOOL = 1; VT_NUM = 2; VT_STR = 3; VT_LIST = 4; VT_MAP = 5;
    NV   = 40000;             // valores
    NPOOL = 150000;           // celdas de listas y registros
    HTTP_MAX = 2097152;       // bytes de una respuesta

global
    // ---- almacén de valores (todo lo que crea una ejecución vive aquí y se descarta al terminar)
    int    ad_vt[NV];           // tipo
    double ad_vn[NV];           // número (o 0/1 para si/no)
    string ad_vs[NV];           // texto
    int    ad_vp[NV];           // lista/registro: posición de inicio en el pool
    int    ad_vc[NV];           // elementos
    int    ad_vcap[NV];         // capacidad reservada en el pool
    int    ad_nv;
    int    ad_pi[NPOOL];        // pool: valor (listas y registros)
    string ad_pk[NPOOL];        // pool: clave (solo registros)
    int    ad_np;
    string ad_err = "";         // mensaje de error de la ejecución actual (vacío = todo bien)
    int    ad_cancelled;        // el usuario canceló
    byte   ad_buf[HTTP_MAX];    // última respuesta HTTP (cuerpo)
    int    ad_buf_len;
    char   ad_chunk[4100];
    char   ad_work[8300];
    int    ad_ji, ad_jn;        // posición y final del lector de JSON
    // traducciones del addon (lang/<idioma>.txt junto a main.addon: "texto en inglés => traducción", una por línea)
    string ad_tr_k[400]; string ad_tr_v[400]; int ad_tr_n;
end

function ad_fail(string msg)
begin
    if (ad_err == "") ad_err = msg; end
    return 0;
end

function ad_values_reset()
private int i;
begin
    for (i = 3; i < ad_nv; i++) ad_vs[i] = ""; end
    for (i = 0; i < ad_np; i++) ad_pk[i] = ""; end
    ad_nv = 3; ad_np = 0;
    ad_vt[0] = VT_NULL;
    ad_vt[1] = VT_BOOL; ad_vn[1] = 1;       // 1 = si
    ad_vt[2] = VT_BOOL; ad_vn[2] = 0;       // 2 = no
end

function ad_new(int t)
begin
    if (ad_nv >= NV) ad_fail("the addon used too much memory (too many values)"); return 0; end
    ad_vt[ad_nv] = t; ad_vn[ad_nv] = 0; ad_vs[ad_nv] = ""; ad_vp[ad_nv] = 0; ad_vc[ad_nv] = 0; ad_vcap[ad_nv] = 0;
    ad_nv++;
    return ad_nv - 1;
end

function ad_num(double d)
private int v;
begin
    v = ad_new(VT_NUM); ad_vn[v] = d; return v;
end

function ad_str(string s)
private int v;
begin
    v = ad_new(VT_STR); ad_vs[v] = s; return v;
end

function ad_bool(int b)
begin
    if (b) return 1; end
    return 2;
end

function ad_list()
begin
    return ad_new(VT_LIST);
end

function ad_map()
begin
    return ad_new(VT_MAP);
end

// reserva (o amplia) el bloque del pool de una lista/registro
function ad_grow(int v)
private int ncap, start, i;
begin
    if (ad_vc[v] < ad_vcap[v]) return 1; end
    ncap = ad_vcap[v] == 0 ? 8 : ad_vcap[v] * 2;
    if (ad_np + ncap > NPOOL) ad_fail("the addon used too much memory (the data is too big)"); return 0; end
    start = ad_np; ad_np += ncap;
    for (i = 0; i < ad_vc[v]; i++) ad_pi[start + i] = ad_pi[ad_vp[v] + i]; ad_pk[start + i] = ad_pk[ad_vp[v] + i]; end
    ad_vp[v] = start; ad_vcap[v] = ncap;
    return 1;
end

function ad_list_add(int l, int item)
begin
    if (!ad_grow(l)) return 0; end
    ad_pi[ad_vp[l] + ad_vc[l]] = item; ad_vc[l]++;
    return 1;
end

function ad_map_find(int m, string k)
private int i;
begin
    for (i = 0; i < ad_vc[m]; i++)
        if (ad_pk[ad_vp[m] + i] == k) return i; end
    end
    return -1;
end

// valor de un campo (-1 si no existe)
function ad_map_get(int m, string k)
private int i;
begin
    i = ad_map_find(m, k);
    if (i < 0) return -1; end
    return ad_pi[ad_vp[m] + i];
end

function ad_map_set(int m, string k, int item)
private int i;
begin
    i = ad_map_find(m, k);
    if (i >= 0) ad_pi[ad_vp[m] + i] = item; return 1; end
    if (!ad_grow(m)) return 0; end
    ad_pk[ad_vp[m] + ad_vc[m]] = k; ad_pi[ad_vp[m] + ad_vc[m]] = item; ad_vc[m]++;
    return 1;
end

function ad_truthy(int v)
begin
    switch (ad_vt[v])
        case VT_NULL: return 0; end
        case VT_BOOL, VT_NUM: return ad_vn[v] != 0; end
        case VT_STR: return len(ad_vs[v]) > 0; end
        default: return ad_vc[v] > 0; end
    end
end

declare function string ad_text(int v) end

function ad_equal(int a, int b)
private int i, k;
begin
    if (ad_vt[a] != ad_vt[b])
        if (ad_vt[a] == VT_NUM && ad_vt[b] == VT_STR) return ad_text(a) == ad_vs[b]; end
        if (ad_vt[a] == VT_STR && ad_vt[b] == VT_NUM) return ad_vs[a] == ad_text(b); end
        return 0;
    end
    switch (ad_vt[a])
        case VT_NULL: return 1; end
        case VT_BOOL, VT_NUM: return ad_vn[a] == ad_vn[b]; end
        case VT_STR: return ad_vs[a] == ad_vs[b]; end
        case VT_LIST:
            if (ad_vc[a] != ad_vc[b]) return 0; end
            for (i = 0; i < ad_vc[a]; i++) if (!ad_equal(ad_pi[ad_vp[a] + i], ad_pi[ad_vp[b] + i])) return 0; end end
            return 1;
        end
        default:
            if (ad_vc[a] != ad_vc[b]) return 0; end
            for (i = 0; i < ad_vc[a]; i++)
                k = ad_map_get(b, ad_pk[ad_vp[a] + i]);
                if (k < 0 || !ad_equal(ad_pi[ad_vp[a] + i], k)) return 0; end
            end
            return 1;
        end
    end
end

function string ad_type_name(int v)
begin
    switch (ad_vt[v])
        case VT_NULL: return "nothing"; end
        case VT_BOOL: return "yes/no"; end
        case VT_NUM: return "number"; end
        case VT_STR: return "text"; end
        case VT_LIST: return "list"; end
        default: return "record"; end
    end
end

// número como texto sin ceros inútiles
function string ad_num_text(double d)
private string s; int n;
begin
    if (d == (int)d && d < 1000000000000 && d > -1000000000000)
        return "" + (int)d;
    end
    s = format(d, 6);
    n = len(s);
    while (n > 1 && substr(s, n - 1, 1) == "0") n--; end
    if (n > 0 && substr(s, n - 1, 1) == ".") n--; end
    return substr(s, 0, n);
end

// ---- texto escapado para JSON
function string ad_json_quote(string s)
private string r; int i, n, c;
begin
    r = "\"";
    n = len(s);
    for (i = 0; i < n; i++)
        c = asc(substr(s, i, 1));
        if (c == 34) r += "\\\"";
        elseif (c == 92) r += "\\\\";
        elseif (c == 10) r += "\\n";
        elseif (c == 13) r += "\\r";
        elseif (c == 9) r += "\\t";
        elseif (c < 32) r += " ";
        else r += chr(c);
        end
    end
    return r + "\"";
end

function string ad_json_text(int v)
private string r; int i;
begin
    switch (ad_vt[v])
        case VT_NULL: return "null"; end
        case VT_BOOL: return ad_vn[v] ? "true" : "false"; end
        case VT_NUM: return ad_num_text(ad_vn[v]); end
        case VT_STR: return ad_json_quote(ad_vs[v]); end
        case VT_LIST:
            r = "[";
            for (i = 0; i < ad_vc[v]; i++) if (i > 0) r += ","; end r += ad_json_text(ad_pi[ad_vp[v] + i]); end
            return r + "]";
        end
        default:
            r = "{";
            for (i = 0; i < ad_vc[v]; i++) if (i > 0) r += ","; end r += ad_json_quote(ad_pk[ad_vp[v] + i]) + ":" + ad_json_text(ad_pi[ad_vp[v] + i]); end
            return r + "}";
        end
    end
end

function string ad_text(int v)
begin
    switch (ad_vt[v])
        case VT_NULL: return ""; end
        case VT_BOOL: return ad_vn[v] ? "yes" : "no"; end
        case VT_NUM: return ad_num_text(ad_vn[v]); end
        case VT_STR: return ad_vs[v]; end
        default: return ad_json_text(v); end
    end
end

// ==========================================================================================================
//  Lector de JSON: lee del buffer ad_buf (donde http_get deja la respuesta) y crea valores
// ==========================================================================================================

// bytes del buffer -> texto
function string ad_buf_str(int start, int n)
private string r; int off, k;
begin
    r = "";
    off = 0;
    while (off < n)
        k = n - off; if (k > 4000) k = 4000; end
        mem_copy(&ad_chunk, &ad_buf[start + off], k);
        ad_chunk[k] = 0;
        r += ad_chunk;
        off += k;
    end
    return r;
end

// copia un texto al buffer (para leer JSON que ya estaba en una variable)
function ad_str_to_buf(string s)
private int i, n;
begin
    n = len(s);
    if (n >= HTTP_MAX) n = HTTP_MAX - 1; end
    for (i = 0; i < n; i++) ad_buf[i] = asc(substr(s, i, 1)); end
    ad_buf_len = n;
end

function ad_jws()
private int c;
begin
    while (ad_ji < ad_jn)
        c = ad_buf[ad_ji];
        if (c != 32 && c != 9 && c != 10 && c != 13) break; end
        ad_ji++;
    end
end

function ad_jfail(string what)
private int ln_no, i;
begin
    ln_no = 1;
    for (i = 0; i < ad_ji && i < ad_jn; i++) if (ad_buf[i] == 10) ln_no++; end end
    ad_fail("invalid JSON (" + what + ") near position " + ad_ji + ", line " + ln_no);
    return -1;
end

// añade un codepoint como UTF-8 al buffer de trabajo
function ad_put_utf8(int cp, int pos)
begin
    if (cp < 128)
        ad_work[pos] = cp; return pos + 1;
    elseif (cp < 2048)
        ad_work[pos] = 192 | (cp >> 6); ad_work[pos + 1] = 128 | (cp & 63); return pos + 2;
    elseif (cp < 65536)
        ad_work[pos] = 224 | (cp >> 12); ad_work[pos + 1] = 128 | ((cp >> 6) & 63); ad_work[pos + 2] = 128 | (cp & 63); return pos + 3;
    else
        ad_work[pos] = 240 | (cp >> 18); ad_work[pos + 1] = 128 | ((cp >> 12) & 63); ad_work[pos + 2] = 128 | ((cp >> 6) & 63); ad_work[pos + 3] = 128 | (cp & 63); return pos + 4;
    end
end

function ad_hexval(int c)
begin
    if (c >= 48 && c <= 57) return c - 48; end
    if (c >= 97 && c <= 102) return c - 87; end
    if (c >= 65 && c <= 70) return c - 55; end
    return -1;
end

// lee un texto JSON (ad_ji apunta a la comilla inicial); devuelve el texto
function string ad_jstring()
private int start, c, esc, w, cp, lo, h1, h2, h3, h4; string r;
begin
    ad_ji++;
    start = ad_ji; esc = 0;
    // ¿lleva escapes? busca el final
    while (ad_ji < ad_jn)
        c = ad_buf[ad_ji];
        if (c == 34) break; end
        if (c == 92) esc = 1; ad_ji++; end
        ad_ji++;
    end
    if (ad_ji >= ad_jn) ad_jfail("unterminated text"); return ""; end
    if (!esc)
        r = ad_buf_str(start, ad_ji - start);
        ad_ji++;
        return r;
    end
    // con escapes: se decodifica en ad_work por trozos
    r = ""; w = 0;
    ad_ji = start;
    while (ad_ji < ad_jn && ad_buf[ad_ji] != 34)
        c = ad_buf[ad_ji];
        if (c == 92 && ad_ji + 1 < ad_jn)
            ad_ji++; c = ad_buf[ad_ji];
            switch (c)
                case 110: ad_work[w] = 10; w++; end
                case 116: ad_work[w] = 9; w++; end
                case 114: ad_work[w] = 13; w++; end
                case 98: ad_work[w] = 8; w++; end
                case 102: ad_work[w] = 12; w++; end
                case 117:
                    h1 = ad_hexval(ad_buf[ad_ji + 1]); h2 = ad_hexval(ad_buf[ad_ji + 2]); h3 = ad_hexval(ad_buf[ad_ji + 3]); h4 = ad_hexval(ad_buf[ad_ji + 4]);
                    if (h1 >= 0 && h2 >= 0 && h3 >= 0 && h4 >= 0)
                        cp = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4; ad_ji += 4;
                        if (cp >= 55296 && cp < 56320 && ad_buf[ad_ji + 1] == 92 && ad_buf[ad_ji + 2] == 117)
                            h1 = ad_hexval(ad_buf[ad_ji + 3]); h2 = ad_hexval(ad_buf[ad_ji + 4]); h3 = ad_hexval(ad_buf[ad_ji + 5]); h4 = ad_hexval(ad_buf[ad_ji + 6]);
                            lo = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4;
                            if (lo >= 56320 && lo < 57344) cp = 65536 + ((cp - 55296) << 10) + (lo - 56320); ad_ji += 6; end
                        end
                        w = ad_put_utf8(cp, w);
                    end
                end
                default: ad_work[w] = c; w++; end
            end
            ad_ji++;
        else
            ad_work[w] = c; w++; ad_ji++;
        end
        if (w > 8000) ad_work[w] = 0; r += ad_work; w = 0; end
    end
    if (ad_ji >= ad_jn) ad_jfail("unterminated text"); return ""; end
    ad_ji++;
    ad_work[w] = 0; r += ad_work;
    return r;
end

function ad_jnumber()
private int neg, ex, exneg; double d, fscale;
begin
    neg = 0; d = 0;
    if (ad_buf[ad_ji] == 45) neg = 1; ad_ji++; end
    while (ad_ji < ad_jn && ad_buf[ad_ji] >= 48 && ad_buf[ad_ji] <= 57) d = d * 10 + (ad_buf[ad_ji] - 48); ad_ji++; end
    if (ad_ji < ad_jn && ad_buf[ad_ji] == 46)
        ad_ji++; fscale = 0.1;
        while (ad_ji < ad_jn && ad_buf[ad_ji] >= 48 && ad_buf[ad_ji] <= 57) d = d + (ad_buf[ad_ji] - 48) * fscale; fscale = fscale / 10; ad_ji++; end
    end
    if (ad_ji < ad_jn && (ad_buf[ad_ji] == 101 || ad_buf[ad_ji] == 69))
        ad_ji++; exneg = 0; ex = 0;
        if (ad_buf[ad_ji] == 45) exneg = 1; ad_ji++; elseif (ad_buf[ad_ji] == 43) ad_ji++; end
        while (ad_ji < ad_jn && ad_buf[ad_ji] >= 48 && ad_buf[ad_ji] <= 57) ex = ex * 10 + (ad_buf[ad_ji] - 48); ad_ji++; end
        while (ex > 0) if (exneg) d = d / 10; else d = d * 10; end ex--; end
    end
    if (neg) d = -d; end
    return ad_num(d);
end

function ad_jvalue(int depth)
private int c, v, item, k; string name;
begin
    if (ad_err != "") return -1; end
    ad_jws();
    if (ad_ji >= ad_jn) return ad_jfail("unexpected end"); end
    if (depth > 100) return ad_jfail("too deeply nested"); end
    c = ad_buf[ad_ji];
    if (c == 123)                                   // {
        v = ad_map(); ad_ji++; ad_jws();
        if (ad_ji < ad_jn && ad_buf[ad_ji] == 125) ad_ji++; return v; end
        loop
            ad_jws();
            if (ad_ji >= ad_jn || ad_buf[ad_ji] != 34) return ad_jfail("expected a field name"); end
            name = ad_jstring(); if (ad_err != "") return -1; end
            ad_jws();
            if (ad_ji >= ad_jn || ad_buf[ad_ji] != 58) return ad_jfail("expected ':'"); end
            ad_ji++;
            item = ad_jvalue(depth + 1); if (item < 0) return -1; end
            ad_map_set(v, name, item);
            ad_jws();
            if (ad_ji < ad_jn && ad_buf[ad_ji] == 44) ad_ji++; continue; end
            if (ad_ji < ad_jn && ad_buf[ad_ji] == 125) ad_ji++; break; end
            return ad_jfail("expected ',' or '}'");
        end
        return v;
    elseif (c == 91)                                // [
        v = ad_list(); ad_ji++; ad_jws();
        if (ad_ji < ad_jn && ad_buf[ad_ji] == 93) ad_ji++; return v; end
        loop
            item = ad_jvalue(depth + 1); if (item < 0) return -1; end
            ad_list_add(v, item);
            ad_jws();
            if (ad_ji < ad_jn && ad_buf[ad_ji] == 44) ad_ji++; continue; end
            if (ad_ji < ad_jn && ad_buf[ad_ji] == 93) ad_ji++; break; end
            return ad_jfail("expected ',' or ']'");
        end
        return v;
    elseif (c == 34)
        return ad_str(ad_jstring());
    elseif (c == 116 && ad_buf[ad_ji + 1] == 114) ad_ji += 4; return 1;
    elseif (c == 102 && ad_buf[ad_ji + 1] == 97) ad_ji += 5; return 2;
    elseif (c == 110 && ad_buf[ad_ji + 1] == 117) ad_ji += 4; return 0;
    elseif (c == 45 || (c >= 48 && c <= 57))
        return ad_jnumber();
    end
    return ad_jfail("unexpected character");
end

// interpreta ad_buf[0..ad_buf_len) como JSON; devuelve el valor o -1 (con ad_err)
function ad_json_parse()
private int v;
begin
    ad_ji = 0; ad_jn = ad_buf_len;
    if (ad_jn >= 3 && ad_buf[0] == 239 && ad_buf[1] == 187 && ad_buf[2] == 191) ad_ji = 3; end      // marca BOM
    v = ad_jvalue(0);
    if (v >= 0)
        ad_jws();
        if (ad_ji < ad_jn) return ad_jfail("extra text after the data"); end
    end
    return v;
end

// ==========================================================================================================
//  Cliente HTTP (HTTP/1.0 sobre libmod_net). No hay HTTPS: las direcciones de API deben ser http://
//  (los vídeos y la música que se reproducen sí pueden ser https: eso lo hace el reproductor, no el addon).
// ==========================================================================================================
global
    char ad_sbuf[4100];
    char ad_rbuf[4100];
    int  ad_http_status;
    string ad_http_location = "";
    string ad_http_headers = "";     // cabeceras de la respuesta (en minúsculas)
end

function ad_buf_find(string needle, int pos0, int upto)
private int i, j, n, ok;
begin
    n = len(needle);
    for (i = pos0; i + n <= upto; i++)
        if (ad_buf[i] == asc(substr(needle, 0, 1)))
            ok = 1;
            for (j = 1; j < n; j++) if (ad_buf[i + j] != asc(substr(needle, j, 1))) ok = 0; break; end end
            if (ok) return i; end
        end
    end
    return -1;
end

// una sola petición (sin seguir redirecciones). 1 = recibida (cuerpo en ad_buf, estado en ad_http_status)
function ad_http_once(string method, string host, int port, string path, string hdrs, string body)
private int *sock; int *lst; int n, st, idle, off, k, i, tmo; string req;
begin
    ad_buf_len = 0; ad_http_status = 0;
    sock = net_open(NET_MODE_CLIENT, NET_PROTO_TCP, host, port);
    if (sock == 0) ad_fail("could not connect to " + host + " port " + port + " (is the address right and the server running?)"); return 0; end
    req = method + " " + path + " HTTP/1.0" + chr(13) + chr(10);
    req += "Host: " + host + (port != 80 ? ":" + port : "") + chr(13) + chr(10);
    req += "User-Agent: BennuGD2-MediaPlayer-Addon/1.0" + chr(13) + chr(10) + "Connection: close" + chr(13) + chr(10);
    if (hdrs != "") req += hdrs; end
    if (body != "") req += "Content-Length: " + len(body) + chr(13) + chr(10); end
    req += chr(13) + chr(10) + body;
    off = 0;
    while (off < len(req))
        k = len(req) - off; if (k > 4000) k = 4000; end
        for (i = 0; i < k; i++) ad_sbuf[i] = asc(substr(req, off + i, 1)); end
        n = net_send(sock, &ad_sbuf, k);
        if (n <= 0) net_close(sock); ad_fail("could not send the request to " + host); return 0; end
        off += k;
    end
    lst = list_create(); list_insertItem(lst, sock);
    idle = 0; tmo = 1200;                                          // 20 s sin recibir nada
    loop
        if (ad_cancelled) break; end
        st = net_wait(lst, 0, NULL);
        if (st > 0)
            n = net_recv(sock, &ad_rbuf, 4096);
            if (n <= NET_DISCONNECTED) break; end
            if (n > 0)
                if (ad_buf_len + n >= HTTP_MAX) net_close(sock); list_free(lst); ad_fail("the answer is too big for an addon (limit 2 MB)"); return 0; end
                mem_copy(&ad_buf[ad_buf_len], &ad_rbuf, n); ad_buf_len += n; idle = 0;
            end
        else
            idle++;
            if (idle > tmo) net_close(sock); list_free(lst); ad_fail("the server did not answer in time (" + host + ")"); return 0; end
            ui_wait_frame();
        end
    end
    net_close(sock); list_free(lst);
    if (ad_cancelled) ad_fail("cancelled"); return 0; end
    if (ad_buf_len < 12) ad_fail("the server closed the connection without answering (" + host + ")"); return 0; end
    return 1;
end

// separa cabeceras y cuerpo, lee el estado, decodifica "chunked"; deja el cuerpo al principio de ad_buf
function ad_http_split()
private int hend, i, c, sz, p, outp, chunked, digit, ok; string h, low;
begin
    hend = ad_buf_find(chr(13) + chr(10) + chr(13) + chr(10), 0, ad_buf_len);
    if (hend < 0) ad_fail("the server answer has no headers"); return 0; end
    h = ad_buf_str(0, hend);
    low = lcase(h);
    ad_http_headers = low;
    ad_http_status = 0;
    if (substr(low, 0, 5) == "http/") ad_http_status = atoi(substr(low, 9, 3)); end
    ad_http_location = "";
    i = find(low, chr(10) + "location:");
    if (i >= 0)
        p = i + 10; c = find(h, chr(13), p);
        if (c < 0) c = len(h); end
        ad_http_location = substr(h, p, c - p);
        while (len(ad_http_location) > 0 && substr(ad_http_location, 0, 1) == " ") ad_http_location = substr(ad_http_location, 1); end
    end
    chunked = find(low, "transfer-encoding: chunked") >= 0;
    p = hend + 4;
    if (!chunked)
        mem_move(&ad_buf[0], &ad_buf[p], ad_buf_len - p);
        ad_buf_len -= p;
        return 1;
    end
    // cuerpo por trozos: <hex>\r\n datos \r\n ... 0\r\n
    outp = 0;
    loop
        sz = 0; ok = 0;
        while (p < ad_buf_len && ad_buf[p] != 13 && ad_buf[p] != 59)
            digit = ad_hexval(ad_buf[p]);
            if (digit >= 0) sz = sz * 16 + digit; ok = 1; end
            p++;
        end
        while (p < ad_buf_len && ad_buf[p] != 10) p++; end
        p++;
        if (!ok || sz == 0) break; end
        if (p + sz > ad_buf_len) sz = ad_buf_len - p; end
        mem_move(&ad_buf[outp], &ad_buf[p], sz);
        outp += sz; p += sz + 2;
        if (p >= ad_buf_len) break; end
    end
    ad_buf_len = outp;
    return 1;
end

// petición https por el motor (FFmpeg sabe TLS y sigue las redirecciones). 1 = bien (cuerpo en ad_buf)
function ad_https_once(string method, string url, string hdrs, string body)
private int n;
begin
    ad_buf_len = 0; ad_http_status = http_fetch(url, hdrs, method, body);
    if (ad_http_status == 0) ad_fail("could not connect to " + substr(url, 0, 80) + " (" + http_error() + ")"); return 0; end
    if (ad_http_status != 200) return 1; end
    n = http_length();
    if (n >= HTTP_MAX) ad_fail("the answer is too big for an addon (limit 2 MB)"); return 0; end
    ad_buf_len = http_read(&ad_buf[0], n);
    return 1;
end

// petición completa con redirecciones http. 1 = bien (cuerpo en ad_buf)
function ad_http(string method, string url, string hdrs, string body)
private int tries, port, sl, co, ok; string rest, host, path, hostport, loc;
begin
    tries = 0;
    loop
        if (substr(url, 0, 8) == "https://")
            if (!ad_https_once(method, url, hdrs, body)) return 0; end
            if (ad_http_status == 200) return 1; end
        else
            if (substr(url, 0, 7) != "http://") ad_fail("the address must start with http:// or https:// (got \"" + substr(url, 0, 40) + "\")"); return 0; end
            rest = substr(url, 7);
            sl = find(rest, "/");
            if (sl < 0) hostport = rest; path = "/"; else hostport = substr(rest, 0, sl); path = substr(rest, sl); end
            co = find(hostport, ":");
            if (co >= 0) host = substr(hostport, 0, co); port = atoi(substr(hostport, co + 1)); else host = hostport; port = 80; end
            if (host == "") ad_fail("the address has no server name"); return 0; end
            ok = ad_http_once(method, host, port, path, hdrs, body);
            if (!ok) return 0; end
            if (!ad_http_split()) return 0; end
        end
        if (ad_http_status >= 200 && ad_http_status < 300) return 1; end
        if (ad_http_status == 301 || ad_http_status == 302 || ad_http_status == 303 || ad_http_status == 307 || ad_http_status == 308)
            tries++;
            if (tries > 4 || ad_http_location == "") ad_fail("too many redirections"); return 0; end
            loc = ad_http_location;
            if (substr(loc, 0, 1) == "/") loc = "http://" + hostport + loc; end
            url = loc;
            if (ad_http_status == 303) method = "GET"; body = ""; end
            continue;
        end
        if (ad_http_status == 401) ad_fail("the server answered 401 (not authorised): check the token or password in the addon settings"); return 0; end
        if (ad_http_status == 403) ad_fail("the server answered 403 (forbidden)"); return 0; end
        if (ad_http_status == 404) ad_fail("the server answered 404 (not found): " + substr(url, 0, 90)); return 0; end
        ad_fail("the server answered with error " + ad_http_status); return 0;
    end
end

// ==========================================================================================================
//  El lenguaje: lector de palabras (lexer) y analizador (parser)
// ==========================================================================================================
const
    TK_END = 0; TK_WORD = 1; TK_NUM = 2; TK_STR = 3; TK_SYM = 4;
    AD_MAXLN = 3000; AD_MAXTOK = 40000; AD_CAPX = 30000; AD_CAPS = 6000; AD_CAPA = 4000; AD_CAPPG = 200;
    // expresiones
    XK_NUM = 0; XK_STR = 1; XK_BOOL = 2; XK_NULL = 3; XK_VAR = 4; XK_FIELD = 5; XK_INDEX = 6; XK_CALL = 7; XK_BIN = 8; XK_NOT = 9; XK_NEG = 10;
    XK_LIST = 11; XK_MAP = 12; XK_CMP = 13; XK_AND = 14; XK_OR = 15; XK_LIT = 16; XK_ENTRY = 17;
    CM_EQ = 0; CM_NE = 1; CM_GT = 2; CM_LT = 3; CM_GE = 4; CM_LE = 5; CM_EMPTY = 6; CM_NOTEMPTY = 7; CM_NOTHING = 8; CM_NOTNOTHING = 9;
    CM_CONTAINS = 10; CM_STARTS = 11; CM_ENDS = 12;
    // sentencias
    SK_SET = 0; SK_ADD = 1; SK_IF = 2; SK_FOR = 3; SK_WHILE = 4; SK_REPEAT = 5; SK_STOP = 6; SK_SKIP = 7; SK_EXIT = 8; SK_FETCH = 9; SK_TRY = 10;
    SK_FAIL = 11; SK_SHOW = 12; SK_ASK = 13; SK_MESSAGE = 14; SK_WAIT = 15; SK_SAVE = 16; SK_LOG = 17; SK_GIVE = 18; SK_CALL = 19; SK_CLEAR = 20; SK_GOTO = 21;
    FL_NORMAL = 0; FL_STOP = 1; FL_SKIP = 2; FL_EXIT = 3; FL_RETURN = 4;
end

global
    // líneas y palabras del programa
    int    ad_ln_ind[AD_MAXLN]; int ad_ln_no[AD_MAXLN]; int ad_ln_t0[AD_MAXLN]; int ad_nln;
    int    ad_tk_t[AD_MAXTOK]; string ad_tk_s[AD_MAXTOK]; double ad_tk_n[AD_MAXTOK]; int ad_ntk;
    string ad_src_file = "";
    string ad_perr = "";                  // error de sintaxis (vacío = bien)
    int    ad_cl, ad_ct, ad_cur_lineno;   // cursor del analizador
    // expresiones
    int    ad_xk[AD_CAPX]; int ad_xa[AD_CAPX]; int ad_xb[AD_CAPX]; int ad_xnext[AD_CAPX]; int ad_xop[AD_CAPX]; double ad_xn[AD_CAPX]; string ad_xs[AD_CAPX]; int ad_xl[AD_CAPX]; int ad_nx;
    // sentencias (hasta 8 expresiones cada una)
    int    ad_sk[AD_CAPS]; int ad_sl[AD_CAPS]; int ad_smode[AD_CAPS]; int ad_sflag[AD_CAPS]; int ad_se[AD_CAPS * 8]; string ad_sname[AD_CAPS];
    int    ad_sargs[AD_CAPS]; int ad_shdrs[AD_CAPS]; int ad_sbody[AD_CAPS]; int ad_selse[AD_CAPS]; int ad_snext[AD_CAPS]; int ad_ns;
    int    ad_ar_ne[AD_CAPA]; int ad_ar_e[AD_CAPA]; string ad_ar_name[AD_CAPA]; int ad_ar_next[AD_CAPA]; int ad_nar;
    // páginas y funciones
    string ad_pg_name[AD_CAPPG]; int ad_pg_body[AD_CAPPG]; int ad_pg_np[AD_CAPPG]; string ad_pg_par[AD_CAPPG * 12]; int ad_pg_func[AD_CAPPG]; int ad_npg;
    // cabecera del addon
    string ad_i_name = "", ad_i_id = "", ad_i_ver = "", ad_i_author = "", ad_i_desc = "";
    string ad_st_name[24]; string ad_st_label[24]; string ad_st_type[24]; string ad_st_def[24]; string ad_st_choices[24]; int ad_st_hidden[24]; int ad_nst;
    string ad_goto_page = "", ad_goto_args = "";      // "go to PAGE": la pagina a la que hay que ir cuando termina la actual
end

declare function string ad_tv() end
declare function string ad_describe() end
declare function string ad_need_name(string what) end
declare function string ad_hdr_text(int h) end
declare function int ad_parse_or() end
declare function int ad_parse_block(int indent) end

function ad_reset_program()
begin
    ad_nln = 0; ad_ntk = 0; ad_nx = 1; ad_ns = 1; ad_nar = 1; ad_npg = 0; ad_nst = 0; ad_perr = "";
    ad_i_name = ""; ad_i_id = ""; ad_i_ver = ""; ad_i_author = ""; ad_i_desc = "";
end

function ad_perror(string msg)
begin
    if (ad_perr == "") ad_perr = ad_src_file + " line " + ad_cur_lineno + ": " + msg; end
    return 0;
end

function ad_is_alpha(int c) begin return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95; end
function ad_is_digit(int c) begin return c >= 48 && c <= 57; end
function ad_is_space(int c) begin return c == 32 || c == 9 || c == 13; end

function ad_addtok(int t, string s, double n)
begin
    if (ad_ntk >= AD_MAXTOK - 2) ad_perror("this addon is too long"); return 0; end
    ad_tk_t[ad_ntk] = t; ad_tk_s[ad_ntk] = s; ad_tk_n[ad_ntk] = n; ad_ntk++;
    return 1;
end

// divide una línea (sin la sangría) en palabras; añade un TK_END al final. Devuelve el índice de la primera.
function ad_lex(string s, int lineno)
private int first, i, n, c, j, closed, qc; string wd, buf;
begin
    first = ad_ntk; n = len(s); i = 0;
    ad_cur_lineno = lineno;
    while (i < n && ad_perr == "")
        c = asc(substr(s, i, 1));
        if (ad_is_space(c)) i++; continue; end
        if (c == 35) break; end
        if (ad_is_alpha(c))
            j = i; while (j < n && (ad_is_alpha(asc(substr(s, j, 1))) || ad_is_digit(asc(substr(s, j, 1))))) j++; end
            ad_addtok(TK_WORD, substr(s, i, j - i), 0); i = j;
        elseif (ad_is_digit(c))
            j = i; while (j < n && ad_is_digit(asc(substr(s, j, 1)))) j++; end
            if (j + 1 < n && asc(substr(s, j, 1)) == 46 && ad_is_digit(asc(substr(s, j + 1, 1))))
                j++; while (j < n && ad_is_digit(asc(substr(s, j, 1)))) j++; end
            end
            wd = substr(s, i, j - i);
            ad_addtok(TK_NUM, wd, atof(wd)); i = j;
        elseif (c == 34 || c == 39)
            qc = c; j = i + 1; buf = ""; closed = 0;
            while (j < n)
                c = asc(substr(s, j, 1));
                if (c == qc) closed = 1; j++; break; end
                if (qc == 39 && c == 123) buf += chr(1); j++; continue; end
                if (qc == 39 && c == 125) buf += chr(2); j++; continue; end
                if (c == 92 && j + 1 < n)
                    j++; c = asc(substr(s, j, 1));
                    if (c == 110) buf += chr(10);
                    elseif (c == 116) buf += chr(9);
                    elseif (c == 34 || c == 39) buf += chr(c);
                    elseif (c == 92) buf += "\\";
                    elseif (c == 123) buf += chr(1);
                    elseif (c == 125) buf += chr(2);
                    else buf += "\\" + chr(c);
                    end
                    j++;
                else
                    buf += chr(c); j++;
                end
            end
            if (!closed) ad_perror("this text starts with a quote (column " + (i + 1) + ") but never closes"); return first; end
            ad_addtok(TK_STR, buf, 0); i = j;
        else
            wd = substr(s, i, 1);
            if (i + 1 < n)
                c = asc(substr(s, i + 1, 1));
                if (c == 61 && (wd == "=" || wd == "!" || wd == "<" || wd == ">")) wd += "="; end
            end
            if (len(wd) == 1 && find("()[]{},:.+-*/%=<>!", wd) < 0) ad_perror("I do not understand the character '" + wd + "' (column " + (i + 1) + ")"); return first; end
            if (len(wd) == 2 && wd != "==" && wd != "!=" && wd != "<=" && wd != ">=") wd = substr(wd, 0, 1); end
            ad_addtok(TK_SYM, wd, 0); i += len(wd);
        end
    end
    ad_addtok(TK_END, "", 0);
    return first;
end

// ---- ayudas del cursor
function ad_tt() begin return ad_tk_t[ad_ct]; end
function string ad_tv() begin return ad_tk_s[ad_ct]; end
function ad_isw(string w) begin return ad_tk_t[ad_ct] == TK_WORD && ad_tk_s[ad_ct] == w; end
function ad_isw2(string w)
begin
    if (ad_tk_t[ad_ct] == TK_END) return 0; end
    return ad_tk_t[ad_ct + 1] == TK_WORD && ad_tk_s[ad_ct + 1] == w;
end
function ad_iss(string s) begin return ad_tk_t[ad_ct] == TK_SYM && ad_tk_s[ad_ct] == s; end
function ad_accw(string w) begin if (ad_isw(w)) ad_ct++; return 1; end return 0; end
function ad_accs(string s) begin if (ad_iss(s)) ad_ct++; return 1; end return 0; end

function string ad_describe()
begin
    switch (ad_tk_t[ad_ct])
        case TK_END: return "the end of the line"; end
        case TK_WORD: return "the word '" + ad_tk_s[ad_ct] + "'"; end
        case TK_NUM: return "the number " + ad_tk_s[ad_ct]; end
        case TK_STR: return "a piece of text"; end
        default: return "'" + ad_tk_s[ad_ct] + "'"; end
    end
end

function ad_needw(string w, string hint)
begin
    if (ad_accw(w)) return 1; end
    ad_perror("I expected the word '" + w + "' " + (hint != "" ? hint : "here") + " but found " + ad_describe());
    return 0;
end

function ad_needs(string s, string hint)
begin
    if (ad_accs(s)) return 1; end
    ad_perror("I expected '" + s + "' " + (hint != "" ? hint : "here") + " but found " + ad_describe());
    return 0;
end

function ad_need_end()
begin
    if (ad_tk_t[ad_ct] != TK_END) ad_perror("I did not expect " + ad_describe() + " here (this line should have ended)"); return 0; end
    return 1;
end

function ad_is_reserved(string w)
begin
    return find(" set add to from into if otherwise for each in while repeat times stop skip exit loop fetch try on fail show ask message wait save as log give back clear true false nothing and or not is contains starts ends than greater less least most empty limit opening playing logo info year duration with header subtitles default secret doing bound go ", " " + w + " ") >= 0;
end

function string ad_need_name(string what)
private string w;
begin
    if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("I expected " + what + " but found " + ad_describe()); return ""; end
    w = ad_tk_s[ad_ct];
    if (ad_is_reserved(w)) ad_perror("'" + w + "' is a word the language uses, so it cannot be " + what + "; please choose another name"); return ""; end
    ad_ct++;
    return w;
end

// ---- nodos
function ad_nx_new(int kind)
begin
    if (ad_nx >= AD_CAPX - 1) ad_perror("this addon is too big (too many expressions)"); return 0; end
    ad_xk[ad_nx] = kind; ad_xl[ad_nx] = ad_cur_lineno; ad_xa[ad_nx] = 0; ad_xb[ad_nx] = 0; ad_xnext[ad_nx] = 0; ad_xop[ad_nx] = 0; ad_xn[ad_nx] = 0; ad_xs[ad_nx] = "";
    ad_nx++;
    return ad_nx - 1;
end

// ---- expresiones
declare function int ad_parse_interp(string s) end

function ad_parse_primary()
private int e, last, item, ent; string w;
begin
    if (ad_perr != "") return 0; end
    switch (ad_tk_t[ad_ct])
        case TK_NUM: e = ad_nx_new(XK_NUM); ad_xn[e] = ad_tk_n[ad_ct]; ad_ct++; return e; end
        case TK_STR: e = ad_parse_interp(ad_tk_s[ad_ct]); ad_ct++; return e; end
        case TK_SYM:
            w = ad_tk_s[ad_ct];
            if (w == "(")
                ad_ct++; e = ad_parse_or(); ad_needs(")", "to close the bracket"); return e;
            elseif (w == "[")
                ad_ct++; e = ad_nx_new(XK_LIST); last = 0;
                if (!ad_accs("]"))
                    loop
                        item = ad_parse_or(); if (ad_perr != "") return 0; end
                        if (last == 0) ad_xa[e] = item; else ad_xnext[last] = item; end
                        last = item;
                        if (ad_accs(",")) continue; end
                        ad_needs("]", "to close the list"); break;
                    end
                end
                return e;
            elseif (w == "{")
                ad_ct++; e = ad_nx_new(XK_MAP); last = 0;
                if (!ad_accs("}"))
                    loop
                        if (ad_tk_t[ad_ct] != TK_WORD && ad_tk_t[ad_ct] != TK_STR) ad_perror("inside { } I expected a field name (like name: \"value\") but found " + ad_describe()); return 0; end
                        ent = ad_nx_new(XK_ENTRY); ad_xs[ent] = ad_tk_s[ad_ct]; ad_ct++;
                        ad_needs(":", "after the field name");
                        ad_xa[ent] = ad_parse_or(); if (ad_perr != "") return 0; end
                        if (last == 0) ad_xa[e] = ent; else ad_xnext[last] = ent; end
                        last = ent;
                        if (ad_accs(",")) continue; end
                        ad_needs("}", "to close the record"); break;
                    end
                end
                return e;
            end
            ad_perror("I did not expect " + ad_describe() + " here; a value (text, number, name...) should come first"); return 0;
        end
        case TK_WORD:
            w = ad_tk_s[ad_ct];
            if (w == "true") ad_ct++; e = ad_nx_new(XK_BOOL); ad_xn[e] = 1; return e; end
            if (w == "false") ad_ct++; e = ad_nx_new(XK_BOOL); return e; end
            if (w == "nothing") ad_ct++; return ad_nx_new(XK_NULL); end
            if (ad_is_reserved(w) && !(ad_tk_t[ad_ct + 1] == TK_SYM && ad_tk_s[ad_ct + 1] == "(")) ad_perror("I expected a value but found the word '" + w + "', which the language uses for something else"); return 0; end
            ad_ct++;
            if (ad_iss("("))
                ad_ct++; e = ad_nx_new(XK_CALL); ad_xs[e] = w; last = 0;
                if (!ad_accs(")"))
                    loop
                        item = ad_parse_or(); if (ad_perr != "") return 0; end
                        if (last == 0) ad_xa[e] = item; else ad_xnext[last] = item; end
                        last = item; ad_xop[e]++;
                        if (ad_accs(",")) continue; end
                        ad_needs(")", "to close the call"); break;
                    end
                end
                return e;
            end
            e = ad_nx_new(XK_VAR); ad_xs[e] = w; return e;
        end
    end
    ad_perror("I expected a value but found " + ad_describe());
    return 0;
end

function ad_parse_postfix()
private int e, f, ixn;
begin
    e = ad_parse_primary();
    while (ad_perr == "")
        if (ad_iss(".") && ad_tk_t[ad_ct + 1] == TK_WORD)
            ad_ct++; f = ad_nx_new(XK_FIELD); ad_xa[f] = e; ad_xs[f] = ad_tk_s[ad_ct]; ad_ct++; e = f;
        elseif (ad_iss("["))
            ad_ct++; ixn = ad_nx_new(XK_INDEX); ad_xa[ixn] = e; ad_xb[ixn] = ad_parse_or(); ad_needs("]", "to close the position"); e = ixn;
        else break; end
    end
    return e;
end

function ad_parse_unary()
private int e;
begin
    if (ad_iss("-")) ad_ct++; e = ad_nx_new(XK_NEG); ad_xa[e] = ad_parse_unary(); return e; end
    return ad_parse_postfix();
end

function ad_parse_mul()
private int l, e; string op;
begin
    l = ad_parse_unary();
    while (ad_perr == "" && (ad_iss("*") || ad_iss("/") || ad_iss("%")))
        op = ad_tk_s[ad_ct]; ad_ct++;
        e = ad_nx_new(XK_BIN); ad_xs[e] = op; ad_xa[e] = l; ad_xb[e] = ad_parse_unary(); l = e;
    end
    return l;
end

function ad_parse_add()
private int l, e; string op;
begin
    l = ad_parse_mul();
    while (ad_perr == "" && (ad_iss("+") || ad_iss("-")))
        op = ad_tk_s[ad_ct]; ad_ct++;
        e = ad_nx_new(XK_BIN); ad_xs[e] = op; ad_xa[e] = l; ad_xb[e] = ad_parse_mul(); l = e;
    end
    return l;
end

function ad_mk_cmp(int l, int op, int rhs)
private int e;
begin
    e = ad_nx_new(XK_CMP); ad_xop[e] = op; ad_xa[e] = l; ad_xb[e] = rhs; return e;
end

function ad_parse_cmp()
private int l, e, neg;
begin
    l = ad_parse_add();
    if (ad_perr != "") return 0; end
    if (ad_iss("==")) ad_ct++; return ad_mk_cmp(l, CM_EQ, ad_parse_add()); end
    if (ad_iss("!=")) ad_ct++; return ad_mk_cmp(l, CM_NE, ad_parse_add()); end
    if (ad_iss("<=")) ad_ct++; return ad_mk_cmp(l, CM_LE, ad_parse_add()); end
    if (ad_iss(">=")) ad_ct++; return ad_mk_cmp(l, CM_GE, ad_parse_add()); end
    if (ad_iss("<")) ad_ct++; return ad_mk_cmp(l, CM_LT, ad_parse_add()); end
    if (ad_iss(">")) ad_ct++; return ad_mk_cmp(l, CM_GT, ad_parse_add()); end
    if (ad_isw("contains")) ad_ct++; return ad_mk_cmp(l, CM_CONTAINS, ad_parse_add()); end
    if (ad_isw("starts") && ad_isw2("with")) ad_ct += 2; return ad_mk_cmp(l, CM_STARTS, ad_parse_add()); end
    if (ad_isw("ends") && ad_isw2("with")) ad_ct += 2; return ad_mk_cmp(l, CM_ENDS, ad_parse_add()); end
    if (ad_isw("is"))
        ad_ct++; neg = ad_accw("not");
        if (ad_accw("empty")) return ad_mk_cmp(l, neg ? CM_NOTEMPTY : CM_EMPTY, 0); end
        if (ad_accw("nothing")) return ad_mk_cmp(l, neg ? CM_NOTNOTHING : CM_NOTHING, 0); end
        if (ad_accw("greater")) ad_needw("than", "after 'greater'"); return ad_mk_cmp(l, neg ? CM_LE : CM_GT, ad_parse_add()); end
        if (ad_accw("less")) ad_needw("than", "after 'less'"); return ad_mk_cmp(l, neg ? CM_GE : CM_LT, ad_parse_add()); end
        if (ad_isw("at") && (ad_isw2("least") || ad_isw2("most")))
            ad_ct++;
            if (ad_isw("least")) ad_ct++; return ad_mk_cmp(l, neg ? CM_LT : CM_GE, ad_parse_add()); end
            ad_ct++; return ad_mk_cmp(l, neg ? CM_GT : CM_LE, ad_parse_add());
        end
        return ad_mk_cmp(l, neg ? CM_NE : CM_EQ, ad_parse_add());
    end
    return l;
end

function ad_parse_not()
private int e;
begin
    if (ad_isw("not")) ad_ct++; e = ad_nx_new(XK_NOT); ad_xa[e] = ad_parse_not(); return e; end
    return ad_parse_cmp();
end

function ad_parse_and()
private int l, e;
begin
    l = ad_parse_not();
    while (ad_perr == "" && ad_isw("and")) ad_ct++; e = ad_nx_new(XK_AND); ad_xa[e] = l; ad_xb[e] = ad_parse_not(); l = e; end
    return l;
end

function ad_parse_or()
private int l, e;
begin
    l = ad_parse_and();
    while (ad_perr == "" && ad_isw("or")) ad_ct++; e = ad_nx_new(XK_OR); ad_xa[e] = l; ad_xb[e] = ad_parse_and(); l = e; end
    return l;
end

// Carga las traducciones del addon para el idioma del reproductor (si no hay fichero, el addon se ve en su idioma original)
// en un fichero de traduccion \{ y \} son llaves que se escriben tal cual (igual que en los textos del addon)
function string ad_tr_braces(string t)
private string r; int i;
begin
    if (find(t, "\\") < 0) return t; end
    r = ""; i = 0;
    while (i < len(t))
        if (substr(t, i, 1) == "\\" && i + 1 < len(t) && substr(t, i + 1, 1) == "{") r += chr(1); i += 2;
        elseif (substr(t, i, 1) == "\\" && i + 1 < len(t) && substr(t, i + 1, 1) == "}") r += chr(2); i += 2;
        else r += substr(t, i, 1); i++; end
    end
    return r;
end

function ad_tr_load(string path)
private int fh, p, i; string dir, ln;
begin
    ad_tr_n = 0;
    if (lang_cur == "en") return 0; end
    dir = path; i = len(dir) - 1;
    while (i >= 0 && substr(dir, i, 1) != "/") i--; end
    if (i < 0) return 0; end
    dir = substr(dir, 0, i + 1);
    fh = fopen(dir + "lang/" + lang_cur + ".txt", O_READ);
    if (!fh) return 0; end
    while (!feof(fh) && ad_tr_n < 400)
        ln = fgets(fh);
        while (len(ln) > 0 && (substr(ln, len(ln) - 1, 1) == chr(10) || substr(ln, len(ln) - 1, 1) == chr(13))) ln = substr(ln, 0, len(ln) - 1); end
        p = find(ln, " => ");
        if (p > 0 && substr(ln, 0, 1) != "#")
            ad_tr_k[ad_tr_n] = ad_tr_braces(substr(ln, 0, p)); ad_tr_v[ad_tr_n] = ad_tr_braces(substr(ln, p + 4)); ad_tr_n++;
        end
    end
    fclose(fh);
    return ad_tr_n;
end

// el texto de un literal del addon, traducido si el addon trae su traduccion (las partes {expresion} se dejan tal cual)
function string ad_translate(string s)
private int i;
begin
    if (ad_tr_n == 0) return s; end
    for (i = 0; i < ad_tr_n; i++)
        if (ad_tr_k[i] == s) return ad_tr_v[i]; end
    end
    return s;
end

// "texto {expresion} más texto" -> nodo XK_STR con partes (XK_LIT o expresiones) encadenadas
function ad_parse_interp(string s)
private int e, last, part, i, n, depth, save_ct, lit_start, first_tok, ex; string lit, src;
begin
    s = ad_translate(s);
    e = ad_nx_new(XK_STR); last = 0;
    n = len(s); i = 0;
    while (i < n && ad_perr == "")
        lit = "";
        while (i < n && substr(s, i, 1) != "{")
            if (substr(s, i, 1) == chr(1)) lit += "{"; elseif (substr(s, i, 1) == chr(2)) lit += "}"; else lit += substr(s, i, 1); end
            i++;
        end
        if (lit != "")
            part = ad_nx_new(XK_LIT); ad_xs[part] = lit;
            if (last == 0) ad_xa[e] = part; else ad_xnext[last] = part; end
            last = part;
        end
        if (i < n && substr(s, i, 1) == "{")
            i++; depth = 1; lit_start = i;
            while (i < n && depth > 0)
                if (substr(s, i, 1) == "{") depth++; elseif (substr(s, i, 1) == "}") depth--; end
                if (depth > 0) i++; end
            end
            if (i >= n) ad_perror("a '{' inside the text was never closed with '}'"); return e; end
            src = substr(s, lit_start, i - lit_start); i++;
            save_ct = ad_ct;
            first_tok = ad_lex(src, ad_cur_lineno);
            ad_ct = first_tok;
            if (ad_tk_t[ad_ct] == TK_END) ad_perror("there is nothing between { } in the text"); end
            ex = ad_parse_or();
            if (ad_perr == "" && ad_tk_t[ad_ct] != TK_END) ad_perror("inside { } in a text I did not expect " + ad_describe()); end
            ad_ct = save_ct;
            if (last == 0) ad_xa[e] = ex; else ad_xnext[last] = ex; end
            last = ex;
        end
    end
    return e;
end

// ---- sentencias
function ad_new_stmt(int kind)
private int k;
begin
    if (ad_ns >= AD_CAPS - 1) ad_perror("this addon is too big (too many statements)"); return 0; end
    ad_sk[ad_ns] = kind; ad_sl[ad_ns] = ad_cur_lineno; ad_smode[ad_ns] = 0; ad_sflag[ad_ns] = 0; ad_sname[ad_ns] = "";
    ad_sargs[ad_ns] = 0; ad_shdrs[ad_ns] = 0; ad_sbody[ad_ns] = 0; ad_selse[ad_ns] = 0; ad_snext[ad_ns] = 0;
    for (k = 0; k < 8; k++) ad_se[ad_ns * 8 + k] = 0; end
    ad_ns++;
    return ad_ns - 1;
end

function ad_new_arg()
begin
    if (ad_nar >= AD_CAPA - 1) ad_perror("this addon is too big (too many values passed around)"); return 0; end
    ad_ar_ne[ad_nar] = 0; ad_ar_e[ad_nar] = 0; ad_ar_name[ad_nar] = ""; ad_ar_next[ad_nar] = 0;
    ad_nar++;
    return ad_nar - 1;
end

// cláusulas "with header NOMBRE is VALOR / with body X / with method M" de fetch
function ad_parse_fetch_with(int s)
private int a, last;
begin
    last = 0;
    while (ad_perr == "" && ad_isw("with"))
        ad_ct++;
        if (ad_accw("header"))
            a = ad_new_arg(); ad_ar_ne[a] = ad_parse_add(); ad_needw("is", "between the header name and its value"); ad_ar_e[a] = ad_parse_or();
            if (ad_shdrs[s] == 0) ad_shdrs[s] = a; else ad_ar_next[last] = a; end
            last = a;
        elseif (ad_accw("body")) ad_se[s * 8 + 1] = ad_parse_or();
        elseif (ad_accw("method")) ad_se[s * 8 + 2] = ad_parse_or();
        else ad_perror("after 'with' I expected 'header', 'body' or 'method' but found " + ad_describe()); end
    end
end

function ad_parse_statement()
private int s, nm, a, last, lastarg, lastname, lasthdr; string w, nmtxt;
begin
    if (ad_perr != "") return 0; end
    ad_cur_lineno = ad_ln_no[ad_cl];
    if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("a line should start with a command (set, if, for each, fetch, show...) but it starts with " + ad_describe()); return 0; end
    w = ad_tk_s[ad_ct];
    if (w == "set")
        ad_ct++; s = ad_new_stmt(SK_SET);
        if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("after 'set' I expected a name but found " + ad_describe()); return 0; end
        if (ad_is_reserved(ad_tk_s[ad_ct])) ad_perror("'" + ad_tk_s[ad_ct] + "' is a word the language uses, so it cannot be a name; please choose another"); return 0; end
        ad_se[s * 8] = ad_parse_postfix();
        ad_needw("to", "in 'set NAME to VALUE'"); ad_se[s * 8 + 1] = ad_parse_or(); ad_need_end();
    elseif (w == "add")
        ad_ct++; s = ad_new_stmt(SK_ADD); ad_se[s * 8] = ad_parse_or(); ad_needw("to", "in 'add VALUE to LIST'"); ad_se[s * 8 + 1] = ad_parse_postfix(); ad_need_end();
    elseif (w == "clear")
        ad_ct++;
        if (ad_isw("message")) ad_ct++; s = ad_new_stmt(SK_MESSAGE); ad_need_end(); return s; end
        s = ad_new_stmt(SK_CLEAR); ad_se[s * 8] = ad_parse_postfix(); ad_need_end();
    elseif (w == "if")
        ad_ct++; s = ad_new_stmt(SK_IF); ad_se[s * 8] = ad_parse_or(); ad_needs(":", "at the end of the 'if' line"); ad_need_end();
    elseif (w == "for")
        ad_ct++; ad_needw("each", "after 'for'"); s = ad_new_stmt(SK_FOR); ad_sname[s] = ad_need_name("a name for each item");
        ad_needw("in", "after the name"); ad_se[s * 8] = ad_parse_or();
        if (ad_accw("limit")) ad_se[s * 8 + 1] = ad_parse_or(); end
        ad_needs(":", "at the end of the 'for each' line"); ad_need_end();
    elseif (w == "while")
        ad_ct++; s = ad_new_stmt(SK_WHILE); ad_se[s * 8] = ad_parse_or(); ad_needs(":", "at the end of the 'while' line"); ad_need_end();
    elseif (w == "repeat")
        ad_ct++; s = ad_new_stmt(SK_REPEAT); ad_se[s * 8] = ad_parse_or(); ad_needw("times", "after the number"); ad_needs(":", "at the end of the 'repeat' line"); ad_need_end();
    elseif (w == "go")
        ad_ct++; ad_needw("to", "after 'go'"); s = ad_new_stmt(SK_GOTO); ad_sname[s] = ad_need_name("the name of a page");
        lastarg = 0;
        while (ad_perr == "" && ad_isw("with"))
            ad_ct++; a = ad_new_arg(); ad_ar_name[a] = ad_need_name("the name of a value to pass to the page"); ad_needw("is", "after the name"); ad_ar_e[a] = ad_parse_or();
            if (ad_sargs[s] == 0) ad_sargs[s] = a; else ad_ar_next[lastarg] = a; end
            lastarg = a;
        end
        ad_need_end();
    elseif (w == "stop") ad_ct++; s = ad_new_stmt(SK_STOP); ad_need_end();
    elseif (w == "skip") ad_ct++; s = ad_new_stmt(SK_SKIP); ad_need_end();
    elseif (w == "exit") ad_ct++; ad_needw("loop", "after 'exit'"); s = ad_new_stmt(SK_EXIT); ad_need_end();
    elseif (w == "fetch")
        ad_ct++; s = ad_new_stmt(SK_FETCH);
        if (ad_accw("json")) ad_smode[s] = 0; elseif (ad_accw("text")) ad_smode[s] = 2;
        else ad_perror("after 'fetch' I expected json or text but found " + ad_describe()); return 0; end
        ad_needw("from", "after the kind of data"); ad_se[s * 8] = ad_parse_or();
        ad_sname[s] = "result";
        while (ad_perr == "")
            if (ad_accw("into")) ad_sname[s] = ad_need_name("a name for the result");
            elseif (ad_isw("with")) ad_parse_fetch_with(s);
            else break; end
        end
        ad_need_end();
    elseif (w == "try")
        ad_ct++; s = ad_new_stmt(SK_TRY); ad_needs(":", "after 'try'"); ad_need_end();
    elseif (w == "fail") ad_ct++; s = ad_new_stmt(SK_FAIL); ad_se[s * 8] = ad_parse_or(); ad_need_end();
    elseif (w == "show")
        ad_ct++; s = ad_new_stmt(SK_SHOW);
        if (ad_accw("folder")) ad_smode[s] = 0; elseif (ad_accw("video")) ad_smode[s] = 1; elseif (ad_accw("audio")) ad_smode[s] = 2; elseif (ad_accw("radio")) ad_smode[s] = 3;
        elseif (ad_accw("button")) ad_smode[s] = 4; elseif (ad_accw("check")) ad_smode[s] = 5; elseif (ad_accw("choice")) ad_smode[s] = 6; elseif (ad_accw("input")) ad_smode[s] = 7; elseif (ad_accw("header")) ad_smode[s] = 8;
        else ad_perror("after 'show' I expected folder, video, audio, radio, button, check, choice, input or header but found " + ad_describe()); return 0; end
        ad_se[s * 8] = ad_parse_or();
        lastarg = 0; lasthdr = 0;
        while (ad_perr == "")
            if (ad_accw("opening")) ad_sname[s] = ad_need_name("the name of a page");
            elseif (ad_accw("doing")) ad_sname[s] = ad_need_name("the name of a page");
            elseif (ad_accw("bound")) ad_sname[s] = ad_need_name("the name of a setting");
            elseif (ad_accw("playing")) ad_se[s * 8 + 1] = ad_parse_or();
            elseif (ad_accw("logo")) ad_se[s * 8 + 2] = ad_parse_or();
            elseif (ad_accw("info")) ad_se[s * 8 + 3] = ad_parse_or();
            elseif (ad_accw("year")) ad_se[s * 8 + 4] = ad_parse_or();
            elseif (ad_accw("duration")) ad_se[s * 8 + 5] = ad_parse_or();
            elseif (ad_accw("subtitles")) ad_se[s * 8 + 6] = ad_parse_or();
            elseif (ad_isw("with"))
                ad_ct++;
                if (ad_accw("header"))
                    a = ad_new_arg(); ad_ar_ne[a] = ad_parse_add(); ad_needw("is", "between the header name and its value"); ad_ar_e[a] = ad_parse_or();
                    if (ad_shdrs[s] == 0) ad_shdrs[s] = a; else ad_ar_next[lasthdr] = a; end
                    lasthdr = a;
                    continue;
                end
                a = ad_new_arg(); ad_ar_name[a] = ad_need_name("the name of a value to pass to the page"); ad_needw("is", "after the name"); ad_ar_e[a] = ad_parse_or();
                if (ad_sargs[s] == 0) ad_sargs[s] = a; else ad_ar_next[lastarg] = a; end
                lastarg = a;
            else break; end
        end
        ad_need_end();
        if (ad_perr == "" && ad_smode[s] == 0 && ad_sname[s] == "") ad_perror("a folder needs 'opening PAGE' to say which page it opens"); end
        if (ad_perr == "" && ad_smode[s] >= 1 && ad_smode[s] <= 3 && ad_se[s * 8 + 1] == 0) ad_perror("this item needs 'playing ADDRESS' to say what to play"); end
        if (ad_perr == "" && ad_smode[s] == 4 && ad_sname[s] == "") ad_perror("a button needs 'doing PAGE' to say which page it runs"); end
        if (ad_perr == "" && ad_smode[s] >= 5 && ad_smode[s] <= 7 && ad_sname[s] == "") ad_perror("this item needs 'bound NAME' with the name of the setting it changes"); end
    elseif (w == "ask")
        ad_ct++; s = ad_new_stmt(SK_ASK); ad_se[s * 8] = ad_parse_or(); ad_needw("into", "after the question"); ad_sname[s] = ad_need_name("a name for the answer");
        while (ad_perr == "")
            if (ad_accw("default")) ad_se[s * 8 + 1] = ad_parse_or(); elseif (ad_accw("secret")) ad_sflag[s] = 1; else break; end
        end
        ad_need_end();
    elseif (w == "message") ad_ct++; s = ad_new_stmt(SK_MESSAGE); ad_se[s * 8] = ad_parse_or(); ad_need_end();
    elseif (w == "wait") ad_ct++; s = ad_new_stmt(SK_WAIT); ad_se[s * 8] = ad_parse_or(); ad_accw("seconds"); ad_need_end();
    elseif (w == "save")
        ad_ct++; s = ad_new_stmt(SK_SAVE);
        if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("after 'save' I expected the name of a setting but found " + ad_describe()); return 0; end
        ad_sname[s] = ad_tk_s[ad_ct]; ad_ct++; ad_needw("as", "in 'save NAME as VALUE'"); ad_se[s * 8] = ad_parse_or(); ad_need_end();
    elseif (w == "log") ad_ct++; s = ad_new_stmt(SK_LOG); ad_se[s * 8] = ad_parse_or(); ad_need_end();
    elseif (w == "give") ad_ct++; ad_needw("back", "after 'give'"); s = ad_new_stmt(SK_GIVE); ad_se[s * 8] = ad_parse_or(); ad_need_end();
    elseif (w == "otherwise" || w == "on")
        ad_perror("'" + w + "' must come right after an 'if' / 'try' block, at the same indentation"); return 0;
    else
        s = ad_new_stmt(SK_CALL); ad_se[s * 8] = ad_parse_or();
        if (ad_perr == "" && ad_xk[ad_se[s * 8]] != XK_CALL) ad_perror("I do not know the command '" + w + "'. Commands are: set, add, if, for each, while, repeat, fetch, try, show, go to, ask, message, wait, save, log, fail, stop"); end
        ad_need_end();
    end
    return s;
end

function ad_line_word(int lni, string w)
begin
    return ad_tk_t[ad_ln_t0[lni]] == TK_WORD && ad_tk_s[ad_ln_t0[lni]] == w;
end

function ad_parse_block(int indent)
private int first, last, bi, s, k, cur, alt, ol;
begin
    first = 0; last = 0; bi = -1;
    while (ad_perr == "" && ad_cl < ad_nln)
        if (ad_ln_ind[ad_cl] < indent) break; end
        if (bi < 0) bi = ad_ln_ind[ad_cl]; end
        ad_cur_lineno = ad_ln_no[ad_cl];
        if (ad_ln_ind[ad_cl] > bi) ad_perror("this line is indented more than the lines before it, but nothing opened a block (a line ending with ':')"); return 0; end
        if (ad_ln_ind[ad_cl] < bi) ad_perror("the indentation of this line does not match any block above"); return 0; end
        ad_ct = ad_ln_t0[ad_cl];
        k = ad_cl; ad_cl++;
        s = ad_parse_statement();
        if (ad_perr != "") return 0; end
        if (ad_sk[s] == SK_IF || ad_sk[s] == SK_FOR || ad_sk[s] == SK_WHILE || ad_sk[s] == SK_REPEAT || ad_sk[s] == SK_TRY)
            if (ad_cl >= ad_nln || ad_ln_ind[ad_cl] <= bi) ad_cur_lineno = ad_ln_no[k]; ad_perror("this line opens a block with ':' but the next line is not indented"); return 0; end
            ad_sbody[s] = ad_parse_block(bi + 1);
            if (ad_sk[s] == SK_IF)
                cur = s;
                while (ad_perr == "" && ad_cl < ad_nln && ad_ln_ind[ad_cl] == bi && ad_line_word(ad_cl, "otherwise"))
                    ol = ad_cl; ad_ct = ad_ln_t0[ol] + 1; ad_cl++; ad_cur_lineno = ad_ln_no[ol];
                    alt = ad_new_stmt(SK_IF);
                    if (ad_accw("if")) ad_se[alt * 8] = ad_parse_or(); end
                    ad_needs(":", "at the end of the 'otherwise' line"); ad_need_end();
                    if (ad_perr != "") return 0; end
                    if (ad_cl >= ad_nln || ad_ln_ind[ad_cl] <= bi) ad_perror("this 'otherwise' opens a block but the next line is not indented"); return 0; end
                    ad_sbody[alt] = ad_parse_block(bi + 1);
                    ad_selse[cur] = alt; cur = alt;
                    if (ad_se[alt * 8] == 0) break; end
                end
            elseif (ad_sk[s] == SK_TRY)
                if (ad_cl < ad_nln && ad_ln_ind[ad_cl] == bi && ad_line_word(ad_cl, "on"))
                    ol = ad_cl; ad_ct = ad_ln_t0[ol] + 1; ad_cl++; ad_cur_lineno = ad_ln_no[ol];
                    ad_needw("error", "after 'on'"); ad_needs(":", "at the end of the 'on error' line"); ad_need_end();
                    if (ad_perr != "") return 0; end
                    if (ad_cl >= ad_nln || ad_ln_ind[ad_cl] <= bi) ad_perror("'on error' opens a block but the next line is not indented"); return 0; end
                    ad_selse[s] = ad_parse_block(bi + 1);
                else
                    ad_cur_lineno = ad_ln_no[k]; ad_perror("a 'try' block must be followed by 'on error:' at the same indentation"); return 0;
                end
            end
        elseif (ad_cl < ad_nln && ad_ln_ind[ad_cl] > bi)
            ad_cur_lineno = ad_ln_no[ad_cl]; ad_perror("this line is indented more than the line before it, but that line does not end with ':'"); return 0;
        end
        if (first == 0) first = s; else ad_snext[last] = s; end
        last = s;
    end
    return first;
end

// ---- programa completo
function ad_parse_program(string path)
private int fh, lineno, indent, i, c, ft, nm, pg, k, lni, first, t0i, hascode; string raw, txt, kind, vbuf, sname;
begin
    ad_reset_program();
    ad_src_file = "main.addon";
    fh = fopen(path, O_READ);
    if (!fh) ad_perr = "I could not open " + path; return 0; end
    lineno = 0;
    while (!feof(fh) && ad_perr == "")
        raw = fgets(fh); lineno++;
        if (lineno == 1 && len(raw) >= 3 && asc(substr(raw, 0, 1)) == 239) raw = substr(raw, 3); end        // BOM
        indent = 0; i = 0;
        while (i < len(raw) && (substr(raw, i, 1) == " " || substr(raw, i, 1) == chr(9))) indent += (substr(raw, i, 1) == chr(9)) ? 4 : 1; i++; end
        txt = substr(raw, i);
        first = ad_lex(txt, lineno);
        if (ad_perr != "") break; end
        if (ad_tk_t[first] == TK_END) ad_ntk--; continue; end              // línea vacía o comentario: descartada
        if (ad_nln >= AD_MAXLN) ad_perror("this addon has too many lines"); break; end
        ad_ln_ind[ad_nln] = indent; ad_ln_no[ad_nln] = lineno; ad_ln_t0[ad_nln] = first; ad_nln++;
    end
    fclose(fh);
    if (ad_perr != "") return 0; end

    ad_cl = 0;
    while (ad_perr == "" && ad_cl < ad_nln)
        lni = ad_cl; ad_cur_lineno = ad_ln_no[lni]; ad_ct = ad_ln_t0[lni];
        if (ad_ln_ind[lni] != 0) ad_perror("this line is indented but nothing above opened a block"); break; end
        ad_cl++;
        if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("at the top of the file I expected addon, id, version, author, description, setting, page or define but found " + ad_describe()); break; end
        kind = ad_tk_s[ad_ct];
        if (kind == "addon" || kind == "description" || kind == "author")
            ad_ct++;
            if (ad_tk_t[ad_ct] != TK_STR) ad_perror("after '" + kind + "' I expected a piece of text in quotes"); break; end
            txt = ad_tk_s[ad_ct]; ad_ct++; ad_need_end();
            if (kind == "addon") ad_i_name = txt; elseif (kind == "author") ad_i_author = txt; else ad_i_desc = txt; end
        elseif (kind == "id" || kind == "version")
            ad_ct++; vbuf = ""; hascode = 0;
            while (ad_tk_t[ad_ct] != TK_END) vbuf += ad_tk_s[ad_ct]; ad_ct++; hascode = 1; end
            if (!hascode) ad_perror("after '" + kind + "' I expected a value (for example: " + kind + (kind == "id" ? " my-addon" : " 1.0") + ")"); break; end
            if (kind == "id") ad_i_id = vbuf; else ad_i_ver = vbuf; end
        elseif (kind == "setting")
            ad_ct++;
            if (ad_nst >= 24) ad_perror("an addon can have at most 24 settings"); break; end
            k = ad_nst; ad_nst++;
            if (ad_tk_t[ad_ct] != TK_WORD) ad_perror("after 'setting' I expected the name of the setting"); break; end
            ad_st_name[k] = ad_tk_s[ad_ct]; ad_st_label[k] = ad_tk_s[ad_ct]; ad_st_def[k] = ""; ad_st_choices[k] = ""; ad_st_hidden[k] = 0; ad_ct++;
            ad_needw("is", "after the setting name");
            if (ad_accw("secret")) ad_needw("text", "after 'secret'"); ad_st_type[k] = "secret";
            elseif (ad_accw("text")) ad_st_type[k] = "text";
            elseif (ad_accw("number")) ad_st_type[k] = "number";
            elseif (ad_accw("yes")) ad_needw("or", "in 'yes or no'"); ad_needw("no", "in 'yes or no'"); ad_st_type[k] = "yesno";
            elseif (ad_accw("choice")) ad_st_type[k] = "choice";
            else ad_perror("the type of a setting must be: text, secret text, number, yes or no, or choice (found " + ad_describe() + ")"); break; end
            while (ad_perr == "" && ad_accs(","))
                if (ad_accw("label"))
                    if (ad_tk_t[ad_ct] != TK_STR) ad_perror("after 'label' I expected a piece of text"); break; end
                    ad_st_label[k] = ad_tk_s[ad_ct]; ad_ct++;
                elseif (ad_accw("default"))
                    if (ad_tk_t[ad_ct] == TK_END || ad_tk_t[ad_ct] == TK_SYM) ad_perror("after 'default' I expected a value"); break; end
                    ad_st_def[k] = ad_tk_s[ad_ct]; ad_ct++;
                elseif (ad_accw("choices"))
                    loop
                        if (ad_tk_t[ad_ct] != TK_STR) ad_perror("after 'choices' I expected pieces of text in quotes"); break; end
                        if (ad_st_choices[k] != "") ad_st_choices[k] += "|"; end
                        ad_st_choices[k] += ad_tk_s[ad_ct]; ad_ct++;
                        if (ad_iss(",") && ad_tk_t[ad_ct + 1] == TK_STR) ad_ct++; continue; end
                        break;
                    end
                elseif (ad_accw("hidden")) ad_st_hidden[k] = 1;
                else ad_perror("after the comma I expected label, default, choices or hidden"); end
            end
            ad_need_end();
            if (ad_perr == "" && ad_st_type[k] == "choice" && ad_st_choices[k] == "") ad_perror("a 'choice' setting needs 'choices \"a\", \"b\"...'"); end
        elseif (kind == "page" || kind == "define")
            ad_ct++;
            if (ad_npg >= AD_CAPPG) ad_perror("too many pages and functions"); break; end
            pg = ad_npg; ad_npg++;
            ad_pg_func[pg] = (kind == "define"); ad_pg_np[pg] = 0; ad_pg_body[pg] = 0;
            ad_pg_name[pg] = ad_need_name(kind == "define" ? "a name for the function" : "a name for the page");
            if (ad_perr != "") break; end
            if (kind == "define")
                ad_needs("(", "after the function name");
                if (!ad_accs(")"))
                    loop
                        if (ad_pg_np[pg] >= 12) ad_perror("at most 12 parameters"); break; end
                        ad_pg_par[pg * 12 + ad_pg_np[pg]] = ad_need_name("a parameter name"); ad_pg_np[pg]++;
                        if (ad_perr != "") break; end
                        if (ad_accs(",")) continue; end
                        ad_needs(")", "after the parameters"); break;
                    end
                end
            elseif (ad_accw("with"))
                loop
                    if (ad_pg_np[pg] >= 12) ad_perror("at most 12 parameters"); break; end
                    ad_pg_par[pg * 12 + ad_pg_np[pg]] = ad_need_name("a parameter name"); ad_pg_np[pg]++;
                    if (ad_perr != "") break; end
                    if (ad_accs(",")) continue; end
                    break;
                end
            end
            ad_needs(":", kind == "define" ? "at the end of the 'define' line" : "at the end of the 'page' line"); ad_need_end();
            for (k = 0; k < pg; k++) if (ad_pg_name[k] == ad_pg_name[pg]) ad_perror("there is already a page or function called '" + ad_pg_name[pg] + "'"); end end
            if (ad_perr != "") break; end
            if (ad_cl >= ad_nln || ad_ln_ind[ad_cl] <= 0) ad_perror("this " + (kind == "define" ? "function" : "page") + " has no lines inside it (indent them below)"); break; end
            ad_pg_body[pg] = ad_parse_block(1);
        else
            ad_perror("I do not know '" + kind + "' at the top of the file (expected addon, id, version, author, description, setting, page or define)");
        end
    end
    if (ad_perr != "") return 0; end
    ad_cur_lineno = 1;
    if (ad_i_name == "") ad_perr = "main.addon: the addon needs a name: add a line   addon \"My addon\""; return 0; end
    if (ad_i_id == "") ad_perr = "main.addon: the addon needs an id: add a line   id my-addon"; return 0; end
    if (ad_i_ver == "") ad_i_ver = "1.0"; end
    hascode = 0;
    for (k = 0; k < ad_npg; k++) if (ad_pg_name[k] == "home" && !ad_pg_func[k]) hascode = 1; end end
    if (!hascode) ad_perr = "main.addon: the addon needs a page called home (the first page the player opens)"; return 0; end
    return 1;
end

// solo la cabecera (nombre, descripción...) para la lista de addons: no analiza las páginas
function ad_peek_info(string path)
private int fh, i, first; string raw, txt, kind;
begin
    ad_reset_program();
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    while (!feof(fh))
        raw = fgets(fh);
        if (len(raw) >= 3 && asc(substr(raw, 0, 1)) == 239) raw = substr(raw, 3); end
        if (len(raw) > 0 && substr(raw, 0, 1) != " " && substr(raw, 0, 1) != chr(9) && substr(raw, 0, 1) != "#")
            if (substr(raw, 0, 5) == "page " || substr(raw, 0, 7) == "define ") break; end
            ad_ntk = 0;
            first = ad_lex(raw, 1);
            ad_ct = first;
            if (ad_perr != "") ad_perr = ""; continue; end
            if (ad_tk_t[ad_ct] == TK_WORD)
                kind = ad_tk_s[ad_ct]; ad_ct++;
                if ((kind == "addon" || kind == "description" || kind == "author") && ad_tk_t[ad_ct] == TK_STR)
                    if (kind == "addon") ad_i_name = ad_tk_s[ad_ct]; elseif (kind == "author") ad_i_author = ad_tk_s[ad_ct]; else ad_i_desc = ad_tk_s[ad_ct]; end
                elseif (kind == "id" || kind == "version")
                    txt = "";
                    while (ad_tk_t[ad_ct] != TK_END) txt += ad_tk_s[ad_ct]; ad_ct++; end
                    if (kind == "id") ad_i_id = txt; else ad_i_ver = txt; end
                end
            end
        end
    end
    fclose(fh);
    ad_ntk = 0;
    return ad_i_name != "";
end

// ==========================================================================================================
//  El intérprete
// ==========================================================================================================
const AD_MAXIT = 3000; AD_MAXSC = 3000;

global
    // ámbito de variables (pila)
    string ad_sc_name[AD_MAXSC]; int ad_sc_val[AD_MAXSC]; int ad_sc_top, ad_sc_base;
    int    ad_give, ad_depth; long ad_steps;
    int    ad_lv0[48]; int ad_lv1[48];
    // lo que muestra la página en curso
    int    ad_nit;
    int    ad_it_flag[AD_MAXIT];
    int    ad_it_kind[AD_MAXIT]; string ad_it_title[AD_MAXIT]; string ad_it_page[AD_MAXIT]; string ad_it_args[AD_MAXIT]; string ad_it_url[AD_MAXIT];
    string ad_it_logo[AD_MAXIT]; string ad_it_info[AD_MAXIT]; int ad_it_year[AD_MAXIT]; int ad_it_dur[AD_MAXIT]; string ad_it_sub[AD_MAXIT]; string ad_it_hdr[AD_MAXIT];
    int    host_cancelled;          // lo pone host_ask: 1 si el usuario cancela
    int    ad_loaded;               // hay un addon cargado y sin errores
    string ad_loaded_path = "";
end

// hooks que define quien incluye este archivo
declare function string host_ask(string prompt, string def, int secret) end
declare function string host_setting_get(string name) end

function ad_rt_error(int ln_no, string msg)
begin
    if (ad_err == "") ad_err = ad_src_file + " line " + ln_no + ": " + msg; end
    return 0;
end

function ad_lev(string a, string b)
private int la, lb, i, j, cost, m, t;
begin
    la = len(a); lb = len(b);
    if (la > 40 || lb > 40) return 99; end
    for (j = 0; j <= lb; j++) ad_lv0[j] = j; end
    for (i = 1; i <= la; i++)
        ad_lv1[0] = i;
        for (j = 1; j <= lb; j++)
            cost = (lcase(substr(a, i - 1, 1)) == lcase(substr(b, j - 1, 1))) ? 0 : 1;
            m = ad_lv0[j] + 1;
            t = ad_lv1[j - 1] + 1; if (t < m) m = t; end
            t = ad_lv0[j - 1] + cost; if (t < m) m = t; end
            ad_lv1[j] = m;
        end
        for (j = 0; j <= lb; j++) ad_lv0[j] = ad_lv1[j]; end
    end
    return ad_lv0[lb];
end

function ad_sc_get(string name)
private int i;
begin
    for (i = ad_sc_top - 1; i >= ad_sc_base; i--)
        if (ad_sc_name[i] == name) return ad_sc_val[i]; end
    end
    return -1;
end

function ad_sc_set(string name, int v)
private int i;
begin
    for (i = ad_sc_top - 1; i >= ad_sc_base; i--)
        if (ad_sc_name[i] == name) ad_sc_val[i] = v; return 1; end
    end
    if (ad_sc_top >= AD_MAXSC) ad_fail("too many variables"); return 0; end
    ad_sc_name[ad_sc_top] = name; ad_sc_val[ad_sc_top] = v; ad_sc_top++;
    return 1;
end

function ad_find_setting(string name)
private int i;
begin
    for (i = 0; i < ad_nst; i++) if (ad_st_name[i] == name) return i; end end
    return -1;
end

function ad_setting_value(int k)
private string s;
begin
    s = host_setting_get(ad_st_name[k]);
    if (s == chr(1)) s = ad_st_def[k]; end
    if (ad_st_type[k] == "number") return ad_num(atof(s)); end
    if (ad_st_type[k] == "yesno") return ad_bool(s == "yes" || s == "true" || s == "1"); end
    return ad_str(s);
end

function ad_to_num(int v, int ln_no, string what)
begin
    switch (ad_vt[v])
        case VT_NUM, VT_BOOL: return ad_vn[v]; end
        case VT_NULL: return 0; end
        case VT_STR:
            if (len(ad_vs[v]) > 0 && (ad_is_digit(asc(substr(ad_vs[v], 0, 1))) || substr(ad_vs[v], 0, 1) == "-" || substr(ad_vs[v], 0, 1) == ".")) return atof(ad_vs[v]); end
        end
    end
    ad_rt_error(ln_no, what + " needs a number but got " + ad_type_name(v));
    return 0;
end

function ad_cmp_values(int a, int b, int ln_no)
private double dxv, dyv;
begin
    if (ad_vt[a] == VT_STR && ad_vt[b] == VT_STR)
        if (ad_vs[a] < ad_vs[b]) return -1; end
        if (ad_vs[a] > ad_vs[b]) return 1; end
        return 0;
    end
    dxv = ad_to_num(a, ln_no, "this comparison"); dyv = ad_to_num(b, ln_no, "this comparison");
    if (dxv < dyv) return -1; end
    if (dxv > dyv) return 1; end
    return 0;
end

function ad_utf8_len(string s)
private int i, n, c;
begin
    n = 0;
    for (i = 0; i < len(s); i++) c = asc(substr(s, i, 1)); if ((c & 192) != 128) n++; end end
    return n;
end

declare function int ad_call_user(int pg, int argc, int a0, int a1, int a2, int a3, int a4, int a5, int ln_no) end
declare function int ad_call_builtin(int e) end

function ad_eval(int e)
private int a, b, r, i, c, n, pg, argc, v, ln_no, found, bi; string s, t, best; double dx, dy; int ar0, ar1, ar2, ar3, ar4, ar5, part;
begin
    if (ad_err != "") return 0; end
    ln_no = ad_xl[e];
    ad_steps++;
    if (ad_steps > 4000000) ad_rt_error(ln_no, "the addon ran for too long (is there a loop that never ends?)"); return 0; end
    switch (ad_xk[e])
        case XK_NUM: return ad_num(ad_xn[e]); end
        case XK_BOOL: return ad_xn[e] != 0 ? 1 : 2; end
        case XK_NULL: return 0; end
        case XK_LIT: return ad_str(ad_xs[e]); end
        case XK_STR:
            part = ad_xa[e];
            if (part != 0 && ad_xnext[part] == 0 && ad_xk[part] == XK_LIT) return ad_str(ad_xs[part]); end
            s = "";
            while (part != 0)
                if (ad_xk[part] == XK_LIT) s += ad_xs[part]; else v = ad_eval(part); if (ad_err != "") return 0; end s += ad_text(v); end
                part = ad_xnext[part];
            end
            return ad_str(s);
        end
        case XK_VAR:
            v = ad_sc_get(ad_xs[e]);
            if (v >= 0) return v; end
            i = ad_find_setting(ad_xs[e]);
            if (i >= 0) return ad_setting_value(i); end
            if (ad_xs[e] == "error") return ad_str(""); end
            best = ""; bi = 3;
            for (i = ad_sc_base; i < ad_sc_top; i++) c = ad_lev(ad_xs[e], ad_sc_name[i]); if (c < bi) bi = c; best = ad_sc_name[i]; end end
            for (i = 0; i < ad_nst; i++) c = ad_lev(ad_xs[e], ad_st_name[i]); if (c < bi) bi = c; best = ad_st_name[i]; end end
            if (best != "") ad_rt_error(ln_no, "'" + ad_xs[e] + "' has no value yet (did you mean '" + best + "'?)"); return 0; end
            ad_rt_error(ln_no, "'" + ad_xs[e] + "' has no value yet: set it first with  set " + ad_xs[e] + " to ...");
            return 0;
        end
        case XK_FIELD:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            if (ad_vt[a] == VT_NULL) ad_rt_error(ln_no, "cannot read '" + ad_xs[e] + "' because the value before the dot is nothing (it may be missing in the data)"); return 0; end
            if (ad_vt[a] != VT_MAP) ad_rt_error(ln_no, "cannot read '" + ad_xs[e] + "' of " + ad_type_name(a) + ": only records have fields"); return 0; end
            v = ad_map_get(a, ad_xs[e]);
            if (v < 0) return 0; end
            return v;
        end
        case XK_INDEX:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            b = ad_eval(ad_xb[e]); if (ad_err != "") return 0; end
            if (ad_vt[a] == VT_LIST)
                i = (int)ad_to_num(b, ln_no, "a list position");
                if (i < 1 || i > ad_vc[a]) return 0; end
                return ad_pi[ad_vp[a] + i - 1];
            elseif (ad_vt[a] == VT_MAP)
                v = ad_map_get(a, ad_text(b)); if (v < 0) return 0; end return v;
            elseif (ad_vt[a] == VT_STR)
                i = (int)ad_to_num(b, ln_no, "a text position");
                if (i < 1 || i > len(ad_vs[a])) return 0; end
                return ad_str(substr(ad_vs[a], i - 1, 1));
            elseif (ad_vt[a] == VT_NULL)
                ad_rt_error(ln_no, "cannot take an item from nothing (the list or record is missing)"); return 0;
            end
            ad_rt_error(ln_no, "cannot use [ ] on " + ad_type_name(a)); return 0;
        end
        case XK_BIN:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            b = ad_eval(ad_xb[e]); if (ad_err != "") return 0; end
            s = ad_xs[e];
            if (s == "+")
                if (ad_vt[a] == VT_LIST && ad_vt[b] == VT_LIST)
                    r = ad_list();
                    for (i = 0; i < ad_vc[a]; i++) ad_list_add(r, ad_pi[ad_vp[a] + i]); end
                    for (i = 0; i < ad_vc[b]; i++) ad_list_add(r, ad_pi[ad_vp[b] + i]); end
                    return r;
                end
                if (ad_vt[a] == VT_STR || ad_vt[b] == VT_STR) return ad_str(ad_text(a) + ad_text(b)); end
                dx = ad_to_num(a, ln_no, "+"); dy = ad_to_num(b, ln_no, "+");
                return ad_num(dx + dy);
            end
            dx = ad_to_num(a, ln_no, "this calculation"); dy = ad_to_num(b, ln_no, "this calculation");
            if (ad_err != "") return 0; end
            if (s == "-") return ad_num(dx - dy); end
            if (s == "*") return ad_num(dx * dy); end
            if (dy == 0) ad_rt_error(ln_no, "cannot divide by zero"); return 0; end
            if (s == "/") return ad_num(dx / dy); end
            return ad_num(dx - dy * (int)(dx / dy));
        end
        case XK_NEG: a = ad_eval(ad_xa[e]); return ad_num(-ad_to_num(a, ln_no, "the minus sign")); end
        case XK_NOT: a = ad_eval(ad_xa[e]); return ad_truthy(a) ? 2 : 1; end
        case XK_AND:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            if (!ad_truthy(a)) return 2; end
            b = ad_eval(ad_xb[e]); return ad_truthy(b) ? 1 : 2;
        end
        case XK_OR:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            if (ad_truthy(a)) return 1; end
            b = ad_eval(ad_xb[e]); return ad_truthy(b) ? 1 : 2;
        end
        case XK_CMP:
            a = ad_eval(ad_xa[e]); if (ad_err != "") return 0; end
            c = ad_xop[e];
            if (c == CM_EMPTY) return (!ad_truthy(a) && ad_vt[a] != VT_NUM) ? 1 : 2; end
            if (c == CM_NOTEMPTY) return (ad_truthy(a) || ad_vt[a] == VT_NUM) ? 1 : 2; end
            if (c == CM_NOTHING) return ad_vt[a] == VT_NULL ? 1 : 2; end
            if (c == CM_NOTNOTHING) return ad_vt[a] != VT_NULL ? 1 : 2; end
            b = ad_eval(ad_xb[e]); if (ad_err != "") return 0; end
            switch (c)
                case CM_EQ: return ad_equal(a, b) ? 1 : 2; end
                case CM_NE: return ad_equal(a, b) ? 2 : 1; end
                case CM_GT: return ad_cmp_values(a, b, ln_no) > 0 ? 1 : 2; end
                case CM_LT: return ad_cmp_values(a, b, ln_no) < 0 ? 1 : 2; end
                case CM_GE: return ad_cmp_values(a, b, ln_no) >= 0 ? 1 : 2; end
                case CM_LE: return ad_cmp_values(a, b, ln_no) <= 0 ? 1 : 2; end
                case CM_CONTAINS:
                    if (ad_vt[a] == VT_STR) return find(ad_vs[a], ad_text(b)) >= 0 ? 1 : 2; end
                    if (ad_vt[a] == VT_LIST) for (i = 0; i < ad_vc[a]; i++) if (ad_equal(ad_pi[ad_vp[a] + i], b)) return 1; end end return 2; end
                    if (ad_vt[a] == VT_MAP) return ad_map_get(a, ad_text(b)) >= 0 ? 1 : 2; end
                    return 2;
                end
                case CM_STARTS: s = ad_text(a); t = ad_text(b); return substr(s, 0, len(t)) == t ? 1 : 2; end
                case CM_ENDS: s = ad_text(a); t = ad_text(b); return (len(t) <= len(s) && substr(s, len(s) - len(t)) == t) ? 1 : 2; end
            end
            return 2;
        end
        case XK_LIST:
            r = ad_list(); i = ad_xa[e];
            while (i != 0) v = ad_eval(i); if (ad_err != "") return 0; end ad_list_add(r, v); i = ad_xnext[i]; end
            return r;
        end
        case XK_MAP:
            r = ad_map(); i = ad_xa[e];
            while (i != 0) v = ad_eval(ad_xa[i]); if (ad_err != "") return 0; end ad_map_set(r, ad_xs[i], v); i = ad_xnext[i]; end
            return r;
        end
        case XK_CALL:
            // funciones del addon primero; si no, las integradas
            pg = -1;
            for (i = 0; i < ad_npg; i++) if (ad_pg_func[i] && ad_pg_name[i] == ad_xs[e]) pg = i; end end
            if (pg >= 0)
                argc = ad_xop[e]; i = ad_xa[e]; ar0 = 0; ar1 = 0; ar2 = 0; ar3 = 0; ar4 = 0; ar5 = 0; n = 0;
                while (i != 0)
                    v = ad_eval(i); if (ad_err != "") return 0; end
                    switch (n) case 0: ar0 = v; end case 1: ar1 = v; end case 2: ar2 = v; end case 3: ar3 = v; end case 4: ar4 = v; end case 5: ar5 = v; end end
                    n++; i = ad_xnext[i];
                end
                if (argc > 6) ad_rt_error(ln_no, "functions of the addon can take at most 6 values"); return 0; end
                return ad_call_user(pg, argc, ar0, ar1, ar2, ar3, ar4, ar5, ln_no);
            end
            r = ad_call_builtin(e);
            if (r >= 0) return r; end
            if (ad_err != "") return 0; end
            best = ""; bi = 3;
            for (i = 0; i < ad_npg; i++) if (ad_pg_func[i]) c = ad_lev(ad_xs[e], ad_pg_name[i]); if (c < bi) bi = c; best = ad_pg_name[i]; end end end
            if (best != "") ad_rt_error(ln_no, "I do not know a function called '" + ad_xs[e] + "' (did you mean '" + best + "'?)"); return 0; end
            ad_rt_error(ln_no, "I do not know a function called '" + ad_xs[e] + "'");
            return 0;
        end
    end
    return 0;
end

// ---- funciones integradas
declare function string ad_b64(string s) end
declare function string ad_urlenc(string s) end
declare function string ad_hex_digit(int n) end

function string ad_hex_digit(int n)
begin
    return substr("0123456789ABCDEF", n, 1);
end

function string ad_urlenc(string s)
private string r; int i, c;
begin
    r = "";
    for (i = 0; i < len(s); i++)
        c = asc(substr(s, i, 1));
        if (ad_is_alpha(c) && c != 95 || ad_is_digit(c) || c == 45 || c == 46 || c == 126) r += chr(c);
        elseif (c == 95) r += "_";
        else r += "%" + ad_hex_digit(c >> 4) + ad_hex_digit(c & 15);
        end
    end
    return r;
end

function string ad_b64(string s)
private string r, tbl; int i, n, v, b0, b1, b2;
begin
    tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    r = ""; n = len(s);
    for (i = 0; i < n; i += 3)
        b0 = asc(substr(s, i, 1));
        b1 = (i + 1 < n) ? asc(substr(s, i + 1, 1)) : 0;
        b2 = (i + 2 < n) ? asc(substr(s, i + 2, 1)) : 0;
        v = (b0 << 16) | (b1 << 8) | b2;
        r += substr(tbl, (v >> 18) & 63, 1) + substr(tbl, (v >> 12) & 63, 1);
        r += (i + 1 < n) ? substr(tbl, (v >> 6) & 63, 1) : "=";
        r += (i + 2 < n) ? substr(tbl, v & 63, 1) : "=";
    end
    return r;
end

function ad_less(int a, int b, string field)
private int xv, yv;
begin
    xv = a; yv = b;
    if (field != "")
        xv = (ad_vt[a] == VT_MAP) ? ad_map_get(a, field) : -1; if (xv < 0) xv = 0; end
        yv = (ad_vt[b] == VT_MAP) ? ad_map_get(b, field) : -1; if (yv < 0) yv = 0; end
    end
    if (ad_vt[xv] == VT_NUM && ad_vt[yv] == VT_NUM) return ad_vn[xv] < ad_vn[yv]; end
    return ad_text(xv) < ad_text(yv);
end

// ordenación estable (mezcla) de una lista; devuelve una lista nueva
function ad_sort(int l, string field)
private int n, w, lo, mid, hi, i, j, k, src, tmp, tt, r;
begin
    n = ad_vc[l];
    r = ad_list();
    if (n == 0) return r; end
    if (ad_np + n * 2 > NPOOL) ad_fail("the addon used too much memory (the data is too big)"); return r; end
    src = ad_np; tmp = ad_np + n; ad_np += n * 2;
    for (i = 0; i < n; i++) ad_pi[src + i] = ad_pi[ad_vp[l] + i]; end
    w = 1;
    while (w < n)
        lo = 0;
        while (lo < n)
            mid = lo + w; if (mid > n) mid = n; end
            hi = lo + 2 * w; if (hi > n) hi = n; end
            i = lo; j = mid; k = lo;
            while (i < mid && j < hi)
                if (ad_less(ad_pi[src + j], ad_pi[src + i], field)) ad_pi[tmp + k] = ad_pi[src + j]; j++; else ad_pi[tmp + k] = ad_pi[src + i]; i++; end
                k++;
            end
            while (i < mid) ad_pi[tmp + k] = ad_pi[src + i]; i++; k++; end
            while (j < hi) ad_pi[tmp + k] = ad_pi[src + j]; j++; k++; end
            lo += 2 * w;
        end
        tt = src; src = tmp; tmp = tt;
        w *= 2;
    end
    ad_vp[r] = src; ad_vc[r] = n; ad_vcap[r] = n;
    return r;
end

declare function string ad_pad2(int n) end
function string ad_pad2(int n)
begin
    if (n < 10) return "0" + n; end
    return "" + n;
end

// una lista de resultados no pasa de 3000 elementos
function int ad_list_len_guard(int l)
begin
    return ad_vc[l] < 3000;
end

// ---- ayudas para leer paginas HTML (webs): magnets(texto), links(texto, base), html_text(texto), html_decode(texto), find_all(texto, patron)
function string ad_utf8_chr(int cp)
begin
    if (cp < 128) return chr(cp); end
    if (cp < 2048) return chr(192 | (cp >> 6)) + chr(128 | (cp & 63)); end
    if (cp < 65536) return chr(224 | (cp >> 12)) + chr(128 | ((cp >> 6) & 63)) + chr(128 | (cp & 63)); end
    return chr(240 | (cp >> 18)) + chr(128 | ((cp >> 12) & 63)) + chr(128 | ((cp >> 6) & 63)) + chr(128 | (cp & 63));
end

// &amp; &lt; &gt; &quot; &#39; &#x27; &nbsp; ...
function string ad_html_decode(string s)
private string r, ent; int p, q, c, cp, k;
begin
    if (find(s, "&") < 0) return s; end
    r = ""; p = 0;
    while (p < len(s))
        q = find(s, "&", p);
        if (q < 0) r += substr(s, p); break; end
        r += substr(s, p, q - p);
        c = find(s, ";", q);
        if (c < 0 || c - q > 10) r += "&"; p = q + 1; continue; end
        ent = substr(s, q + 1, c - q - 1);
        if (ent == "amp") r += "&";
        elseif (ent == "lt") r += "<";
        elseif (ent == "gt") r += ">";
        elseif (ent == "quot") r += chr(34);
        elseif (ent == "apos") r += "'";
        elseif (ent == "nbsp") r += " ";
        elseif (substr(ent, 0, 1) == "#" && len(ent) > 1)
            cp = 0;
            if (substr(ent, 1, 1) == "x" || substr(ent, 1, 1) == "X")
                for (k = 2; k < len(ent); k++) cp = cp * 16 + ad_hexval(asc(substr(ent, k, 1))); end
            else
                cp = atoi(substr(ent, 1));
            end
            if (cp > 0) r += ad_utf8_chr(cp); end
        else
            r += "&" + ent + ";";
        end
        p = c + 1;
    end
    return r;
end

function string ad_url_decode(string s)
private string r; int i, c;
begin
    r = ""; i = 0;
    while (i < len(s))
        c = asc(substr(s, i, 1));
        if (c == 37 && i + 2 < len(s) + 0 && ad_hexval(asc(substr(s, i + 1, 1))) >= 0 && ad_hexval(asc(substr(s, i + 2, 1))) >= 0)
            r += chr(ad_hexval(asc(substr(s, i + 1, 1))) * 16 + ad_hexval(asc(substr(s, i + 2, 1)))); i += 3;
        elseif (c == 43) r += " "; i++;
        else r += chr(c); i++; end
    end
    return r;
end

function string ad_collapse(string s)
private string r; int i, c, sp;
begin
    r = ""; sp = 1;
    for (i = 0; i < len(s); i++)
        c = asc(substr(s, i, 1));
        if (c == 32 || c == 9 || c == 10 || c == 13) if (!sp) r += " "; sp = 1; end
        else r += chr(c); sp = 0; end
    end
    if (len(r) > 0 && substr(r, len(r) - 1, 1) == " ") r = substr(r, 0, len(r) - 1); end
    return r;
end

// quita las etiquetas (y el contenido de script y style)
function string ad_strip_tags(string s)
private string r, lo; int p, q, c;
begin
    r = ""; p = 0; lo = lcase(s);
    while (p < len(s))
        q = find(s, "<", p);
        if (q < 0) r += substr(s, p); break; end
        r += substr(s, p, q - p);
        if (substr(lo, q, 7) == "<script" || substr(lo, q, 6) == "<style")
            c = find(lo, substr(lo, q, 7) == "<script" ? "</script>" : "</style>", q);
            if (c < 0) break; end
            c = find(s, ">", c); if (c < 0) break; end
            r += " "; p = c + 1; continue;
        end
        c = find(s, ">", q);
        if (c < 0) break; end
        r += " "; p = c + 1;
    end
    return r;
end

function string ad_html_text(string s)
begin
    return ad_collapse(ad_html_decode(ad_strip_tags(s)));
end

// direccion completa de un enlace de una pagina
function string ad_abs_url(string base, string h)
private int p, q; string origin, dir;
begin
    if (substr(h, 0, 7) == "http://" || substr(h, 0, 8) == "https://" || substr(h, 0, 7) == "magnet:") return h; end
    p = find(base, "://");
    if (p < 0) return h; end
    if (substr(h, 0, 2) == "//") return substr(base, 0, p) + ":" + h; end
    q = find(base, "/", p + 3);
    origin = q < 0 ? base : substr(base, 0, q);
    if (substr(h, 0, 1) == "/") return origin + h; end
    q = find(base, "?"); dir = q < 0 ? base : substr(base, 0, q);
    q = len(dir) - 1;
    while (q > p + 3 && substr(dir, q, 1) != "/") q--; end
    if (q <= p + 3) return origin + "/" + h; end
    return substr(dir, 0, q + 1) + h;
end

// enlaces magnet de un texto: lista de {name, magnet}
function int ad_magnets(string t)
private int r, p, e, m, k, c; string mg, nm, hash, seen, dn;
begin
    r = ad_list(); seen = "|"; p = 0;
    while (ad_list_len_guard(r))
        p = find(t, "magnet:?", p);
        if (p < 0) break; end
        e = p + 8;
        while (e < len(t))
            c = asc(substr(t, e, 1));
            if (c == 34 || c == 39 || c == 60 || c == 62 || c == 32 || c == 9 || c == 10 || c == 13 || c == 92) break; end
            e++;
        end
        mg = ad_html_decode(substr(t, p, e - p));
        p = e;
        k = find(lcase(mg), "xt=urn:btih:");
        if (k < 0) continue; end
        hash = lcase(substr(mg, k + 12, 40));
        if (find(seen, "|" + hash + "|") >= 0) continue; end
        seen += hash + "|";
        nm = hash;
        k = find(mg, "dn=");
        if (k >= 0)
            dn = substr(mg, k + 3); c = find(dn, "&"); if (c >= 0) dn = substr(dn, 0, c); end
            nm = ad_url_decode(dn);
        end
        k = find(mg, "xl="); c = 0;
        if (k >= 0) dn = substr(mg, k + 3); if (find(dn, "&") >= 0) dn = substr(dn, 0, find(dn, "&")); end c = atoi(dn); end
        m = ad_map(); ad_map_set(m, "name", ad_str(nm)); ad_map_set(m, "magnet", ad_str(mg)); ad_map_set(m, "size", ad_num(c)); ad_list_add(r, m);
    end
    return r;
end

// enlaces <a href> de una pagina: lista de {url, text}
function int ad_links(string t, string base)
private int r, p, q, c, m, close; string lo, tag, ltag, href, q1, inner;
begin
    r = ad_list(); lo = lcase(t); p = 0;
    while (ad_list_len_guard(r))
        p = find(lo, "<a ", p);
        if (p < 0) break; end
        q = find(t, ">", p);
        if (q < 0) break; end
        tag = substr(t, p, q - p); ltag = substr(lo, p, q - p);
        close = find(lo, "</a>", q);
        inner = close < 0 ? "" : substr(t, q + 1, close - q - 1);
        p = q + 1;
        c = find(ltag, "href=");
        if (c < 0) continue; end
        q1 = substr(tag, c + 5, 1); href = "";
        if (q1 == chr(34) || q1 == "'")
            close = find(tag, q1, c + 6); href = close < 0 ? "" : substr(tag, c + 6, close - c - 6);
        else
            href = substr(tag, c + 5); close = find(href, " "); if (close >= 0) href = substr(href, 0, close); end
        end
        href = ad_html_decode(href);
        if (href == "" || substr(href, 0, 1) == "#" || substr(lcase(href), 0, 11) == "javascript:") continue; end
        m = ad_map(); ad_map_set(m, "url", ad_str(ad_abs_url(base, href))); ad_map_set(m, "text", ad_str(ad_html_text(inner))); ad_list_add(r, m);
    end
    return r;
end

// todas las coincidencias de una expresion regular: el primer grupo (o la coincidencia entera) de cada una
function int ad_find_all(string t, string pat)
private int r, pos, n; string rest, g;
begin
    r = ad_list(); rest = t; n = 0;
    while (n < 5000 && ad_list_len_guard(r))
        pos = regex(pat, rest);
        if (pos < 0) break; end
        g = regex_reg[1] != "" ? regex_reg[1] : regex_reg[0];
        ad_list_add(r, ad_str(g)); n++;
        pos += len(regex_reg[0]) > 0 ? len(regex_reg[0]) : 1;
        if (pos >= len(rest)) break; end
        rest = substr(rest, pos);
    end
    return r;
end

// valor del atributo name="..." de una etiqueta (tag, y ltag = la misma en minusculas)
function string ad_attr(string tag, string ltag, string name)
private int c, close; string q1, v;
begin
    c = find(ltag, " " + name + "=");
    if (c < 0) return ""; end
    c += len(name) + 2; q1 = substr(tag, c, 1);
    if (q1 == chr(34) || q1 == "'")
        close = find(tag, q1, c + 1); v = close < 0 ? "" : substr(tag, c + 1, close - c - 1);
    else
        v = substr(tag, c); close = find(v, " "); if (close >= 0) v = substr(v, 0, close); end
        if (substr(v, len(v) - 1, 1) == "/" || substr(v, len(v) - 1, 1) == ">") v = substr(v, 0, len(v) - 1); end
    end
    return ad_html_decode(v);
end

function string ad_host_of(string u)
private int p, q; string h;
begin
    p = find(u, "://");
    h = p < 0 ? u : substr(u, p + 3);
    q = find(h, "/"); if (q >= 0) h = substr(h, 0, q); end
    q = find(h, "?"); if (q >= 0) h = substr(h, 0, q); end
    if (substr(lcase(h), 0, 4) == "www.") h = substr(h, 4); end
    return h;
end

function string ad_origin_of(string u)
private int p, q;
begin
    p = find(u, "://");
    if (p < 0) return u; end
    q = find(u, "/", p + 3);
    return q < 0 ? u : substr(u, 0, q);
end

// Muchas webs no tienen un formulario que se pueda leer: la busqueda la hace JavaScript y lleva a una direccion como /buscar/palabra.
// Se mira si la pagina (enlaces o codigo) nombra una ruta de busqueda y se devuelve la direccion con {q} ("" si no hay pistas)
function string ad_search_hint(string t, string base)
private string lo, kw[8], path; int i, p, st, en, c, k;
begin
    kw[0] = "/buscar/"; kw[1] = "/search/"; kw[2] = "/busqueda/"; kw[3] = "/busca/"; kw[4] = "/find/"; kw[5] = "/resultados/"; kw[6] = "/s/"; kw[7] = "/query/";
    lo = lcase(t);
    // 1) el codigo de la pagina une una ruta con lo que se escribe, se llame como se llame:  "/lo-que-sea/" + palabra   o   "/buscar?q=" + palabra
    // (en este motor de expresiones el + y el ? solo valen entre corchetes: "x+" se escribe "xx*")
    p = regex("[\"'](/[a-z0-9_.~-][a-z0-9_.~-]*/[a-z0-9_.~-][a-z0-9_.~-]*/)[\"'][ ]*[+]", t);
    if (p >= 0 && regex_reg[1] != "") return ad_abs_url(base, regex_reg[1]) + "{q}"; end
    p = regex("[\"'](/[a-z0-9_.~-][a-z0-9_.~-]*/)[\"'][ ]*[+]", t);
    if (p >= 0 && regex_reg[1] != "") return ad_abs_url(base, regex_reg[1]) + "{q}"; end
    p = regex("[\"'](/[a-z0-9_./~-]*[?][a-z0-9_][a-z0-9_]*=)[\"'][ ]*[+]", t);
    if (p >= 0 && regex_reg[1] != "") return ad_abs_url(base, regex_reg[1]) + "{q}"; end
    // 2) rutas que suelen usarse para buscar
    for (i = 0; i < 8; i++)
        p = find(lo, kw[i]);
        while (p >= 0)
            st = p;                                                      // el principio de la ruta: hasta una comilla, un espacio, un parentesis...
            while (st > 0)
                c = asc(substr(t, st - 1, 1));
                if (c == 34 || c == 39 || c == 32 || c == 40 || c == 61 || c == 60 || c == 62 || c == 10 || c == 13 || c == 9) break; end
                st--;
            end
            if (substr(t, st, 1) == "/" || substr(t, st, 4) == "http")
                en = p + len(kw[i]);
                path = substr(t, st, en - st);
                if (len(path) < 80 && find(path, "{") < 0 && find(path, "}") < 0) return ad_abs_url(base, path) + "{q}"; end
            end
            p = find(lo, kw[i], p + 1);
        end
    end
    return "";
end

// el formulario de busqueda de una pagina: devuelve la direccion con {q} donde van las palabras ("" si no hay ninguno)
function string ad_search_form(string t, string base)
private string lo, ftag, lftag, act, meth, body, lbody, tag, ltag, nm, ty, val, params, qname, qtype, best, url; int p, q, e, ip, iq, score, bestscore;
begin
    lo = lcase(t); p = 0; best = ""; bestscore = 0;
    while (p >= 0)
        p = find(lo, "<form", p);
        if (p < 0) break; end
        q = find(t, ">", p);
        if (q < 0) break; end
        ftag = substr(t, p, q - p); lftag = substr(lo, p, q - p);
        e = find(lo, "</form>", q);
        body = e < 0 ? substr(t, q + 1) : substr(t, q + 1, e - q - 1); lbody = lcase(body);
        p = q;
        meth = lcase(ad_attr(ftag, lftag, "method"));
        if (find(lbody, "type=\"password\"") >= 0 || find(lbody, "type='password'") >= 0 || find(lbody, "type=password") >= 0) continue; end    // un formulario de acceso no es una busqueda
        act = ad_attr(ftag, lftag, "action");
        qname = ""; qtype = ""; params = ""; ip = 0;
        while (ip >= 0)
            ip = find(lbody, "<input", ip);
            if (ip < 0) break; end
            iq = find(body, ">", ip);
            if (iq < 0) break; end
            tag = substr(body, ip, iq - ip); ltag = substr(lbody, ip, iq - ip);
            ip = iq;
            ty = lcase(ad_attr(tag, ltag, "type")); nm = ad_attr(tag, ltag, "name"); val = ad_attr(tag, ltag, "value");
            if (nm == "") continue; end
            if ((ty == "" || ty == "text" || ty == "search") && qname == "") qname = nm; qtype = ty;
            elseif (ty == "hidden") params += "&" + nm + "=" + ad_urlenc(val); end
        end
        if (qname == "") continue; end
        score = 1;
        if (qtype == "search") score += 2; end
        nm = lcase(qname);
        if (nm == "q" || nm == "s" || nm == "search" || nm == "query" || nm == "keyword" || nm == "keywords" || nm == "term" || nm == "find" || nm == "k") score += 2; end
        if (find(lcase(ftag), "search") >= 0 || find(lcase(act), "search") >= 0) score += 1; end
        if (score > bestscore)
            bestscore = score;
            url = ad_abs_url(base, act == "" ? base : act);
            if (meth == "post") best = "post:" + url + "|" + qname + "={q}" + params;                    // se envia por POST: "post:direccion|cuerpo"
            else best = url + (find(url, "?") >= 0 ? "&" : "?") + qname + "={q}" + params; end
        end
    end
    return best;
end

// ---- carpetas: list_files(carpeta, extension) -> lista de {name, path, size}; data_folder() -> la carpeta de datos del reproductor; make_folder(ruta)
function int ad_list_files(string folder, string ext)
private int r, dh, m; string nm;
begin
    r = ad_list();
    dh = diropen(join_path(folder, "*"));
    if (!dh) return r; end
    nm = dirread(dh);
    while (nm != "" && ad_vc[r] < 500)
        if (!fileinfo.directory && nm != "." && nm != ".." && (ext == "" || lcase(ext_of(nm)) == lcase(ext)))
            m = ad_map(); ad_map_set(m, "name", ad_str(nm)); ad_map_set(m, "path", ad_str(join_path(folder, nm))); ad_map_set(m, "size", ad_num(fileinfo.size));
            ad_list_add(r, m);
        end
        nm = dirread(dh);
    end
    dirclose(dh);
    return r;
end

function ad_call_builtin(int e)
private string f, s, t, u; int argc, i, n, r, c, ln_no, a0, a1, a2, a3, v, p; double d, d2;
begin
    f = ad_xs[e]; ln_no = ad_xl[e]; argc = ad_xop[e];
    a0 = 0; a1 = 0; a2 = 0; a3 = 0;
    i = ad_xa[e]; n = 0;
    while (i != 0)
        v = ad_eval(i); if (ad_err != "") return 0; end
        switch (n) case 0: a0 = v; end case 1: a1 = v; end case 2: a2 = v; end case 3: a3 = v; end end
        n++; i = ad_xnext[i];
    end
    if (f == "length")
        if (argc < 1) ad_rt_error(ln_no, "length() needs a value"); return 0; end
        if (ad_vt[a0] == VT_STR) return ad_num(ad_utf8_len(ad_vs[a0])); end
        if (ad_vt[a0] == VT_LIST || ad_vt[a0] == VT_MAP) return ad_num(ad_vc[a0]); end
        return ad_num(0);
    elseif (f == "upper") return ad_str(ucase(ad_text(a0)));
    elseif (f == "lower") return ad_str(lcase(ad_text(a0)));
    elseif (f == "trim") return ad_str(trim(ad_text(a0)));
    elseif (f == "text") return ad_str(ad_text(a0));
    elseif (f == "number")
        if (ad_vt[a0] == VT_NUM) return a0; end
        return ad_num(atof(ad_text(a0)));
    elseif (f == "round")
        d = ad_to_num(a0, ln_no, "round()");
        if (argc > 1) c = (int)ad_to_num(a1, ln_no, "round()"); else c = 0; end
        d2 = pow(10, c);
        return ad_num(floor(d * d2 + 0.5) / d2);
    elseif (f == "floor") return ad_num(floor(ad_to_num(a0, ln_no, "floor()")));
    elseif (f == "ceil") return ad_num(ceil(ad_to_num(a0, ln_no, "ceil()")));
    elseif (f == "abs") return ad_num(abs(ad_to_num(a0, ln_no, "abs()")));
    elseif (f == "min") d = ad_to_num(a0, ln_no, "min()"); d2 = ad_to_num(a1, ln_no, "min()"); return ad_num(d < d2 ? d : d2);
    elseif (f == "max") d = ad_to_num(a0, ln_no, "max()"); d2 = ad_to_num(a1, ln_no, "max()"); return ad_num(d > d2 ? d : d2);
    elseif (f == "random") c = (int)ad_to_num(a0, ln_no, "random()"); if (c < 1) return ad_num(0); end return ad_num(rand(1, c));
    elseif (f == "replace")
        s = ad_text(a0); t = ad_text(a1); u = ad_text(a2);
        if (t == "") return a0; end
        r = ad_str(""); p = 0; n = 0; v = 0;
        loop
            c = find(s, t, p);
            if (c < 0) break; end
            ad_vs[r] += substr(s, p, c - p) + u; p = c + len(t); n++;
            if (n > 100000) break; end
        end
        ad_vs[r] += substr(s, p);
        return r;
    elseif (f == "json") return ad_str(ad_json_text(a0));
    elseif (f == "parse_json")
        ad_str_to_buf(ad_text(a0)); v = ad_json_parse();
        if (v < 0) return 0; end
        return v;
    elseif (f == "search_form") return ad_str(ad_search_form(ad_text(a0), argc > 1 ? ad_text(a1) : ""));
    elseif (f == "search_hint") return ad_str(ad_search_hint(ad_text(a0), argc > 1 ? ad_text(a1) : ""));
    elseif (f == "host_of") return ad_str(ad_host_of(ad_text(a0)));
    elseif (f == "origin_of") return ad_str(ad_origin_of(ad_text(a0)));
    elseif (f == "list_files") return ad_list_files(ad_text(a0), argc > 1 ? ad_text(a1) : "");
    elseif (f == "data_folder") return ad_str(store_dir);
    elseif (f == "make_folder") mkdir(ad_text(a0)); return 0;
    elseif (f == "magnets") return ad_magnets(ad_text(a0));
    elseif (f == "links") return ad_links(ad_text(a0), argc > 1 ? ad_text(a1) : "");
    elseif (f == "html_text") return ad_str(ad_html_text(ad_text(a0)));
    elseif (f == "html_decode") return ad_str(ad_html_decode(ad_text(a0)));
    elseif (f == "find_all") return ad_find_all(ad_text(a0), ad_text(a1));
    elseif (f == "format_size") return ad_str(fmt_size((int)ad_to_num(a0, ln_no, "format_size()")));
    elseif (f == "url_encode") return ad_str(ad_urlenc(ad_text(a0)));
    elseif (f == "base64") return ad_str(ad_b64(ad_text(a0)));
    elseif (f == "now") return ad_num(time());
    elseif (f == "uuid")
        s = "";
        for (i = 0; i < 32; i++)
            if (i == 8 || i == 12 || i == 16 || i == 20) s += "-"; end
            if (i == 12) s += "4"; elseif (i == 16) s += substr("89ab", rand(0, 3), 1); else s += substr("0123456789abcdef", rand(0, 15), 1); end
        end
        return ad_str(s);
    elseif (f == "format_time")
        c = (int)ad_to_num(a0, ln_no, "format_time()");
        if (c >= 3600) return ad_str((c / 3600) + ":" + ad_pad2((c / 60) % 60) + ":" + ad_pad2(c % 60)); end
        return ad_str((c / 60) + ":" + ad_pad2(c % 60));
    elseif (f == "first") if (ad_vt[a0] == VT_LIST && ad_vc[a0] > 0) return ad_pi[ad_vp[a0]]; end return 0;
    elseif (f == "last") if (ad_vt[a0] == VT_LIST && ad_vc[a0] > 0) return ad_pi[ad_vp[a0] + ad_vc[a0] - 1]; end return 0;
    elseif (f == "reverse")
        r = ad_list();
        if (ad_vt[a0] == VT_LIST) for (i = ad_vc[a0] - 1; i >= 0; i--) ad_list_add(r, ad_pi[ad_vp[a0] + i]); end end
        return r;
    elseif (f == "range")
        d = ad_to_num(a0, ln_no, "range()"); d2 = ad_to_num(a1, ln_no, "range()"); r = ad_list();
        if (d2 - d > 100000) ad_rt_error(ln_no, "range() is too big"); return 0; end
        for (i = (int)d; i <= (int)d2; i++) ad_list_add(r, ad_num(i)); end
        return r;
    elseif (f == "keys")
        r = ad_list();
        if (ad_vt[a0] == VT_MAP) for (i = 0; i < ad_vc[a0]; i++) ad_list_add(r, ad_str(ad_pk[ad_vp[a0] + i])); end end
        return r;
    elseif (f == "has") return (ad_vt[a0] == VT_MAP && ad_map_get(a0, ad_text(a1)) >= 0) ? 1 : 2;
    elseif (f == "default")
        if (ad_vt[a0] == VT_NULL || (ad_vt[a0] == VT_STR && len(ad_vs[a0]) == 0)) return a1; end
        return a0;
    elseif (f == "index_of") s = ad_text(a0); c = find(s, ad_text(a1)); return ad_num(c < 0 ? 0 : c + 1);
    elseif (f == "shorten")
        s = ad_text(a0); c = (int)ad_to_num(a1, ln_no, "shorten()");
        if (ad_utf8_len(s) <= c) return a0; end
        n = 0; i = 0;
        while (i < len(s) && n < c - 1)
            i++; while (i < len(s) && (asc(substr(s, i, 1)) & 192) == 128) i++; end
            n++;
        end
        return ad_str(substr(s, 0, i) + "...");
    elseif (f == "slice")
        n = (int)ad_to_num(a1, ln_no, "slice()"); c = (int)ad_to_num(a2, ln_no, "slice()");
        if (ad_vt[a0] == VT_LIST)
            r = ad_list();
            for (i = n; i <= c && i <= ad_vc[a0]; i++) if (i >= 1) ad_list_add(r, ad_pi[ad_vp[a0] + i - 1]); end end
            return r;
        end
        s = ad_text(a0); if (n < 1) n = 1; end if (c > len(s)) c = len(s); end
        if (c < n) return ad_str(""); end
        return ad_str(substr(s, n - 1, c - n + 1));
    elseif (f == "pick")
        r = ad_list(); s = ad_text(a1);
        if (ad_vt[a0] == VT_LIST)
            for (i = 0; i < ad_vc[a0]; i++)
                v = ad_pi[ad_vp[a0] + i]; c = (ad_vt[v] == VT_MAP) ? ad_map_get(v, s) : -1;
                ad_list_add(r, c < 0 ? 0 : c);
            end
        end
        return r;
    elseif (f == "filter")
        r = ad_list(); s = ad_text(a1);
        if (ad_vt[a0] == VT_LIST)
            for (i = 0; i < ad_vc[a0]; i++)
                v = ad_pi[ad_vp[a0] + i]; c = (ad_vt[v] == VT_MAP) ? ad_map_get(v, s) : -1;
                if (c >= 0 && ad_equal(c, a2)) ad_list_add(r, v); end
            end
        end
        return r;
    elseif (f == "sort")
        if (ad_vt[a0] != VT_LIST) ad_rt_error(ln_no, "sort() needs a list"); return 0; end
        return ad_sort(a0, argc > 1 ? ad_text(a1) : "");
    elseif (f == "join_url")
        s = ad_text(a0); t = ad_text(a1);
        if (substr(t, 0, 7) == "http://" || substr(t, 0, 8) == "https://") return a1; end
        c = (len(s) > 0 && substr(s, len(s) - 1, 1) == "/"); n = (substr(t, 0, 1) == "/");
        if (c && n) return ad_str(s + substr(t, 1)); end
        if (!c && !n) return ad_str(s + "/" + t); end
        return ad_str(s + t);
    elseif (f == "split")
        s = ad_text(a0); t = ad_text(a1); r = ad_list();
        if (t == "") ad_list_add(r, a0); return r; end
        p = 0;
        loop
            c = find(s, t, p);
            if (c < 0) ad_list_add(r, ad_str(substr(s, p))); break; end
            ad_list_add(r, ad_str(substr(s, p, c - p))); p = c + len(t);
        end
        return r;
    elseif (f == "join")
        if (ad_vt[a0] != VT_LIST) ad_rt_error(ln_no, "join() needs a list as its first value"); return 0; end
        s = ""; t = (argc > 1) ? ad_text(a1) : ", ";
        for (i = 0; i < ad_vc[a0]; i++) if (i > 0) s += t; end s += ad_text(ad_pi[ad_vp[a0] + i]); end
        return ad_str(s);
    end
    return -1;
end

// ---- sentencias
declare function int ad_exec_block(int s) end

function ad_container(int e, int want_list)
private int v, parent, i, ix, idx; string key;
begin
    switch (ad_xk[e])
        case XK_VAR:
            v = ad_sc_get(ad_xs[e]);
            if (v < 0 || ad_vt[v] == VT_NULL)
                v = want_list ? ad_list() : ad_map(); ad_sc_set(ad_xs[e], v);
            end
            return v;
        end
        case XK_FIELD:
            parent = ad_container(ad_xa[e], 0); if (ad_err != "") return 0; end
            if (ad_vt[parent] != VT_MAP) ad_rt_error(ad_xl[e], "cannot set '" + ad_xs[e] + "' inside " + ad_type_name(parent) + ": only records have fields"); return 0; end
            v = ad_map_get(parent, ad_xs[e]);
            if (v < 0 || ad_vt[v] == VT_NULL) v = want_list ? ad_list() : ad_map(); ad_map_set(parent, ad_xs[e], v); end
            return v;
        end
        default: return ad_eval(e); end
    end
end

function ad_assign(int lv, int val)
private int b, ix, i; string key;
begin
    switch (ad_xk[lv])
        case XK_VAR:
            if (ad_find_setting(ad_xs[lv]) >= 0) ad_rt_error(ad_xl[lv], "'" + ad_xs[lv] + "' is a setting; use  save " + ad_xs[lv] + " as ...  to change it"); return 0; end
            ad_sc_set(ad_xs[lv], val); return 1;
        end
        case XK_FIELD:
            b = ad_container(ad_xa[lv], 0); if (ad_err != "") return 0; end
            if (ad_vt[b] != VT_MAP) ad_rt_error(ad_xl[lv], "cannot set '" + ad_xs[lv] + "' inside " + ad_type_name(b) + ": only records have fields"); return 0; end
            ad_map_set(b, ad_xs[lv], val); return 1;
        end
        case XK_INDEX:
            b = ad_container(ad_xa[lv], 0); if (ad_err != "") return 0; end
            ix = ad_eval(ad_xb[lv]); if (ad_err != "") return 0; end
            if (ad_vt[b] == VT_LIST)
                i = (int)ad_to_num(ix, ad_xl[lv], "a list position");
                if (i >= 1 && i <= ad_vc[b]) ad_pi[ad_vp[b] + i - 1] = val;
                elseif (i == ad_vc[b] + 1) ad_list_add(b, val);
                else ad_rt_error(ad_xl[lv], "position " + i + " is outside the list (it has " + ad_vc[b] + " items)"); end
                return 1;
            elseif (ad_vt[b] == VT_MAP) ad_map_set(b, ad_text(ix), val); return 1;
            end
            ad_rt_error(ad_xl[lv], "cannot use [ ] on " + ad_type_name(b)); return 0;
        end
    end
    ad_rt_error(ad_xl[lv], "this cannot be assigned to");
    return 0;
end

function string ad_hdr_text(int h)
private string r, k, v;
begin
    r = "";
    while (h != 0)
        k = ad_text(ad_eval(ad_ar_ne[h])); v = ad_text(ad_eval(ad_ar_e[h]));
        if (ad_err != "") return ""; end
        if (find(k, chr(10)) >= 0 || find(v, chr(10)) >= 0 || find(k, chr(13)) >= 0 || find(v, chr(13)) >= 0) ad_fail("a header cannot contain a line break"); return ""; end
        r += k + ": " + v + chr(13) + chr(10);
        h = ad_ar_next[h];
    end
    return r;
end

function ad_call_user(int pg, int argc, int a0, int a1, int a2, int a3, int a4, int a5, int ln_no)
private int saved_base, saved_top, saved_give, i, v;
begin
    if (ad_depth >= 40) ad_rt_error(ln_no, "functions call each other too deeply (is '" + ad_pg_name[pg] + "' calling itself forever?)"); return 0; end
    if (argc != ad_pg_np[pg]) ad_rt_error(ln_no, ad_pg_name[pg] + "() needs " + ad_pg_np[pg] + " value(s) but got " + argc); return 0; end
    saved_base = ad_sc_base; saved_top = ad_sc_top; saved_give = ad_give;
    ad_sc_base = ad_sc_top; ad_depth++; ad_give = 0;
    for (i = 0; i < argc; i++)
        switch (i) case 0: v = a0; end case 1: v = a1; end case 2: v = a2; end case 3: v = a3; end case 4: v = a4; end default: v = a5; end end
        ad_sc_set(ad_pg_par[pg * 12 + i], v);
    end
    ad_exec_block(ad_pg_body[pg]);
    v = ad_give;
    ad_depth--; ad_sc_base = saved_base; ad_sc_top = saved_top; ad_give = saved_give;
    return v;
end

function ad_add_item(int s)
private int it, a, args, v; string t;
begin
    if (ad_nit >= AD_MAXIT) ad_rt_error(ad_sl[s], "a page can show at most " + AD_MAXIT + " items"); return 0; end
    it = ad_nit; ad_nit++;
    ad_it_kind[it] = ad_smode[s]; ad_it_flag[it] = 0;
    ad_it_title[it] = ad_text(ad_eval(ad_se[s * 8])); ad_it_page[it] = ""; ad_it_args[it] = ""; ad_it_url[it] = ""; ad_it_logo[it] = ""; ad_it_info[it] = ""; ad_it_year[it] = 0; ad_it_dur[it] = 0; ad_it_sub[it] = ""; ad_it_hdr[it] = "";
    if (ad_err != "") ad_nit--; return 0; end
    if (ad_smode[s] >= 5 && ad_smode[s] <= 7)                         // check / choice / input: a setting that the user changes from the list
        v = ad_find_setting(ad_sname[s]);
        if (v < 0) ad_rt_error(ad_sl[s], "there is no setting called '" + ad_sname[s] + "' (add a 'setting' line for it)"); ad_nit--; return 0; end
        ad_it_url[it] = ad_sname[s]; ad_it_flag[it] = v;
        if (ad_smode[s] == 5 && ad_st_type[v] != "yesno") ad_rt_error(ad_sl[s], "a check needs a 'yes or no' setting"); ad_nit--; return 0; end
        if (ad_smode[s] == 6 && ad_st_type[v] != "choice") ad_rt_error(ad_sl[s], "a choice needs a 'choice' setting"); ad_nit--; return 0; end
    elseif (ad_sname[s] != "")
        ad_it_page[it] = ad_sname[s];
        v = -1;
        for (a = 0; a < ad_npg; a++) if (ad_pg_name[a] == ad_sname[s] && !ad_pg_func[a]) v = a; end end
        if (v < 0) ad_rt_error(ad_sl[s], "there is no page called '" + ad_sname[s] + "'"); ad_nit--; return 0; end
        args = ad_map(); a = ad_sargs[s];
        while (a != 0)
            ad_map_set(args, ad_ar_name[a], ad_eval(ad_ar_e[a])); if (ad_err != "") ad_nit--; return 0; end
            a = ad_ar_next[a];
        end
        ad_it_args[it] = ad_json_text(args);
    end
    if (ad_se[s * 8 + 1] != 0) ad_it_url[it] = ad_text(ad_eval(ad_se[s * 8 + 1])); end
    if (ad_se[s * 8 + 2] != 0) ad_it_logo[it] = ad_text(ad_eval(ad_se[s * 8 + 2])); end
    if (ad_se[s * 8 + 3] != 0) ad_it_info[it] = ad_text(ad_eval(ad_se[s * 8 + 3])); end
    if (ad_se[s * 8 + 4] != 0) ad_it_year[it] = (int)ad_to_num(ad_eval(ad_se[s * 8 + 4]), ad_sl[s], "the year"); end
    if (ad_se[s * 8 + 5] != 0) ad_it_dur[it] = (int)ad_to_num(ad_eval(ad_se[s * 8 + 5]), ad_sl[s], "the duration"); end
    if (ad_se[s * 8 + 6] != 0) ad_it_sub[it] = ad_text(ad_eval(ad_se[s * 8 + 6])); end
    if (ad_shdrs[s] != 0) ad_it_hdr[it] = ad_hdr_text(ad_shdrs[s]); end
    if (ad_err != "") ad_nit--; return 0; end
    return 1;
end

function ad_exec_stmt(int s)
private int v, l, lim, count, i, fl, cnt, k, ex, hdrs, body, bd, a, mp; string url, hdr, method, res; double d;
begin
    if (ad_err != "") return FL_NORMAL; end
    ad_steps++;
    if (ad_steps > 4000000) ad_rt_error(ad_sl[s], "the addon ran for too long (is there a loop that never ends?)"); return FL_NORMAL; end
    if (ad_cancelled) ad_fail("cancelled"); return FL_NORMAL; end
    switch (ad_sk[s])
        case SK_SET: v = ad_eval(ad_se[s * 8 + 1]); if (ad_err == "") ad_assign(ad_se[s * 8], v); end return FL_NORMAL; end
        case SK_ADD:
            v = ad_eval(ad_se[s * 8]); if (ad_err != "") return FL_NORMAL; end
            l = ad_container(ad_se[s * 8 + 1], 1); if (ad_err != "") return FL_NORMAL; end
            if (ad_vt[l] != VT_LIST) ad_rt_error(ad_sl[s], "'add ... to' needs a list, but this is " + ad_type_name(l)); return FL_NORMAL; end
            ad_list_add(l, v); return FL_NORMAL;
        end
        case SK_CLEAR: v = ad_eval(ad_se[s * 8]); if (ad_err == "" && (ad_vt[v] == VT_LIST || ad_vt[v] == VT_MAP)) ad_vc[v] = 0; end return FL_NORMAL; end
        case SK_IF:
            while (s != 0)
                if (ad_se[s * 8] == 0) return ad_exec_block(ad_sbody[s]); end
                v = ad_eval(ad_se[s * 8]); if (ad_err != "") return FL_NORMAL; end
                if (ad_truthy(v)) return ad_exec_block(ad_sbody[s]); end
                s = ad_selse[s];
            end
            return FL_NORMAL;
        end
        case SK_FOR:
            l = ad_eval(ad_se[s * 8]); if (ad_err != "") return FL_NORMAL; end
            lim = 1000000000;
            if (ad_se[s * 8 + 1] != 0) lim = (int)ad_to_num(ad_eval(ad_se[s * 8 + 1]), ad_sl[s], "the limit"); end
            if (ad_vt[l] == VT_NULL) return FL_NORMAL; end
            if (ad_vt[l] != VT_LIST && ad_vt[l] != VT_MAP) ad_rt_error(ad_sl[s], "'for each' needs a list or a record to go through, but this is " + ad_type_name(l)); return FL_NORMAL; end
            count = ad_vc[l];
            for (i = 0; i < count && i < lim; i++)
                ad_sc_set(ad_sname[s], ad_pi[ad_vp[l] + i]);
                ad_sc_set("index", ad_num(i + 1));
                if (ad_vt[l] == VT_MAP) ad_sc_set("key", ad_str(ad_pk[ad_vp[l] + i])); end
                fl = ad_exec_block(ad_sbody[s]);
                if (ad_err != "") return FL_NORMAL; end
                if (fl == FL_EXIT) break; end
                if (fl == FL_STOP || fl == FL_RETURN) return fl; end
            end
            return FL_NORMAL;
        end
        case SK_WHILE:
            cnt = 0;
            loop
                v = ad_eval(ad_se[s * 8]); if (ad_err != "" || !ad_truthy(v)) break; end
                cnt++;
                if (cnt > 200000) ad_rt_error(ad_sl[s], "this 'while' loop ran more than 200000 times (does its condition ever become false?)"); return FL_NORMAL; end
                fl = ad_exec_block(ad_sbody[s]);
                if (ad_err != "") return FL_NORMAL; end
                if (fl == FL_EXIT) break; end
                if (fl == FL_STOP || fl == FL_RETURN) return fl; end
            end
            return FL_NORMAL;
        end
        case SK_REPEAT:
            cnt = (int)ad_to_num(ad_eval(ad_se[s * 8]), ad_sl[s], "'repeat'"); if (ad_err != "") return FL_NORMAL; end
            if (cnt > 200000) ad_rt_error(ad_sl[s], "'repeat' is limited to 200000 times"); return FL_NORMAL; end
            for (i = 0; i < cnt; i++)
                ad_sc_set("counter", ad_num(i + 1));
                fl = ad_exec_block(ad_sbody[s]);
                if (ad_err != "") return FL_NORMAL; end
                if (fl == FL_EXIT) break; end
                if (fl == FL_STOP || fl == FL_RETURN) return fl; end
            end
            return FL_NORMAL;
        end
        case SK_STOP: return FL_STOP; end
        case SK_SKIP: return FL_SKIP; end
        case SK_EXIT: return FL_EXIT; end
        case SK_GIVE: ad_give = ad_eval(ad_se[s * 8]); return FL_RETURN; end
        case SK_CALL: ad_eval(ad_se[s * 8]); return FL_NORMAL; end
        case SK_FAIL: ad_err = ad_text(ad_eval(ad_se[s * 8])); if (ad_err == "") ad_err = "the addon stopped with an error"; end return FL_NORMAL; end
        case SK_LOG: host_log(ad_text(ad_eval(ad_se[s * 8]))); return FL_NORMAL; end
        case SK_MESSAGE:
            if (ad_se[s * 8] != 0) host_message(ad_text(ad_eval(ad_se[s * 8]))); else host_message(""); end
            return FL_NORMAL;
        end
        case SK_WAIT:
            d = ad_to_num(ad_eval(ad_se[s * 8]), ad_sl[s], "'wait'"); if (ad_err != "") return FL_NORMAL; end
            if (d > 120) d = 120; end
            cnt = (int)(d * 60);
            for (i = 0; i < cnt && !ad_cancelled; i++) ui_wait_frame(); end
            return FL_NORMAL;
        end
        case SK_SAVE: v = ad_eval(ad_se[s * 8]); if (ad_err == "") host_setting_set(ad_sname[s], ad_text(v)); end return FL_NORMAL; end
        case SK_ASK:
            res = host_ask(ad_text(ad_eval(ad_se[s * 8])), ad_se[s * 8 + 1] != 0 ? ad_text(ad_eval(ad_se[s * 8 + 1])) : "", ad_sflag[s]);
            if (ad_err != "") return FL_NORMAL; end
            if (host_cancelled) ad_cancelled = 1; ad_fail("cancelled"); return FL_NORMAL; end
            ad_sc_set(ad_sname[s], ad_str(res)); return FL_NORMAL;
        end
        case SK_SHOW: ad_add_item(s); return FL_NORMAL; end
        case SK_GOTO:
            v = -1;
            for (k = 0; k < ad_npg; k++) if (ad_pg_name[k] == ad_sname[s] && !ad_pg_func[k]) v = k; end end
            if (v < 0) ad_rt_error(ad_sl[s], "there is no page called '" + ad_sname[s] + "'"); return FL_NORMAL; end
            mp = ad_map(); a = ad_sargs[s];
            while (a != 0)
                ad_map_set(mp, ad_ar_name[a], ad_eval(ad_ar_e[a])); if (ad_err != "") return FL_NORMAL; end
                a = ad_ar_next[a];
            end
            ad_goto_page = ad_sname[s]; ad_goto_args = ad_json_text(mp);
            return FL_STOP;
        end
        case SK_FETCH:
            url = ad_text(ad_eval(ad_se[s * 8])); if (ad_err != "") return FL_NORMAL; end
            hdr = ad_hdr_text(ad_shdrs[s]); if (ad_err != "") return FL_NORMAL; end
            method = "GET"; res = "";
            if (ad_se[s * 8 + 1] != 0)
                method = "POST";
                v = ad_eval(ad_se[s * 8 + 1]); if (ad_err != "") return FL_NORMAL; end
                if (ad_vt[v] == VT_MAP || ad_vt[v] == VT_LIST) res = ad_json_text(v); hdr += "Content-Type: application/json" + chr(13) + chr(10); else res = ad_text(v); end
            end
            if (ad_se[s * 8 + 2] != 0) method = ad_text(ad_eval(ad_se[s * 8 + 2])); end
            if (ad_err != "") return FL_NORMAL; end
            if (!ad_http(method, url, hdr, res))
                if (ad_cancelled) return FL_NORMAL; end
                hdr = ad_err; ad_err = ""; ad_rt_error(ad_sl[s], "could not get the data: " + hdr); return FL_NORMAL;
            end
            if (ad_smode[s] == 2) ad_sc_set(ad_sname[s], ad_str(ad_buf_str(0, ad_buf_len))); return FL_NORMAL; end
            v = ad_json_parse();
            if (v < 0) hdr = ad_err; ad_err = ""; ad_rt_error(ad_sl[s], "the answer from the server could not be read: " + hdr); return FL_NORMAL; end
            ad_sc_set(ad_sname[s], v); return FL_NORMAL;
        end
        case SK_TRY:
            k = ad_sc_top; cnt = ad_depth; bd = ad_sc_base;
            fl = ad_exec_block(ad_sbody[s]);
            if (ad_err != "" && !ad_cancelled)
                res = ad_err; ad_err = ""; ad_sc_base = bd; ad_depth = cnt;
                ad_sc_set("error", ad_str(res));
                return ad_exec_block(ad_selse[s]);
            end
            return fl;
        end
    end
    return FL_NORMAL;
end

function ad_exec_block(int s)
private int fl;
begin
    while (s != 0)
        fl = ad_exec_stmt(s);
        if (fl != FL_NORMAL || ad_err != "") return fl; end
        s = ad_snext[s];
    end
    return FL_NORMAL;
end

// ==========================================================================================================
//  API pública
// ==========================================================================================================
// carga y analiza main.addon. 1 = bien; si no, ad_perr explica el fallo
function ad_load(string path)
begin
    ad_loaded = 0;
    ad_values_reset();
    ad_tr_load(path);
    if (!ad_parse_program(path)) return 0; end
    ad_loaded = 1; ad_loaded_path = path;
    return 1;
end

// ejecuta una página. Devuelve 0 = bien (elementos en ad_it_*, cantidad ad_nit), 1 = error (ad_err), 2 = cancelado
function ad_run_page(string page, string argjson)
private int pg, i, v, a, k;
begin
    ad_values_reset();
    ad_err = ""; ad_cancelled = 0; ad_nit = 0; ad_steps = 0; ad_depth = 0; ad_give = 0; ad_goto_page = ""; ad_goto_args = "";
    ad_sc_top = 0; ad_sc_base = 0; ad_buf_len = 0;
    pg = -1;
    for (i = 0; i < ad_npg; i++) if (ad_pg_name[i] == page && !ad_pg_func[i]) pg = i; end end
    if (pg < 0) ad_err = "main.addon: there is no page called '" + page + "'"; return 1; end
    a = -1;
    if (argjson != "")
        ad_str_to_buf(argjson); a = ad_json_parse();
        if (a < 0 || ad_vt[a] != VT_MAP) ad_err = "the values passed to page '" + page + "' could not be read"; return 1; end
    end
    for (i = 0; i < ad_pg_np[pg]; i++)
        v = (a >= 0) ? ad_map_get(a, ad_pg_par[pg * 12 + i]) : -1;
        ad_sc_set(ad_pg_par[pg * 12 + i], v < 0 ? 0 : v);
    end
    ad_exec_block(ad_pg_body[pg]);
    host_message("");
    if (ad_cancelled) return 2; end
    if (ad_err != "") return 1; end
    return 0;
end
