// ==========================================================================================================
//  addon_ui.prg - la parte del reproductor que usa los addons: lista de addons, navegación, ajustes,
//  mensajes y teclado. (El intérprete está en addon.prg.)
// ==========================================================================================================
global
    int    addon_mode;                  // 0 = fuera; 1 = lista de addons instalados; 2 = dentro de un addon
    string addon_dir = "", addon_name = "";
    string as_page[24]; string as_args[24]; int as_depth;          // pila de páginas visitadas
    int    addon_busy;                  // el addon se está ejecutando (esperando red, teclado...)
    string s_amsg = ""; int txt_amsg;   // mensaje del addon / "cargando..."
    int    ask_ok; string ask_text = "";
    int    aset_idx;                    // ajuste que se está editando
    string as_name[48]; string as_val[48]; int as_n; string as_cfg_path = "";
    string entry_aargs[MAX_ENTRIES];    // argumentos (JSON) de una carpeta de addon
    string entry_info[MAX_ENTRIES];     // descripción (para el panel de la derecha)
    string wrap_l[8]; int wrap_n;
    int    addons_ok;
    int    entry_akind[MAX_ENTRIES];    // 1 video, 2 audio, 3 radio (elementos de un addon)
end

declare function string addon_root_user() end
declare function string aset_display(int k) end

// ---------------------------------------------------------------- rutas
function string addon_root_user()
begin
    if (store_dir == "") return ""; end
    return join_path(store_dir, "addons");
end

// ---------------------------------------------------------------- ajustes guardados de cada addon (<almacen>/addons_data/<id>.cfg)
function addon_cfg_load()
private int fh, p; string ln;
begin
    as_n = 0; as_cfg_path = "";
    if (store_dir == "" || ad_i_id == "") return 0; end
    as_cfg_path = join_path(join_path(store_dir, "addons_data"), ad_i_id + ".cfg");
    fh = fopen(as_cfg_path, O_READ);
    if (!fh) return 0; end
    while (!feof(fh) && as_n < 48)
        ln = fgets(fh);
        while (len(ln) > 0 && (substr(ln, len(ln) - 1, 1) == chr(13) || substr(ln, len(ln) - 1, 1) == chr(10))) ln = substr(ln, 0, len(ln) - 1); end
        p = find(ln, "=");
        if (p > 0) as_name[as_n] = substr(ln, 0, p); as_val[as_n] = substr(ln, p + 1); as_n++; end
    end
    fclose(fh);
end

function addon_cfg_save()
private int fh, i;
begin
    if (as_cfg_path == "") return 0; end
    fh = fopen(as_cfg_path, O_WRITE);
    if (!fh) return 0; end
    for (i = 0; i < as_n; i++) fputs(fh, as_name[i] + "=" + as_val[i]); end
    fclose(fh);
end

// ---------------------------------------------------------------- hooks del intérprete
function string host_setting_get(string name)
private int i;
begin
    for (i = 0; i < as_n; i++) if (as_name[i] == name) return as_val[i]; end end
    return chr(1);
end

function host_setting_set(string name, string value)
private int i;
begin
    for (i = 0; i < as_n; i++) if (as_name[i] == name) as_val[i] = value; addon_cfg_save(); return 1; end end
    if (as_n < 48) as_name[as_n] = name; as_val[as_n] = value; as_n++; end
    addon_cfg_save();
    return 1;
end

function host_log(string text)
begin
    say("ADDON " + ad_i_id + ": " + text);
    return 1;
end

function host_message(string text)
begin
    s_amsg = text != "" ? text : tr("s_loading");
    return 1;
end

