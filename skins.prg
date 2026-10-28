// ==========================================================================================================
//  skins.prg - aspectos (skins) del reproductor. Un aspecto es una carpeta con un skin.cfg y sus imagenes (y, si quiere,
//  una fuente): los de fabrica (res/skins/<id>) y los del usuario (<almacen>/skins/<id>, o ./skins/<id>) usan el mismo formato.
//  El formato esta explicado en SKINS.md. Aqui se leen, se cargan y se animan sus capas.
// ==========================================================================================================
const
    SK_MAX = 48;                          // aspectos que se listan
    SL_MAX = 12;                          // capas de un aspecto
    SK_DL_MAX = 24;                       // ficheros que puede pedir un aspecto al instalarlo desde una URL
    FXE_STATIC = 1; FXE_BOB = 2; FXE_SWAY = 3; FXE_DRIFT = 4; FXE_RISE = 5; FXE_TWINKLE = 6; FXE_SCROLL = 7; FXE_PERSP = 8; FXE_SHOOT = 9;
end

global
    string sk_id[SK_MAX]; string sk_dir[SK_MAX]; string sk_nm[SK_MAX]; int sk_user[SK_MAX]; int sk_n;
    string skin_pref = "";                // id guardado en config.cfg
    string skin_font = "";                // fuente del aspecto actual ("" = la de la interfaz)
    int    skin_gen;                      // cambia cada vez que se carga un aspecto: obliga a rehacer los textos si cambia la fuente
    int    sl_n;                          // capas del aspecto actual
    int    sl_g[SL_MAX]; int sl_fx[SL_MAX]; int sl_cnt[SL_MAX]; int sl_slot[SL_MAX]; int sl_w[SL_MAX];
    int    sl_x[SL_MAX]; int sl_y[SL_MAX]; int sl_y2[SL_MAX]; int sl_sz[SL_MAX]; int sl_sz2[SL_MAX]; int sl_al[SL_MAX]; int sl_al2[SL_MAX];
    int    sl_amp[SL_MAX]; int sl_per[SL_MAX]; int sl_per2[SL_MAX]; int sl_dx[SL_MAX]; int sl_dy[SL_MAX]; int sl_x0[SL_MAX];
    int    sl_spd[SL_MAX]; int sl_dspd[SL_MAX]; int sl_loop[SL_MAX]; int sl_add[SL_MAX]; int sl_front[SL_MAX]; int sl_hz[SL_MAX];
    int    sl_tilt[SL_MAX]; int sl_pulse[SL_MAX]; int sl_breathe[SL_MAX]; int sl_vx[SL_MAX]; int sl_vy[SL_MAX]; int sl_ang[SL_MAX];
    int    sl_y0[SL_MAX]; int sl_y1[SL_MAX]; int sl_len[SL_MAX];
    string sl_file[SL_MAX]; string sk_bgfile = ""; string sk_pillfile = ""; string sk_fontfile = "";
    string sk_dl[SK_DL_MAX]; int sk_dl_n;
    int    skin_f5;
end

// ---- lectura de valores de una linea "clave=valor clave=valor ..."
function string sk_kvs(string ln, string key)
private string s, r; int p, q;
begin
    s = " " + ln + " ";
    p = find(s, " " + key + "=");
    if (p < 0) return ""; end
    p += len(key) + 2;
    r = substr(s, p);
    q = find(r, " ");
    if (q < 0) return r; end
    return substr(r, 0, q);
end

// numero con hasta dos decimales, multiplicado por 100 ("2.6" -> 260)
function int sk_num100(string v)
private int i, c, neg, ip, fp, fd, seen, r;
begin
    for (i = 0; i < len(v); i++)
        c = asc(substr(v, i, 1));
        if (c == 45 && i == 0) neg = 1;
        elseif (c == 46) seen = 1;
        elseif (c >= 48 && c <= 57)
            if (!seen) ip = ip * 10 + (c - 48); elseif (fd < 2) fp = fp * 10 + (c - 48); fd++; end
        else break; end
    end
    if (fd == 1) fp *= 10; end
    r = ip * 100 + fp;
    if (neg) r = -r; end
    return r;
end

// posicion del guion de un rango "a-b" (un guion inicial es un signo), o -1
function int sk_dash(string v)
private int i;
begin
    for (i = 1; i < len(v); i++) if (substr(v, i, 1) == "-") return i; end end
    return -1;
end