// un fotograma de interfaz mientras el addon espera (red, teclado, pausas)
function ui_wait_frame()
private int i;
begin
    frame_n++;
    read_input();
    apply_script();
    if (wm_info.exit_status) ad_cancelled = 1; end
    if (modal != M_NONE)
        update_modal();
    elseif (act_press[A_BACK])
        ad_cancelled = 1;                     // ○ cancela lo que esté esperando el addon
    end
    for (i = 0; i < A_COUNT; i++) act_press[i] = 0; end        // lo pulsado aquí ya está gastado (no debe llegar al explorador)
    layout_all();
    apply_texts();
    if (shot_path != "" && frame_n == shot_frame)
        map_save(0, screen_get(), shot_path); say("captura guardada: " + shot_path); exit();
    end
    frame;
    return 1;
end

function string host_ask(string prompt, string def, int secret)
begin
    ask_ok = 0; ask_text = ""; kb_secret_next = secret;
    kb_open(prompt, def, KB_ADDON);
    while (modal != M_NONE && !ad_cancelled) ui_wait_frame(); end
    if (modal != M_NONE) modal = M_NONE; end
    if (!ask_ok) host_cancelled = 1; return ""; end
    host_cancelled = 0;
    return ask_text;
end

// ---------------------------------------------------------------- mensajes de error largos (menú con líneas)
function wrap_text(string t, int maxw, int maxlines)
private int p, n, sp; string ltxt, wd, rest;
begin
    wrap_n = 0; rest = t;
    while (rest != "" && wrap_n < maxlines)
        ltxt = "";
        loop
            sp = find(rest, " ");
            if (sp < 0) wd = rest; rest = ""; else wd = substr(rest, 0, sp); rest = substr(rest, sp + 1); end
            if (ltxt == "") ltxt = wd; elseif (tw(ltxt + " " + wd) <= maxw) ltxt += " " + wd; else rest = wd + (rest != "" ? " " + rest : ""); break; end
            if (rest == "") break; end
        end
        // una palabra más larga que la línea: se corta
        while (tw(ltxt) > maxw && len(ltxt) > 4) rest = substr(ltxt, len(ltxt) - 1) + rest; ltxt = utf8_chop(ltxt); end
        wrap_l[wrap_n] = ltxt; wrap_n++;
    end
    if (rest != "" && wrap_n > 0) wrap_l[wrap_n - 1] = fit_text(wrap_l[wrap_n - 1] + " " + rest, maxw); end
end

// igual que show_error pero con un acceso directo a los ajustes del addon (p. ej. falta el token)
function show_error_settings(string title, string text)
private int i;
begin
    menu_clear();
    wrap_text(text, 900, 6);
    for (i = 0; i < wrap_n; i++) menu_add(wrap_l[i], MA_CANCEL); end
    menu_add(tr("m_addon_settings"), MA_ASETTINGS);
    menu_add(tr("m_back"), MA_CANCEL);
    menu_sel = wrap_n;
    menu_show(title);
end

function show_error(string title, string text)
private int i;
begin
    menu_clear();
    wrap_text(text, 900, 6);
    for (i = 0; i < wrap_n; i++) menu_add(wrap_l[i], MA_CANCEL); end
    menu_add(tr("m_back"), MA_CANCEL);
    menu_sel = wrap_n;
    menu_show(title);
end

// ---------------------------------------------------------------- lista de addons instalados
function addon_scan_root(string root)
private int dh, i, j; string nm, p;
begin
    if (root == "") return 0; end
    dh = diropen(join_path(root, "*"));
    if (!dh) return 0; end
    nm = dirread(dh);
    while (nm != "" && n_entries < MAX_ENTRIES)
        if (nm != "." && nm != ".." && substr(nm, 0, 1) != ".")
            p = join_path(root, nm);
            if (fexists(join_path(p, "main.addon")))
                if (ad_peek_info(join_path(p, "main.addon")))
                    entries[n_entries] = ad_i_name; entry_dir[n_entries] = K_ADDON; entry_url[n_entries] = p; entry_size[n_entries] = 0; entry_logo[n_entries] = fexists(join_path(p, "logo.png")) ? join_path(p, "logo.png") : "";
                    entry_aargs[n_entries] = ""; entry_info[n_entries] = ad_i_desc + (ad_i_author != "" ? "  (" + ad_i_author + ", v" + ad_i_ver + ")" : "");
                    n_entries++;
                end
            end
        end
        nm = dirread(dh);
    end
    dirclose(dh);
end

function read_addons()
private int i, j, t_d; string t_s, t_u, t_i, t_l;
begin
    addon_mode = 1;
    n_entries = 0; sel = 0; top_row = 0; dir_ver++; cur_list = "";
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    addon_scan_root(join_path(cd(), "addons"));        // los que trae el reproductor
    addon_scan_root(addon_root_user());                // los que instala el usuario (por FTP)
    for (i = 2; i < n_entries; i++)                    // orden alfabético
        t_s = entries[i]; t_d = entry_dir[i]; t_u = entry_url[i]; t_i = entry_info[i]; t_l = entry_logo[i]; j = i - 1;
        while (j >= 1 && lcase(t_s) < lcase(entries[j]))
            entries[j + 1] = entries[j]; entry_dir[j + 1] = entry_dir[j]; entry_url[j + 1] = entry_url[j]; entry_info[j + 1] = entry_info[j]; entry_logo[j + 1] = entry_logo[j]; j--;
        end
        entries[j + 1] = t_s; entry_dir[j + 1] = t_d; entry_url[j + 1] = t_u; entry_info[j + 1] = t_i; entry_logo[j + 1] = t_l;
    end
    lbl_ver = -1;
end

// ---------------------------------------------------------------- ejecutar páginas y mostrar sus elementos
function addon_fill_entries()
private int i; string t;
begin
    n_entries = 0; sel = 0; top_row = 0; dir_ver++;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    for (i = 0; i < ad_nit && n_entries < MAX_ENTRIES; i++)
        entries[n_entries] = ad_it_title[i];
        entry_logo[n_entries] = ad_it_logo[i]; entry_size[n_entries] = 0;
        t = ad_it_info[i];
        if (ad_it_year[i] > 0) t += (t != "" ? "  " : "") + "(" + ad_it_year[i] + ")"; end
        if (ad_it_dur[i] > 0) t += (t != "" ? "  " : "") + fmt_time(ad_it_dur[i] * 1000); end
        entry_info[n_entries] = t;
        entry_akind[n_entries] = ad_it_kind[i];
        if (ad_it_kind[i] == 0)
            entry_dir[n_entries] = K_AFOLDER; entry_url[n_entries] = ad_it_page[i]; entry_aargs[n_entries] = ad_it_args[i];
        else
            entry_dir[n_entries] = K_URL; entry_url[n_entries] = ad_it_url[i]; entry_aargs[n_entries] = ad_it_hdr[i];   // en un vídeo, aargs lleva las cabeceras
        end
        n_entries++;
    end
    lbl_ver = -1;
end

// 0 = bien, 1 = error (ya mostrado), 2 = cancelado
function addon_run(string page, string args)
private int rc;
begin
    addon_busy = 1; s_amsg = tr("s_loading");
    rc = ad_run_page(page, args);
    addon_busy = 0; s_amsg = "";
    if (rc == 1)
        if (ad_nst > 0) show_error_settings(addon_name != "" ? addon_name : tr("s_addons"), ad_err);
        else show_error(addon_name != "" ? addon_name : tr("s_addons"), ad_err); end
    end
    return rc;
end

function addon_goto(string page, string args)
private int rc;
begin
    rc = addon_run(page, args);
    if (rc != 0) return rc; end
    if (as_depth < 24) as_page[as_depth] = page; as_args[as_depth] = args; as_depth++; end
    addon_mode = 2; cur_list = "";
    addon_fill_entries();
    return 0;
end

function addon_back()
private int rc;
begin
    if (as_depth <= 1)
        read_addons(); return 1;
    end
    rc = addon_run(as_page[as_depth - 2], as_args[as_depth - 2]);
    if (rc != 0) return rc; end
    as_depth--;
    addon_fill_entries();
    return 0;
end