function int sk_lo100(string ln, string key, int def100)
private string v; int p;
begin
    v = sk_kvs(ln, key);
    if (v == "") return def100; end
    p = sk_dash(v);
    if (p > 0) v = substr(v, 0, p); end
    return sk_num100(v);
end

function int sk_hi100(string ln, string key, int def100)
private string v; int p;
begin
    v = sk_kvs(ln, key);
    if (v == "") return def100; end
    p = sk_dash(v);
    if (p > 0) return sk_num100(substr(v, p + 1)); end
    return sk_num100(v);
end

function int sk_int(string ln, string key, int def)
begin
    return sk_lo100(ln, key, def * 100) / 100;
end

// color "RRGGBB" -> numero
function int sk_hex(string v, int def)
private int i, c, r;
begin
    if (len(v) != 6) return def; end
    for (i = 0; i < 6; i++)
        c = asc(lcase(substr(v, i, 1)));
        if (c >= 48 && c <= 57) c -= 48; elseif (c >= 97 && c <= 102) c -= 87; else return def; end
        r = r * 16 + c;
    end
    return r;
end

function string sk_trim(string s)
private int a, b;
begin
    a = 0; b = len(s);
    while (a < b && (substr(s, a, 1) == " " || substr(s, a, 1) == chr(9))) a++; end
    while (b > a && (substr(s, b - 1, 1) == " " || substr(s, b - 1, 1) == chr(13) || substr(s, b - 1, 1) == chr(10) || substr(s, b - 1, 1) == chr(9))) b--; end
    return substr(s, a, b - a);
end

// un nombre de fichero de un aspecto: solo letras, numeros, . _ - y sin ".." (no puede salirse de su carpeta)
function int sk_safe_name(string f)
private int i, c;
begin
    if (f == "" || len(f) > 60 || find(f, "..") >= 0 || substr(f, 0, 1) == ".") return 0; end
    for (i = 0; i < len(f); i++)
        c = asc(lcase(substr(f, i, 1)));
        if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 46 || c == 95 || c == 45)) return 0; end
    end
    return 1;
end

function int sk_effect_id(string e)
begin
    e = lcase(e);
    if (e == "static") return FXE_STATIC; end
    if (e == "bob") return FXE_BOB; end
    if (e == "sway") return FXE_SWAY; end
    if (e == "drift") return FXE_DRIFT; end
    if (e == "rise") return FXE_RISE; end
    if (e == "twinkle") return FXE_TWINKLE; end
    if (e == "scroll") return FXE_SCROLL; end
    if (e == "perspective") return FXE_PERSP; end
    if (e == "shoot") return FXE_SHOOT; end
    return 0;
end

// Lee un skin.cfg. Con load = 0 solo recoge el nombre; con load = 1 rellena el aspecto actual (colores, fuente, capas)
function int sk_parse(string path, string dir, int load)
private int fh, p, n, slot; string ln, k, v, fl, tail;
begin
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    n = 0; slot = 0;
    if (load) sl_n = 0; sk_bgfile = ""; sk_pillfile = ""; sk_fontfile = ""; txc = 8589934336; txs = 8589934336; end
    while (!feof(fh) && n < 400)
        n++;
        ln = sk_trim(fgets(fh));
        if (ln != "" && substr(ln, 0, 1) != "#")
            p = find(ln, "=");
            if (p > 0)
                k = lcase(sk_trim(substr(ln, 0, p))); v = sk_trim(substr(ln, p + 1));
                p = find(v, " #"); if (p >= 0) v = sk_trim(substr(v, 0, p)); end                  // comentario al final de la linea
                if (k == "name" && !load && sk_nm[sk_n] == "") sk_nm[sk_n] = v; end
                if (load)
                    if (k == "text") txc = 4294967296 + (sk_hex(v, 16777215) << 8); end
                    if (k == "select") txs = 4294967296 + (sk_hex(v, 16777215) << 8); end
                    if (k == "background") sk_bgfile = v; end
                    if (k == "pill") sk_pillfile = v; end
                    if (k == "font") sk_fontfile = v; end
                    if (k == "layer" && sl_n < SL_MAX)
                        p = find(v, " ");
                        if (p < 0) fl = v; tail = ""; else fl = substr(v, 0, p); tail = substr(v, p + 1); end
                        sl_fx[sl_n] = sk_effect_id(sk_kvs(tail, "effect"));
                        if (sl_fx[sl_n] > 0 && sk_safe_name(fl))
                            sl_file[sl_n] = fl;
                            sl_cnt[sl_n] = sk_int(tail, "count", 1); if (sl_cnt[sl_n] < 1) sl_cnt[sl_n] = 1; end
                            if (sl_cnt[sl_n] > 40) sl_cnt[sl_n] = 40; end
                            sl_x[sl_n] = sk_int(tail, "x", 640); sl_y[sl_n] = sk_lo100(tail, "y", 36000) / 100; sl_y2[sl_n] = sk_hi100(tail, "y", 36000) / 100;
                            sl_sz[sl_n] = sk_lo100(tail, "size", 10000) / 100; sl_sz2[sl_n] = sk_hi100(tail, "size", 10000) / 100;
                            sl_al[sl_n] = sk_lo100(tail, "alpha", 25500) / 100; sl_al2[sl_n] = sk_hi100(tail, "alpha", 25500) / 100;
                            sl_amp[sl_n] = sk_int(tail, "amp", 10);
                            sl_per[sl_n] = sk_lo100(tail, "period", 400); sl_per2[sl_n] = sk_hi100(tail, "period", 400);
                            if (sl_per[sl_n] < 20) sl_per[sl_n] = 20; end
                            if (sl_per2[sl_n] < sl_per[sl_n]) sl_per2[sl_n] = sl_per[sl_n]; end
                            sl_dx[sl_n] = sk_int(tail, "dx", 250); sl_dy[sl_n] = sk_int(tail, "dy", 80); sl_x0[sl_n] = sk_int(tail, "x0", -450);
                            sl_spd[sl_n] = sk_int(tail, "speed", 40); sl_dspd[sl_n] = sk_int(tail, "dspeed", 0); sl_loop[sl_n] = sk_int(tail, "loop", 2100); if (sl_loop[sl_n] < 1) sl_loop[sl_n] = 1; end
                            sl_add[sl_n] = sk_int(tail, "add", 0); sl_front[sl_n] = sk_int(tail, "front", 0); sl_hz[sl_n] = sk_int(tail, "horizon", 373);
                            sl_tilt[sl_n] = sk_lo100(tail, "tilt", 0) * 10; sl_pulse[sl_n] = sk_int(tail, "pulse", 0); sl_breathe[sl_n] = sk_int(tail, "breathe", 0);
                            sl_vx[sl_n] = sk_int(tail, "vx", 20); sl_vy[sl_n] = sk_int(tail, "vy", 8); sl_ang[sl_n] = sk_lo100(tail, "angle", 0) * 10;
                            sl_y0[sl_n] = sk_int(tail, "y0", 740); sl_y1[sl_n] = sk_int(tail, "y1", -40); sl_len[sl_n] = sk_int(tail, "length", 46); if (sl_len[sl_n] < 1) sl_len[sl_n] = 1; end
                            sl_slot[sl_n] = slot;
                            if (sl_fx[sl_n] == FXE_STATIC || sl_fx[sl_n] == FXE_BOB || sl_fx[sl_n] == FXE_SCROLL || sl_fx[sl_n] == FXE_SHOOT) sl_cnt[sl_n] = 1; end
                            slot += sl_cnt[sl_n];
                            if (slot <= FX_N) sl_n++; end
                        end
                    end
                end
            end
        end
    end
    fclose(fh);
    return 1;
end

// ---- lista de aspectos: el clasico, los de fabrica y los que haya en las carpetas del usuario
function int sk_register(string sid, string sdir, string sname, int suser)
begin
    if (sk_n >= SK_MAX) return 0; end
    sk_id[sk_n] = sid; sk_dir[sk_n] = sdir; sk_nm[sk_n] = sname; sk_user[sk_n] = suser;
    sk_n++;
    return 1;
end

function int sk_scan_root(string root)
private int dh; string nm, p, shown;
begin
    if (root == "") return 0; end
    dh = diropen(join_path(root, "*"));
    if (!dh) return 0; end
    nm = dirread(dh);
    while (nm != "" && sk_n < SK_MAX)
        if (nm != "." && nm != ".." && substr(nm, 0, 1) != "." && sk_safe_name(nm))
            p = join_path(root, nm);
            if (fexists(join_path(p, "skin.cfg")))
                sk_nm[sk_n] = "";
                sk_parse(join_path(p, "skin.cfg"), p, 0);
                shown = sk_nm[sk_n]; if (shown == "") shown = nm; end
                sk_register(nm, p, shown, 1);
            end
        end
        nm = dirread(dh);
    end
    dirclose(dh);
    return 1;