function addon_open(string dir)
begin
    addon_busy = 0;
    if (!ad_load(join_path(dir, "main.addon")))
        show_error(tr("s_addons"), ad_perr); return 0;
    end
    addon_dir = dir; addon_name = ad_i_name; as_depth = 0;
    addon_cfg_load();
    return addon_goto("home", "");
end

// ---------------------------------------------------------------- ajustes de un addon
function string aset_display(int k)
private int j; string v;
begin
    v = host_setting_get(ad_st_name[k]);
    if (v == chr(1)) v = ad_st_def[k]; end
    if (ad_st_type[k] == "secret") return v == "" ? "-" : "********"; end
    if (ad_st_type[k] == "yesno") return (v == "yes" || v == "true" || v == "1") ? tr("y_yes") : tr("y_no"); end
    return v == "" ? "-" : fit_text(v, 380);
end

function addon_settings_menu(int keep)
private int k;
begin
    menu_clear();
    if (ad_nst == 0)
        menu_add(tr("m_addon_noset"), MA_CANCEL);
    else
        for (k = 0; k < ad_nst && k < 9; k++) menu_add(fit_text(ad_st_label[k], 620) + ": " + aset_display(k), MA_ASET + k); end
    end
    menu_add(tr("m_back"), MA_CANCEL);
    menu_show(tr("mt_addon_settings") + " - " + ad_i_name);
    if (keep < menu_n) menu_sel = keep; end
end

function addon_edit_setting(int k)
private string v; int j;
begin
    aset_idx = k;
    v = host_setting_get(ad_st_name[k]); if (v == chr(1)) v = ad_st_def[k]; end
    if (ad_st_type[k] == "yesno")
        host_setting_set(ad_st_name[k], (v == "yes" || v == "true" || v == "1") ? "no" : "yes");
        addon_settings_menu(k); return 1;
    end
    if (ad_st_type[k] == "choice")
        // pasa a la opción siguiente
        j = find("|" + ad_st_choices[k] + "|", "|" + v + "|");
        v = next_choice(ad_st_choices[k], v);
        host_setting_set(ad_st_name[k], v);
        addon_settings_menu(k); return 1;
    end
    kb_secret_next = (ad_st_type[k] == "secret");
    kb_open(ad_st_label[k], v, KB_ASET);
    return 1;
end

function string next_choice(string choices, string cur)
private int p, q; string first, rest, opt;
begin
    rest = choices; first = "";
    while (rest != "")
        q = find(rest, "|");
        if (q < 0) opt = rest; rest = ""; else opt = substr(rest, 0, q); rest = substr(rest, q + 1); end
        if (first == "") first = opt; end
        if (opt == cur) 
            if (rest == "") return first; end
            q = find(rest, "|");
            if (q < 0) return rest; end
            return substr(rest, 0, q);
        end
    end
    return first;
end

// abre los ajustes del addon cuya carpeta es dir (carga su cabecera completa)
function addon_open_settings(string dir)
begin
    if (!ad_load(join_path(dir, "main.addon")))
        show_error(tr("s_addons"), ad_perr); return 0;
    end
    addon_name = ad_i_name; addon_dir = dir;
    addon_cfg_load();
    addon_settings_menu(0);
    return 1;
end

// ---------------------------------------------------------------- vídeos HLS con cabeceras (Plex...)
// FFmpeg no sabe saltar en estas listas HLS, así que se salta regenerando listas locales que empiezan en el
// segmento pedido (video + audio) y reabriendo.
function string hls_dirname(string url)
private int i;
begin
    i = len(url) - 1;
    while (i > 0 && substr(url, i, 1) != "/") i--; end
    return substr(url, 0, i + 1);
end

function string hls_abs(string base, string ref)
begin
    if (substr(ref, 0, 4) == "http") return ref; end
    return base + ref;
end

// descarga un texto (cabeceras opcionales); "" si falla
function string hls_get(string url, string hdr)
private int st, n;
begin
    st = http_fetch(url, hdr, "GET", "");
    if (st != 200) return ""; end
    n = http_length();
    if (n >= HTTP_MAX) return ""; end
    ad_buf_len = http_read(&ad_buf[0], n);
    return ad_buf_str(0, ad_buf_len);