end

function int skin_scan()
private int i; string keep;
begin
    keep = (sk_n > 0 && skin >= 0 && skin < sk_n) ? sk_id[skin] : skin_pref;
    sk_n = 0;
    sk_register("classic", "", "", 0);
    sk_register("ps", "res/skins/ps", "", 0); sk_register("aurora", "res/skins/aurora", "", 0); sk_register("sunset", "res/skins/sunset", "", 0);
    sk_register("neon", "res/skins/neon", "", 0); sk_register("embers", "res/skins/embers", "", 0); sk_register("cosmos", "res/skins/cosmos", "", 0);
    if (store_dir != "") sk_scan_root(join_path(store_dir, "skins")); end
    sk_scan_root("skins");
    if (keep != "")
        for (i = 0; i < sk_n; i++) if (sk_id[i] == keep) skin = i; end end
        if (sk_id[skin] != keep) skin = 1; end
    end
    if (skin < 0 || skin >= sk_n) skin = 1; end
    return 1;
end

function string skin_name()
begin
    if (skin <= 0 || skin >= sk_n) return tr("skin_classic"); end
    if (sk_user[skin]) return sk_nm[skin]; end
    return tr("skin_" + sk_id[skin]);
end

function string skin_id()
begin
    if (skin < 0 || skin >= sk_n) return "ps"; end
    return sk_id[skin];
end

// ---- carga: libera lo del aspecto anterior y lee el elegido
function skin_unload()
private int k;
begin
    if (skin_loaded <= 0) return 0; end
    if (g_bg_ps > 0) map_unload(0, g_bg_ps); end
    if (g_pill > 0) map_unload(0, g_pill); end
    for (k = 0; k < sl_n; k++) if (sl_g[k] > 0) map_unload(0, sl_g[k]); end end
    g_bg_ps = 0; g_pill = 0; sl_n = 0;
end

function skin_load()
private int k; string d;
begin
    if (skin_loaded == skin) return 0; end
    skin_unload();
    skin_loaded = skin; skin_gen++;
    skin_font = ""; txc = 8589934336; txs = 8589934336; sl_n = 0;
    if (skin <= 0 || skin >= sk_n) return 0; end
    d = sk_dir[skin];
    if (!sk_parse(join_path(d, "skin.cfg"), d, 1)) return 0; end
    if (sk_safe_name(sk_bgfile)) g_bg_ps = map_load(join_path(d, sk_bgfile)); hires(g_bg_ps); end
    if (sk_safe_name(sk_pillfile)) g_pill = map_load(join_path(d, sk_pillfile)); hires(g_pill); end
    if (g_pill <= 0) g_pill = map_load("res/skins/ps/pill.png"); hires(g_pill); end
    if (sk_safe_name(sk_fontfile) && fexists(join_path(d, sk_fontfile))) skin_font = join_path(d, sk_fontfile); end
    for (k = 0; k < sl_n; k++)
        sl_g[k] = map_load(join_path(d, sl_file[k])); hires(sl_g[k]);
        sl_w[k] = sl_g[k] > 0 ? graphic_info(0, sl_g[k], G_WIDTH) : 0;
    end
end

// cambia al siguiente (o anterior) aspecto, recarga y guarda
function skin_step(int d)
begin
    skin = (skin + sk_n + (d < 0 ? -1 : 1)) % sk_n;
    skin_apply();
end

function skin_apply()
begin
    skin_load();
    apply_lang_font();
    cfg_save();
end

// ---- animacion
function int sn(int a, int amp)
begin
    return sin(a % 360000) * amp;
end

// una pieza animada: grafico, posicion logica, tamano %, transparencia, z y si suma luz
function fx(int n, int g, int px, int py, int sz, int a, int zz, int add)
begin
    if (a < 0) a = 0; end
    if (a > 255) a = 255; end
    if (sz < 1) sz = 1; end
    put(S_FX + n, g, px, py, sz, a, zz);
    if (add) spr_fl[S_FX + n] = B_ABLEND; end
end

function sk_draw_layer(int L, int t)
private int k, s, g, zz, add, ang, u, p, ph, a, sz, xp, spd, cyc, per, cnt, lo, hi, seed;
begin
    g = sl_g[L]; if (g <= 0) return 0; end
    add = sl_add[L]; cnt = sl_cnt[L]; s = S_FX + sl_slot[L]; zz = (sl_front[L] ? 20 : 28) - L;
    switch (sl_fx[L])
        case FXE_STATIC:
            fx(sl_slot[L], g, sl_x[L], sl_y[L], sl_sz[L], sl_al[L], zz, add);
        end
        case FXE_BOB:
            ang = t * 6000000 / sl_per[L];
            fx(sl_slot[L], g, sl_x[L], sl_y[L] + sn(ang, sl_amp[L]), sl_sz[L] + sn(ang * 2, sl_pulse[L]), sl_al[L], zz, add);
        end
        case FXE_SWAY:
            for (k = 0; k < cnt; k++)
                ang = t * 6000000 / sl_per[L] + k * 70000 + L * 37000;
                fx(sl_slot[L] + k, g, sl_x[L] + k * sl_dx[L] + sn(ang, sl_amp[L]), sl_y[L], sl_sz[L] + sn(ang * 4 / 5 + k * 40000, sl_pulse[L]),
                   sl_al[L] + sn(ang * 3 / 2 + k * 13000, sl_breathe[L]), zz, add);
                spr_sizey[S_FX + sl_slot[L] + k] = sl_sz[L] + sn(ang * 2 / 3, sl_pulse[L] / 3);
                spr_angle[S_FX + sl_slot[L] + k] = sn(ang * 3 / 4 + k * 20000, sl_tilt[L]);
            end
        end
        case FXE_DRIFT:
            for (k = 0; k < cnt; k++)
                spd = sl_spd[L] + k * sl_dspd[L];
                xp = (k * sl_dx[L] + t * spd / 60) % sl_loop[L];
                fx(sl_slot[L] + k, g, sl_x0[L] + xp, sl_y[L] + k * sl_dy[L] + sn(t * 70 + k * 100000, 8), sl_sz[L], sl_al[L], zz - k, add);
            end
        end
        case FXE_RISE:
            for (k = 0; k < cnt; k++)
                seed = k + L * 31;
                lo = sl_per[L] * 60 / 100; hi = sl_per2[L] * 60 / 100;
                p = lo + (hi > lo ? (seed * 53) % (hi - lo) : 0);
                ph = (t + seed * 97) % p;
                u = ph * 1000 / p;
                if (u < 150) a = u * 255 / 150; elseif (u > 650) a = (1000 - u) * 255 / 350; else a = 255; end
                a = a * (180 + sn(t * 900 + seed * 71000, 75)) / 255 * sl_al[L] / 255;
                sz = sl_sz[L] + (sl_sz2[L] > sl_sz[L] ? (seed * 37) % (sl_sz2[L] - sl_sz[L]) : 0);
                fx(sl_slot[L] + k, g, ((seed * 191) % 1280) + sn(t * 500 + seed * 70000, sl_amp[L]), sl_y0[L] + (sl_y1[L] - sl_y0[L]) * u / 1000, sz, a, zz, add);
            end
        end
        case FXE_TWINKLE:
            for (k = 0; k < cnt; k++)
                seed = k + L * 17;
                per = sl_per[L] + (seed % 3) * (sl_per2[L] - sl_per[L]) / 2;
                ang = t * 6000000 / per + seed * 53000;
                a = sl_al[L] + (sl_al2[L] - sl_al[L]) * (1000 + sn(ang, 1000)) / 2000;
                sz = sl_sz[L] + (seed % 5) * (sl_sz2[L] - sl_sz[L]) / 4;
                fx(sl_slot[L] + k, g, (seed * 347) % 1280, sl_y[L] + (sl_y2[L] > sl_y[L] ? (seed * 211) % (sl_y2[L] - sl_y[L]) : 0), sz, a, zz, add);
            end
        end
        case FXE_SCROLL:
            put(s, g, sl_w[L] / 3, sl_y[L], 100, sl_al[L], zz);
            spr_xr[s] = -((t * sl_spd[L] / 60) % sl_loop[L]);
            if (add) spr_fl[s] = B_ABLEND; end
        end
        case FXE_PERSP:
            per = sl_per[L] * 60 / 100; if (per < 1) per = 1; end
            for (k = 0; k < cnt; k++)
                u = (t * 1000 / per + k * 1000 / cnt) % 1000;
                fx(sl_slot[L] + k, g, 640, sl_hz[L] + (720 - sl_hz[L]) * (u * u / 1000) / 1000, 40 + u / 5, u * sl_al[L] / 1000, zz, add);
            end
        end
        case FXE_SHOOT:
            per = sl_per[L] * 60 / 100; if (per <= sl_len[L]) per = sl_len[L] + 1; end
            ph = t % per; cyc = t / per;
            if (ph < sl_len[L])
                fx(sl_slot[L], g, 180 + (cyc * 263) % 700 + ph * sl_vx[L], 50 + (cyc * 131) % 280 + ph * sl_vy[L], 100, sn(ph * 180000 / sl_len[L], 255), zz, add);
                spr_angle[s] = sl_ang[L];
            end
        end
    end