end

// valor del atributo URI="..." de una linea
function string hls_uri_attr(string ln)
private int a, b;
begin
    a = find(ln, "URI=\"");
    if (a < 0) return ""; end
    a += 5; b = find(ln, "\"", a);
    if (b < 0) return ""; end
    return substr(ln, a, b - a);
end

// lista de medios recortada: empieza en el segmento que contiene target_ms; devuelve ese inicio en ms (-1 = error)
// after=1 (audio): empieza en el primer segmento que arranca a partir de target_ms, para no adelantar el audio al video
function int hls_trim(string url, int target_ms, string outpath, int after)
private string txt, out, ln, base, map, segs; int pos, e, acc, dur, started, startms, need, k;
begin
    txt = "";
    for (k = 0; k < 2; k++) if (hls_ct_url[k] == url) txt = hls_ct_txt[k]; end end
    if (txt == "")
        txt = hls_get(url, "");
        if (txt != "" && len(txt) < 400000)
            k = (url == hls_vurl) ? 0 : 1; hls_ct_url[k] = url; hls_ct_txt[k] = txt;
        end
    end
    if (txt == "") return -1; end
    base = hls_dirname(url);
    out = "#EXTM3U" + chr(10) + "#EXT-X-VERSION:6" + chr(10) + "#EXT-X-TARGETDURATION:10" + chr(10) + "#EXT-X-PLAYLIST-TYPE:VOD" + chr(10);
    pos = 0; acc = 0; started = 0; startms = 0; dur = 0; need = 0; segs = "";
    while (pos < len(txt))
        e = find(txt, chr(10), pos);
        if (e < 0) e = len(txt); end
        ln = substr(txt, pos, e - pos); pos = e + 1;
        while (len(ln) > 0 && substr(ln, len(ln) - 1, 1) == chr(13)) ln = substr(ln, 0, len(ln) - 1); end
        if (substr(ln, 0, 15) == "#EXT-X-MAP:URI=")
            out += "#EXT-X-MAP:URI=\"" + hls_abs(base, hls_uri_attr(ln)) + "\"" + chr(10);
        elseif (substr(ln, 0, 8) == "#EXTINF:")
            dur = (int)(atof(substr(ln, 8)) * 1000);
            need = 1;
            map = ln;
        elseif (ln != "" && substr(ln, 0, 1) != "#" && need)
            need = 0;
            if (!started && (after ? acc >= target_ms - 200 : acc + dur > target_ms)) started = 1; startms = acc; end
            if (started) segs += map + chr(10) + hls_abs(base, ln) + chr(10); end
            acc += dur;
        end
    end
    if (!started) return -1; end
    out += segs + "#EXT-X-ENDLIST" + chr(10);
    if (!http_write(outpath, out)) return -1; end
    return startms;
end

// direcciones de las listas de vídeo y de audio del maestro (se piden una sola vez por reproducción)
function int hls_load_master()
private string m, ln; int pos, e, wantv;
begin
    if (hls_vurl != "") return 1; end
    m = hls_get(hls_url, hls_hdr);
    if (m == "") return 0; end
    hls_aurl = ""; pos = 0; wantv = 0;
    while (pos < len(m))
        e = find(m, chr(10), pos); if (e < 0) e = len(m); end
        ln = substr(m, pos, e - pos); pos = e + 1;
        while (len(ln) > 0 && substr(ln, len(ln) - 1, 1) == chr(13)) ln = substr(ln, 0, len(ln) - 1); end
        if (substr(ln, 0, 17) == "#EXT-X-STREAM-INF") wantv = 1;
        elseif (substr(ln, 0, 23) == "#EXT-X-MEDIA:TYPE=AUDIO" && hls_aurl == "") hls_aurl = hls_uri_attr(ln);
        elseif (wantv && ln != "" && substr(ln, 0, 1) != "#" && hls_vurl == "") hls_vurl = ln; wantv = 0; end
    end
    if (hls_vurl == "") return 0; end
    hls_vurl = hls_abs(hls_dirname(hls_url), hls_vurl);
    if (hls_aurl != "") hls_aurl = hls_abs(hls_dirname(hls_url), hls_aurl); end
    return 1;
end

// salta a ms dentro del total; 1 = hecho (se ha reabierto), 0 = no se pudo (el motor intentará el salto normal)
function int hls_reseek(int ms)
private string m, dir, vf, af, mf; int base, b2, t0;
begin
    t0 = get_timer();
    dir = hls_dir; if (dir == "") dir = "/tmp"; end
    http_trace("reseek a " + ms + " ms");
    if (!hls_load_master()) return 0; end
    http_trace("maestro ok " + (get_timer() - t0) + " ms");
    vf = join_path(dir, "hls_v.m3u8"); af = join_path(dir, "hls_a.m3u8"); mf = join_path(dir, "hls_m.m3u8");
    base = hls_trim(hls_vurl, ms, vf, 0);
    http_trace("trim video -> " + base + "  (" + (get_timer() - t0) + " ms)");
    if (base < 0) return 0; end
    if (hls_aurl != "")
        b2 = hls_trim(hls_aurl, base, af, 0);
        http_trace("trim audio -> " + b2 + "  (" + (get_timer() - t0) + " ms)");
        if (b2 < 0) return 0; end
        m = "#EXTM3U" + chr(10) + "#EXT-X-MEDIA:TYPE=AUDIO,URI=\"" + af + "\",GROUP-ID=\"a\",NAME=\"audio\",DEFAULT=YES,AUTOSELECT=YES" + chr(10);
        m += "#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO=\"a\"" + chr(10) + vf + chr(10);
    else
        m = "#EXTM3U" + chr(10) + "#EXT-X-STREAM-INF:BANDWIDTH=1000000" + chr(10) + vf + chr(10);
    end
    if (!http_write(mf, m)) return 0; end
    pending_title = hls_title; pending_logo = "";
    hls_base = base;
    http_trace("antes de start_video");
    // crear de nuevo el decodificador por hardware de la consola justo despues de liberar el anterior falla de vez en cuando:
    // hasta 720p se reabre por software (sobra para esa resolucion)
    if (vid_h <= 720) video_use_hw(0); http_trace("reabriendo por software"); else http_trace("reabriendo por hardware"); end
    start_video(mf);
    video_use_hw(1);
    http_trace("despues de start_video (" + (get_timer() - t0) + " ms en total)");
    return 1;
end

// Un vídeo con cabeceras ("with header ..." en el addon): el reproductor no puede enviarlas, así que se
// descarga la lista (m3u8) con ellas a un archivo local y se reproduce ese. Devuelve la ruta ("" = error).
function string addon_signed_playlist(string url, string hdr)
private int st; string path;
begin
    st = http_fetch(url, hdr, "GET", "");
    if (st != 200) show_error(addon_name != "" ? addon_name : tr("s_addons"), "could not open the stream (" + (st > 0 ? "error " + st : http_error()) + ")"); return ""; end
    if (http_length() < HTTP_MAX) ad_buf_len = http_read(&ad_buf[0], http_length()); else ad_buf_len = 0; end
    // se guarda desde C (la misma vista del disco que usa FFmpeg); si el almacén no sirve, /tmp
    hls_dir = store_dir != "" ? store_dir : "/tmp";
    path = join_path(hls_dir, "stream.m3u8");
    if (!http_save(path)) hls_dir = "/tmp"; path = "/tmp/stream.m3u8"; if (!http_save(path)) path = ""; end end
    if (path != "")
        if (find(ad_buf_str(0, ad_buf_len), "#EXT-X-STREAM-INF") >= 0) hls_url = url; hls_hdr = hdr; hls_base = 0; hls_total = 0; end
        return path;
    end
    show_error(tr("s_addons"), "could not save the stream list");
    return "";
end