end

// Fondo del aspecto elegido: su imagen y sus capas animadas
function draw_bg()
private int L;
begin
    if (!skin) return 0; end
    put(S_BG, g_bg_ps, SW / 2, SH / 2, 100, 255, 30);
    for (L = 0; L < sl_n; L++) sk_draw_layer(L, frame_n); end
    wave_f = frame_n;
end

// ---- instalar un aspecto desde una direccion web: la carpeta (o su skin.cfg) con sus imagenes al lado
function sk_collect_files(string path)
private int fh, p, n; string ln, k, v;
begin
    sk_dl_n = 0;
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    while (!feof(fh) && n < 400)
        n++;
        ln = sk_trim(fgets(fh));
        p = find(ln, "=");
        if (p > 0 && substr(ln, 0, 1) != "#")
            k = lcase(sk_trim(substr(ln, 0, p))); v = sk_trim(substr(ln, p + 1));
            p = find(v, " #"); if (p >= 0) v = sk_trim(substr(v, 0, p)); end
            if (k == "layer") p = find(v, " "); if (p > 0) v = substr(v, 0, p); end end
            if ((k == "background" || k == "pill" || k == "font" || k == "layer") && sk_safe_name(v) && sk_dl_n < SK_DL_MAX) sk_dl[sk_dl_n] = v; sk_dl_n++; end
        end
    end
    fclose(fh);
    return 1;
end

function int skin_install_url(string url)
private string base, sid, dir, tmp, ch, root; int i, st, p, ok;
begin
    if (store_dir == "") toast(tr("t_no_store")); return 0; end
    if (len(url) < 9 || url == "https://") return 0; end
    if (lcase(substr(url, len(url) - 8, 8)) == "skin.cfg") url = substr(url, 0, len(url) - 8); end
    if (substr(url, len(url) - 1, 1) != "/") url += "/"; end
    base = url;
    toast(tr("s_loading")); frame;
    st = http_fetch(base + "skin.cfg", "", "GET", "");
    tmp = join_path(store_dir, "skin_nuevo.tmp");
    if (st != 200 || !http_save(tmp))
        show_error(tr("st_skin_install"), tr("t_addon_fail") + ": " + (st > 0 ? tr("t_store_http") + " " + st : http_error())); return 0;
    end
    if (!sk_collect_files(tmp) || sk_dl_n == 0) fremove(tmp); show_error(tr("st_skin_install"), tr("t_skin_bad")); return 0; end
    // el id es el nombre de la carpeta de la direccion
    sid = substr(base, 0, len(base) - 1); p = len(sid) - 1;
    while (p >= 0 && substr(sid, p, 1) != "/") p--; end
    sid = substr(sid, p + 1);
    dir = "";
    for (i = 0; i < len(sid); i++)
        ch = lcase(substr(sid, i, 1));
        if ((ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-" || ch == "_") dir += ch; end
    end
    if (dir == "") dir = "skin"; end
    root = join_path(store_dir, "skins"); mkdir(root);
    dir = join_path(root, dir); mkdir(dir);
    ok = 1;
    for (i = 0; i < sk_dl_n && ok; i++)
        toast(tr("s_loading") + " " + sk_dl[i]); frame;
        st = http_fetch(base + sk_dl[i], "", "GET", "");
        if (st != 200 || !http_save(join_path(dir, sk_dl[i]))) ok = 0; end
    end
    if (!ok) fremove(tmp); show_error(tr("st_skin_install"), tr("t_skin_bad")); return 0; end
    if (http_fetch(base + "skin.cfg", "", "GET", "") == 200) http_save(join_path(dir, "skin.cfg")); end
    fremove(tmp);
    skin_scan();
    toast(tr("t_skin_installed"));
    return 1;
end
