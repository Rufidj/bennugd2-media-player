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
    int    ad_replay, ask_memo_n; string ask_memo_p[8]; string ask_memo_v[8];     // respuestas ya dadas, para volver atras sin volver a preguntar
    int    aset_idx;                    // ajuste que se está editando
    string as_name[48]; string as_val[48]; int as_n; string as_cfg_path = "";
    string entry_aargs[MAX_ENTRIES];    // argumentos (JSON) de una carpeta de addon
    string entry_info[MAX_ENTRIES];     // descripción (para el panel de la derecha)
    string wrap_l[8]; int wrap_n;
    int    addons_ok;
    int    entry_dur[MAX_ENTRIES];      // segundos, si el addon los dio
    int    entry_akind[MAX_ENTRIES];    // 1 video, 2 audio, 3 radio (elementos de un addon)
    // ---- tienda: una entrada por addon del repositorio
    int    store_mode;                  // 1 = la tienda está en pantalla
    int    store_load;                  // 1 = hay que pedir la lista (en el fotograma siguiente)
    string store_base = "";             // raíz de la tienda (vacío = la del repositorio oficial)
    string entry_sver[MAX_ENTRIES];     // versión que hay en la tienda
    string entry_sfiles[MAX_ENTRIES];   // ficheros que hay que descargar ("main.addon,logo.png")
    string entry_siver[MAX_ENTRIES];    // versión instalada ("" = no está instalado)
    int    entry_skind[MAX_ENTRIES];    // 1 = lista de TV/radio de la tienda (0 = addon)
    string entry_surl[MAX_ENTRIES];     // dirección de origen de una lista
    string entry_sauth[MAX_ENTRIES];    // cuenta que pide la lista ("mode=basic" o "mode=form;login=...")
    int    store_cached;                // 1 = la lista se sacó de la copia guardada (sin conexión)
    int    store_net_err;               // estado HTTP del último intento (para el mensaje de error)
    // instalación en curso (una descarga por fotograma, para que la pantalla siga viva)
    int    store_job;                   // 1 = instalando
    int    store_ji, store_jn, store_jrow, store_jerr; string store_jid, store_jdir, store_jfiles, store_jname;
    int    store_jkind;                 // 0 = addon, 1 = lista de TV/radio
    string store_jurl, store_jfile;     // lista: de dónde se baja y con qué nombre se guarda
    int    store_jreq, store_jcur;      // una descarga en segundo plano en curso, y el numero de fichero que baja
    int    dl_job;                      // 1 = descargando un video a "Descargas"
    string dl_path, dl_title;
    int    dl_pick;                     // entrada para la que se esta eligiendo el formato
    // ventana de progreso propia (la barra del sistema de la PS5 no se puede usar desde un titulo)
    int    ov_on, ov_pct, ov_cancel;    // visible / porcentaje 0-100 / con boton de cancelar
    string ov_title = "", s_ovt = "", s_ovp = "", s_ovh = "";
    string ov_sub = "", ov_btn = "";             // texto bajo la barra (si no, el porcentaje) y texto del boton (si no, "Cancelar")
    int    txt_ovt, txt_ovp, txt_ovh;
    string wid_name = "";                      // ajuste que edita el campo de texto abierto
    string store_seen[64]; int store_seen_n;   // carpetas ya listadas (el addon del usuario manda sobre el que trae el reproductor)
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
    draw_cursor();
    apply_texts();
    if (shot_path != "" && frame_n == shot_frame)
        map_save(0, screen_get(), shot_path); say("captura guardada: " + shot_path); exit();
    end
    frame;
    return 1;
end

function string host_ask(string prompt, string def, int secret)
private int i;
begin
    // al volver atras a una pagina que pedia un texto (una busqueda) se reutiliza lo que se escribio, sin abrir otra vez el teclado
    if (ad_replay && !secret)
        for (i = 0; i < ask_memo_n; i++)
            if (ask_memo_p[i] == prompt) host_cancelled = 0; return ask_memo_v[i]; end
        end
    end
    ask_ok = 0; ask_text = ""; kb_secret_next = secret;
    kb_open(prompt, def, KB_ADDON);
    while (modal != M_NONE && !ad_cancelled) ui_wait_frame(); end
    if (modal != M_NONE) modal = M_NONE; end
    if (!ask_ok) host_cancelled = 1; return ""; end
    host_cancelled = 0;
    if (!secret)
        for (i = 0; i < ask_memo_n; i++) if (ask_memo_p[i] == prompt) break; end end
        if (i < 8) ask_memo_p[i] = prompt; ask_memo_v[i] = ask_text; if (i == ask_memo_n) ask_memo_n++; end end
    end
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
// El addon que instala el usuario manda sobre el que trae el reproductor: si la carpeta ya se ha
// visto (mismo nombre) no se lista otra vez, así actualizar un addon del reproductor no lo duplica.
function addon_seen(string folder)
private int i;
begin
    for (i = 0; i < store_seen_n; i++)
        if (store_seen[i] == folder) return 1; end
    end
    if (store_seen_n < 64) store_seen[store_seen_n] = folder; store_seen_n++; end
    return 0;
end

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
            if (fexists(join_path(p, "main.addon")) && !addon_seen(nm))
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
    addon_mode = 1; store_mode = 0;
    n_entries = 0; sel = 0; top_row = 0; dir_ver++; cur_list = "";
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    store_seen_n = 0;
    addon_scan_root(addon_root_user());                // los que instala el usuario (tienda o FTP): mandan
    addon_scan_root(join_path(cd(), "addons"));        // los que trae el reproductor
    for (i = 2; i < n_entries; i++)                    // orden alfabético
        t_s = entries[i]; t_d = entry_dir[i]; t_u = entry_url[i]; t_i = entry_info[i]; t_l = entry_logo[i]; j = i - 1;
        while (j >= 1 && lcase(t_s) < lcase(entries[j]))
            entries[j + 1] = entries[j]; entry_dir[j + 1] = entry_dir[j]; entry_url[j + 1] = entry_url[j]; entry_info[j + 1] = entry_info[j]; entry_logo[j + 1] = entry_logo[j]; j--;
        end
        entries[j + 1] = t_s; entry_dir[j + 1] = t_d; entry_url[j + 1] = t_u; entry_info[j + 1] = t_i; entry_logo[j + 1] = t_l;
    end
    auto_grid();
    lbl_ver = -1;
end


// ---------------------------------------------------------------- botones, casillas, selectores y campos de texto de un addon
// el valor de un ajuste (el de su definicion si el usuario no lo ha tocado)
function string addon_setting_text(int k)
private string v;
begin
    v = host_setting_get(ad_st_name[k]);
    if (v == chr(1)) v = ad_st_def[k]; end
    return v;
end

// el texto de la fila: "[x] titulo", "titulo:  valor"...
function string addon_widget_title(int i)
private string v; int k;
begin
    k = ad_it_flag[i];
    switch (ad_it_kind[i])
        case 5:
            v = addon_setting_text(k);
            return ((v == "yes" || v == "true" || v == "1") ? "[x]  " : "[ ]  ") + ad_it_title[i];
        end
        case 6, 7:
            v = addon_setting_text(k);
            if (ad_st_type[k] == "secret") v = v == "" ? "-" : "*****"; elseif (v == "") v = "-"; end
            return ad_it_title[i] + ":  " + fit_text(v, 300);
        end
        case 8: return ucase(ad_it_title[i]); end
    end
    return ad_it_title[i];
end

// las cabeceras no se pueden elegir: el cursor pasa de largo
function skip_headers(int dir)
private int k;
begin
    if (addon_mode != 2 || sel < 0 || sel >= n_entries) return 0; end
    if (dir == 0) dir = 1; end
    k = 0;
    while (sel >= 0 && sel < n_entries && entry_dir[sel] == K_AWIDGET && entry_akind[sel] == 8 && k < n_entries)
        sel += dir > 0 ? 1 : -1; k++;
    end
    if (sel >= n_entries) sel = n_entries - 1; skip_headers(-1); end
    if (sel < 0) sel = 0; end
    if (sel < top_row) top_row = sel; end
    if (sel >= top_row + ROWS) top_row = sel - ROWS + 1; end
end

// vuelve a ejecutar la pagina que se ve (tras cambiar un valor), dejando el cursor donde estaba
function int addon_refresh()
private int s0, t0, rc;
begin
    s0 = sel; t0 = top_row;
    rc = addon_run(as_page[as_depth - 1], as_args[as_depth - 1]);
    if (rc != 0) return rc; end
    addon_fill_entries();
    sel = s0; top_row = t0;
    if (sel >= n_entries) sel = n_entries - 1; end
    if (sel < 0) sel = 0; end
end

// un boton: se ejecuta su pagina; si esta termina con "go to", se va a esa pagina; si no, se refresca la actual
function addon_do(string page, string args)
private int rc; string gp, ga;
begin
    rc = addon_run(page, args);
    if (rc == 1) return 0; end
    if (ru_pending != "") gp = ru_pending; ru_pending = ""; ru_begin(gp); return 0; end            // "receive_files(carpeta)"
    gp = ad_goto_page; ga = ad_goto_args;
    if (rc == 0 && gp != "")
        if (gp == "home") as_depth = 0; end                       // "go to home" empieza de nuevo: no se apilan paginas
        addon_goto(gp, ga); return 0;
    end
    addon_refresh();
end

function addon_widget(int i)
private int k, n, j; string v, nx, ch[24], lbl;
begin
    k = entry_size[i];
    switch (entry_akind[i])
        case 4: addon_do(entry_url[i], entry_aargs[i]); end
        case 5:
            v = addon_setting_text(k);
            host_setting_set(ad_st_name[k], (v == "yes" || v == "true" || v == "1") ? "no" : "yes");
            addon_refresh();
        end
        case 6:
            v = addon_setting_text(k); n = 0; lbl = ad_st_choices[k]; nx = "";
            // el siguiente valor de la lista (separada por |)
            j = find(lbl, "|"); while (j >= 0 && n < 23) ch[n] = substr(lbl, 0, j); lbl = substr(lbl, j + 1); n++; j = find(lbl, "|"); end
            ch[n] = lbl; n++;
            for (j = 0; j < n; j++) if (ch[j] == v) nx = ch[(j + 1) % n]; end end
            if (nx == "") nx = ch[0]; end
            host_setting_set(ad_st_name[k], nx);
            addon_refresh();
        end
        case 7:
            wid_name = ad_st_name[k];
            kb_secret_next = ad_st_type[k] == "secret";
            kb_open(ad_st_label[k], ad_st_type[k] == "secret" ? "" : addon_setting_text(k), KB_WIDGET);
        end
    end
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
        entry_akind[n_entries] = ad_it_kind[i]; entry_dur[n_entries] = ad_it_dur[i];
        if (ad_it_kind[i] >= 4)                                                    // boton, casilla, selector, campo de texto o cabecera
            entry_dir[n_entries] = K_AWIDGET; entry_url[n_entries] = ad_it_kind[i] == 4 ? ad_it_page[i] : ad_it_url[i];
            entry_aargs[n_entries] = ad_it_args[i]; entry_size[n_entries] = ad_it_flag[i];
            entries[n_entries] = addon_widget_title(i);
        elseif (ad_it_kind[i] == 0)
            entry_dir[n_entries] = K_AFOLDER; entry_url[n_entries] = ad_it_page[i]; entry_aargs[n_entries] = ad_it_args[i];
        else
            entry_dir[n_entries] = K_URL; entry_url[n_entries] = ad_it_url[i]; entry_aargs[n_entries] = ad_it_hdr[i];   // en un vídeo, aargs lleva las cabeceras
        end
        n_entries++;
    end
    auto_grid();
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
private int rc, d;
begin
    // se vuelve a la pagina anterior; si esa no se puede volver a mostrar (por ejemplo una busqueda que pide un texto y se
    // cancela) se sigue hacia atras en vez de quedarse atascado, y al final se sale a la lista de addons
    d = as_depth - 2;
    while (d >= 0)
        ad_replay = 1; rc = addon_run(as_page[d], as_args[d]); ad_replay = 0;
        if (rc == 0)
            as_depth = d + 1;
            addon_fill_entries();
            return 0;
        end
        d--;
    end
    read_addons(); return 1;
end

function addon_open(string dir)
begin
    addon_busy = 0;
    if (!ad_load(join_path(dir, "main.addon")))
        show_error(tr("s_addons"), ad_perr); return 0;
    end
    addon_dir = dir; addon_name = ad_i_name; as_depth = 0; ask_memo_n = 0;
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
        for (k = 0; k < ad_nst && k < 9; k++) if (!ad_st_hidden[k]) menu_add(fit_text(ad_st_label[k], 620) + ": " + aset_display(k), MA_ASET + k); end end
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

// ==========================================================================================================
//  tienda de addons y de listas
//  La lista viene de ficheros de texto del repositorio oficial del reproductor:
//      index.txt   cada línea es un addon:   id | nombre | version | ficheros | descripcion
//      lists.txt   cada línea es una lista:  fichero | direccion | descripcion
//  Al instalar un addon se descarga <raiz>/<id>/<fichero> en <almacen>/addons/<id>/, que es una de las
//  carpetas que mira la lista de addons: la del usuario tiene preferencia sobre la que trae el
//  reproductor, así que instalar desde la tienda también sirve para actualizar un addon del reproductor.
//  Las listas (TDTChannels, iptv-org...) se descargan de su dirección de origen a <almacen>/listas/,
//  que es la carpeta de "Mis listas": al bajar una lista nueva sólo hay que volver a instalarla.
// ==========================================================================================================

function string store_root()
begin
    if (store_base != "") return store_base; end
    if (set_unknown && set_store_url != "") return set_store_url; end            // Ajustes > Addons y fuentes
    return STORE_URL;
end

// campo k (1..) de una cadena con campos separados por "sep" ("" si no llega); sin espacios de sobra
function string field_of(string s, string sep, int k)
private int i, p, a, b;
begin
    i = 0;
    while (k > 1)
        p = find(substr(s, i), sep);
        if (p < 0) return ""; end
        i += p + len(sep); k--;
    end
    p = find(substr(s, i), sep);
    if (p >= 0) b = i + p; else b = len(s); end
    a = i;
    while (a < b && (substr(s, a, 1) == " " || substr(s, a, 1) == chr(9))) a++; end
    while (b > a && (substr(s, b - 1, 1) == " " || substr(s, b - 1, 1) == chr(9) || substr(s, b - 1, 1) == chr(13))) b--; end
    return substr(s, a, b - a);
end

function int field_n(string s, string sep)
private int i, p, n;
begin
    if (s == "") return 0; end
    n = 1; i = 0;
    while (1)
        p = find(substr(s, i), sep);
        if (p < 0) break; end
        n++; i += p + len(sep);
    end
    return n;
end

// versión instalada de un addon ("" si no está): primero la del usuario, después la del reproductor
function string installed_ver(string aid)
private string p;
begin
    if (aid == "") return ""; end
    p = join_path(join_path(addon_root_user(), aid), "main.addon");
    if (!fexists(p)) p = join_path(join_path(join_path(cd(), "addons"), aid), "main.addon"); end
    if (!fexists(p)) return ""; end
    if (!ad_peek_info(p) || ad_i_ver == "") return "?"; end
    return ad_i_ver;
end

// nombre de fichero de una lista de la tienda dentro de "Mis listas" (sin caracteres que no valgan)
function string store_list_name(string n)
private string r = ""; int i, c;
begin
    for (i = 0; i < len(n); i++)
        c = asc(substr(n, i, 1));
        if (c == 47 || c == 92 || c == 58 || c == 42 || c == 63 || c == 34 || c == 60 || c == 62 || c == 124 || c < 32) r += "_"; else r += substr(n, i, 1); end
    end
    if (r == "") r = "lista"; end
    return r;
end

function string store_list_path(string n)
begin
    return join_path(lists_dir, store_list_name(n) + ".m3u");
end

// "" si la lista no está descargada; "1" si ya está en "Mis listas"
function string store_list_have(string n)
begin
    if (fexists(store_list_path(n))) return "1"; end
    return "";
end

// ¿lo descargado es una lista de verdad? (el origen puede devolver una página de error con estado 200)
function int list_file_ok(string path)
private int fh, ok; string ln;
begin
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    ok = 0;
    while (!feof(fh) && !ok)
        ln = fgets(fh);
        if (len(ln) >= 3 && asc(substr(ln, 0, 1)) == 239) ln = substr(ln, 3); end      // marca BOM de UTF-8
        if (substr(ln, 0, 7) == "http://" || substr(ln, 0, 8) == "https://" || substr(ln, 0, 4) == "rtmp" || substr(ln, 0, 3) == "udp") ok = 1; end
    end
    fclose(fh);
    return ok;
end

// texto del estado de un addon o de una lista de la tienda
function string store_state(int i)
begin
    if (entry_skind[i] == 1) if (entry_siver[i] == "") return tr("s_notinst"); else return tr("s_lists_inst"); end end
    if (entry_siver[i] == "") return tr("s_notinst"); end
    if (entry_sver[i] == "" || entry_siver[i] == entry_sver[i]) return tr("s_installed") + " v" + entry_siver[i]; end
    return tr("s_update") + ": v" + entry_siver[i] + " > v" + entry_sver[i];
end

function store_reset()
begin
    n_entries = 1;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_info[0] = "";
    entry_sver[0] = ""; entry_sfiles[0] = ""; entry_siver[0] = ""; entry_skind[0] = 0; entry_surl[0] = "";
    sel = 0; top_row = 0; dir_ver++; lbl_ver = -1; pv_idx = -1;
end

// la tienda se abre al momento con "cargando..." y la lista se pide en el fotograma siguiente: así se ve
// el mensaje mientras se espera a la red en vez de una pantalla congelada
function store_open()
begin
    if (store_dir == "") toast(tr("t_no_store")); return 0; end
    store_mode = 1; addon_mode = 0; cur_list = ""; store_load = 1; store_cached = 0;
    store_reset(); n_entries = 0;
    s_amsg = tr("s_loading"); addon_busy = 1;
end

function store_index_parse(string txt)
private int p; string line, aid, nm, ver, files, desc;
begin
    store_reset();
    while (txt != "" && n_entries < MAX_ENTRIES)
        p = find(txt, chr(10));
        if (p < 0) line = txt; txt = ""; else line = substr(txt, 0, p); txt = substr(txt, p + 1); end
        if (len(line) > 0 && substr(line, len(line) - 1, 1) == chr(13)) line = substr(line, 0, len(line) - 1); end
        if (len(line) > 0 && substr(line, 0, 1) != "#")
            aid = field_of(line, "|", 1); nm = field_of(line, "|", 2); ver = field_of(line, "|", 3); files = field_of(line, "|", 4); desc = field_of(line, "|", 5);
            if (aid != "" && nm != "")
                entries[n_entries] = nm; entry_dir[n_entries] = K_SITEM; entry_url[n_entries] = aid;
                entry_size[n_entries] = 0; entry_logo[n_entries] = (find(files, "logo.png") >= 0) ? store_root() + "/" + aid + "/logo.png?v=" + ver : "";      // la version en la direccion: si el logo cambia, la cache de imagenes no sirve el antiguo entry_info[n_entries] = desc;
                entry_sver[n_entries] = ver; entry_sfiles[n_entries] = files; entry_siver[n_entries] = installed_ver(aid);
                entry_skind[n_entries] = 0; entry_surl[n_entries] = "";
                n_entries++;
            end
        end
    end
    lbl_ver = -1;
end

// listas de TV/radio: "fichero | direccion | descripcion"; se descargan en <almacen>/listas/
function store_lists_parse(string txt)
private int p; string line, fname, url, desc;
begin
    while (txt != "" && n_entries < MAX_ENTRIES)
        p = find(txt, chr(10));
        if (p < 0) line = txt; txt = ""; else line = substr(txt, 0, p); txt = substr(txt, p + 1); end
        if (len(line) > 0 && substr(line, len(line) - 1, 1) == chr(13)) line = substr(line, 0, len(line) - 1); end
        if (len(line) > 0 && substr(line, 0, 1) != "#")
            fname = field_of(line, "|", 1); url = field_of(line, "|", 2); desc = field_of(line, "|", 3);
            if (fname != "" && url != "")
                entries[n_entries] = fname; entry_dir[n_entries] = K_SITEM; entry_url[n_entries] = fname;
                entry_size[n_entries] = 0; entry_logo[n_entries] = ""; entry_info[n_entries] = desc;
                entry_sver[n_entries] = ""; entry_sfiles[n_entries] = ""; entry_siver[n_entries] = store_list_have(fname);
                entry_skind[n_entries] = 1; entry_surl[n_entries] = url;
                entry_sauth[n_entries] = field_of(line, "|", 4);
                n_entries++;
            end
        end
    end
    lbl_ver = -1;
end

// pide un fichero de texto de la tienda; si no hay red usa la copia guardada ("" = no hay nada)
function string store_get_text(string url, string cache)
private int st, n, fh; string txt;
begin
    st = http_fetch(url, "", "GET", "");
    store_net_err = st;
    if (st == 200 && http_length() > 0 && http_length() < HTTP_MAX)
        n = http_read(&ad_buf[0], http_length());
        txt = ad_buf_str(0, n);
        http_write(cache, txt);                                  // copia para cuando no haya red
        return txt;
    end
    if (!fexists(cache)) return ""; end
    txt = "";
    fh = fopen(cache, O_READ);
    if (!fh) return ""; end
    while (!feof(fh)) txt += fgets(fh) + chr(10); end
    fclose(fh);
    if (txt != "") store_cached = 1; end
    return txt;
end

// la tienda se pide en dos pasos (primero los addons y después las listas): una descarga por fotograma,
// para que se siga viendo el "cargando"; si no hay red se usan las copias guardadas
function store_fetch()
private string txt, d;
begin
    d = join_path(store_dir, "addons_data");
    mkdir(d);
    if (store_load == 1)
        txt = store_get_text(store_root() + "/index.txt", join_path(d, "index.txt"));
        if (txt == "")
            store_load = 0; addon_busy = 0; s_amsg = ""; n_entries = 1; dir_ver++;
            show_error(tr("mt_store"), tr("t_store_net") + " (" + (store_net_err > 0 ? "error " + store_net_err : http_error()) + ")");
            return 0;
        end
        store_index_parse(txt);
        store_load = 2;                                          // el siguiente fotograma pide las listas
        return 1;
    end
    if (store_load == 2)
        txt = store_get_text(store_root() + "/lists.txt", join_path(d, "lists.txt"));
        store_load = 0; addon_busy = 0; s_amsg = "";
        if (txt != "") store_lists_parse(txt); end               // si el repositorio no trae lists.txt, no pasa nada
        auto_grid();
        if (store_cached) toast(tr("t_store_off")); end
        return 1;
    end
    store_load = 0;
    return 0;
end

// ---- barra de progreso del sistema (PS5). Si no hay (PC) o falla, no pasa nada: queda el texto propio de la pantalla
function prog_start(string caption, int cancel)
begin
    ov_on = 1; ov_title = caption; ov_cancel = cancel; ov_pct = 0;
end

function prog_stop()
begin
    ov_on = 0;
end

// ventana de progreso: fondo atenuado, caja con el nombre, barra con el porcentaje real y, si se puede, boton de cancelar
function draw_overlay()
private int w, ty;
begin
    put(S_OVDIM, g_ovdim, SW / 2, SH / 2, 100, 255, -21);
    spr_sizex[S_OVDIM] = SW / 8 * 100; spr_sizey[S_OVDIM] = SH / 8 * 100;
    put(S_OVBOX, g_ovbox, SW / 2, SH / 2, 100, 255, -22);
    spr_sizex[S_OVBOX] = 820 / 8 * 100; spr_sizey[S_OVBOX] = 270 / 8 * 100;
    put(S_OVBG, g_barbg, SW / 2, OV_BARY, 100, 255, -23);
    spr_sizex[S_OVBG] = 700 / 8 * 100; spr_sizey[S_OVBG] = 16 * 100 / 8;
    w = ov_pct * 700 / 100;
    if (w > 0)
        put(S_OVFG, g_ovfill, SW / 2 - 350 + w / 2, OV_BARY, 100, 255, -24);
        spr_sizex[S_OVFG] = w * 100 / 8; spr_sizey[S_OVFG] = 16 * 100 / 8;
    end
    if (s_ovt != fit_text(ov_title, 760)) s_ovt = fit_text(ov_title, 760); end
    if (s_ovp != (ov_sub != "" ? ov_sub : ov_pct + " %")) s_ovp = ov_sub != "" ? ov_sub : ov_pct + " %"; end
    txt_want[txt_ovt] = 8589934336 + (255);
    txt_want[txt_ovp] = 8589934336 + (230);
    if (ov_cancel)
        if (s_ovh != (ov_btn != "" ? ov_btn : tr("h_cancel"))) s_ovh = ov_btn != "" ? ov_btn : tr("h_cancel"); end
        put_sel(S_OVBTN, SW / 2, OV_BY, 280, 50, -23);
        if (!touch_mode) put(S_OVICO, g_sym[1], SW / 2 - tw(s_ovh) / 2 - 22, OV_BY + 2, 80, 255, -26); end
        write_move(txt_ovh, ur(SW / 2 + (touch_mode ? 0 : 22)), ur(OV_BY));
        txt_want[txt_ovh] = 8589934336 + (255);
    end
end

// ¿se ha pedido cancelar?  Boton atras / circulo, o un toque sobre el boton en el movil
function ov_cancel_asked()
begin
    if (!ov_cancel) return 0; end
    if (act_press[A_BACK]) return 1; end
    if (tap() && abs(touch_x - SW / 2) < 140 && abs(touch_y - OV_BY) < 40) return 1; end
    return 0;
end

function store_prog()
private int p, tot, got;
begin
    if (!ov_on) return 0; end
    p = store_ji * 100 / store_jn;
    tot = http_total(); got = http_progress();
    if (tot > 0) if (got > tot) got = tot; end p += (got * 100 / tot) / store_jn; end
    if (p > 99) p = 99; end
    ov_pct = p;
end

// prepara la instalación de la entrada i (un addon o una lista): se hace en el fotograma siguiente
function store_install(int i)
begin
    if (store_dir == "") toast(tr("t_no_store")); return 0; end
    if (i <= 0 || i >= n_entries || entry_dir[i] != K_SITEM) return 0; end
    // una lista que pide cuenta: antes de bajarla se pregunta el usuario y la clave (si no están guardados)
    if (entry_skind[i] == 1 && entry_sauth[i] != "")
        au_ask_file = store_list_path(entry_url[i]);
        au_ask_name = store_list_name(entry_url[i]);
        if (!au_load(au_ask_file))
            au_ask_spec = entry_sauth[i];
            au_ask_row = i; au_ask_next = 1;
            au_set_spec(au_ask_spec);
            if (au_mode == "xtream")
                kb_open(tr("k_xt_server"), au_test_val("MP_AUTH_SERVER", au_server), KB_AUTH_SERVER);
            else
                kb_open(tr("k_auth_user"), au_test_val("MP_AUTH_USER", ""), KB_AUTH_USER);
            end
            return 0;
        end
    end
    store_job = 1; store_ji = 0; store_jerr = 0; store_jrow = i;
    store_jid = entry_url[i]; store_jname = entries[i]; store_jkind = entry_skind[i];
    store_jurl = entry_surl[i];
    if (store_jkind == 1)
        store_jfile = store_list_name(store_jid) + ".m3u";       // destino dentro de "Mis listas"
        store_jfiles = ""; store_jn = 1; store_jdir = lists_dir;
    else
        store_jfiles = entry_sfiles[i];
        if (store_jfiles == "") store_jfiles = "main.addon,logo.png"; end
        store_jn = field_n(store_jfiles, ",");
        store_jdir = join_path(addon_root_user(), store_jid);
    end
    store_jreq = 0; store_jcur = 0;
    s_amsg = tr("s_installing") + " " + store_jname; addon_busy = 1;
    prog_start(tr("s_installing") + " " + store_jname, 0);
end

// una descarga por vez, en segundo plano: cada fotograma se mira como va (la pantalla y la barra del sistema siguen vivas)
function store_step()
private int st, r; string fn, url, why, dest;
begin
    if (store_jreq)
        st = http_fetch_poll();
        if (st == -1) store_prog(); return 0; end            // sigue bajando
        store_jreq = 0;
        if (store_jkind == 1)
            // lista de TV/radio: llega de su direccion de origen y se guarda en "Mis listas"
            dest = join_path(store_jdir, store_jfile);
            if (st != 200)
                store_jerr = st > 0 ? st : 1;
            elseif (!http_save(dest))
                store_jerr = -1;
            else
                if (!list_file_ok(dest))
                    store_jerr = -2; fremove(dest); end              // el origen devolvio algo que no es una lista
            end
            store_ji = 1;
        else
            fn = field_of(store_jfiles, ",", store_jcur);
            if (find(fn, "/") > 0) mkdir(join_path(store_jdir, substr(fn, 0, find(fn, "/")))); end      // ficheros en subcarpetas (lang/es.txt)
            if (st != 200) store_jerr = st > 0 ? st : 1;
            elseif (!http_save(join_path(store_jdir, fn))) store_jerr = -1; end
            store_ji = store_jcur;
            if (store_jerr == 0 && store_ji >= store_jn && !ad_peek_info(join_path(store_jdir, "main.addon"))) store_jerr = -2; end
        end
    else
        // empieza la siguiente descarga
        if (store_jkind == 1)
            mkdir(store_jdir);
            dest = join_path(store_jdir, store_jfile);
            au_load(dest);                                        // las credenciales de esta lista, si tiene
            if (http_fetch_begin(au_apply(store_jurl), au_headers(), "GET", "") != 0) store_jerr = 1; else store_jreq = 1; end
        else
            if (store_ji == 0) mkdir(store_jdir); end
            store_jcur = store_ji + 1;
            fn = field_of(store_jfiles, ",", store_jcur);
            if (fn == "")
                store_ji = store_jcur;                            // un hueco en la lista de ficheros: se salta
            else
                url = store_root() + "/" + store_jid + "/" + fn;
                if (http_fetch_begin(url, "", "GET", "") != 0) store_jerr = 1; else store_jreq = 1; end
            end
        end
        if (store_jreq) store_prog(); return 0; end
    end
    if (store_jerr != 0 || store_ji >= store_jn)
        store_job = 0; addon_busy = 0; s_amsg = ""; prog_stop();
        if (store_jerr != 0)
            if (store_jerr == -2 && store_jkind == 0) fremove(join_path(store_jdir, "main.addon")); end   // el fichero bajado no es un addon
            if (store_jerr == -1)
                why = tr("t_store_nosave");
            elseif (store_jerr == -2)
                if (store_jkind == 1) why = tr("t_store_badlist"); else why = tr("t_store_badfile"); end
            else
                why = tr("t_store_http") + " " + store_jerr;
            end
            show_error(tr("mt_store"), tr("t_store_fail") + " " + store_jname + ": " + why);
        else
            if (store_jkind == 1) entry_siver[store_jrow] = store_list_have(store_jid); else entry_siver[store_jrow] = installed_ver(store_jid); end
            dir_ver++; lbl_ver = -1; pv_idx = -1;
            if (store_jkind == 1) toast(tr("t_store_listok") + " " + store_jname); else toast(tr("t_store_ok") + " " + store_jname); end
        end
    else
        s_amsg = tr("s_installing") + " " + store_jname + "  " + store_ji + "/" + store_jn; ov_title = s_amsg;
    end
end

// ---- guardar un video de un addon en "Descargas": el motor copia video y audio a un .mp4 en segundo plano
// ¿se puede descargar esta entrada?  Un video directo si; una carpeta del addon solo si parece un video
// (tiene duracion o abre la pagina "play"/"watch"), porque al descargar se abre esa pagina para obtener la URL
// Devuelve 0 = no, 1 = video (se ofrece el video y solo el audio), 2 = solo audio (musica)
function int dl_possible(int i)
begin
    if (addon_mode != 2 || i <= 0 || i >= n_entries) return 0; end
    if (entry_dir[i] == K_URL) return entry_akind[i] == 1 ? 1 : (entry_akind[i] == 2 ? 2 : 0); end
    if (entry_dir[i] == K_AFOLDER) return (entry_dur[i] > 0 || entry_url[i] == "play" || entry_url[i] == "watch") ? 1 : 0; end
    return 0;
end

// formatos a los que se puede convertir el audio: nombre en el motor, extension y texto del menu
function string dl_fmt_id(int k)
begin
    switch (k) case 0: return "mp3"; end case 1: return "opus"; end case 2: return "flac"; end case 3: return "wav"; end default: return "aac"; end end
end
function string dl_fmt_ext(int k)
begin
    switch (k) case 0: return ".mp3"; end case 1: return ".opus"; end case 2: return ".flac"; end case 3: return ".wav"; end default: return ".m4a"; end end
end
function string dl_fmt_name(int k)
begin
    switch (k) case 0: return "MP3"; end case 1: return "Opus"; end case 2: return "FLAC"; end case 3: return "WAV"; end default: return "AAC (.m4a)"; end end
end

// mode: 0 = el video con su audio en un .mp4; 1 = solo el audio tal cual (.m4a, .mp3, .opus...: el motor elige segun el codec);
// 10..14 = el audio convertido a mp3 / opus / flac / wav / aac
function dl_start(int i, int mode)
private string dname, dpath, durl, dhdr, dext; int r, dn, c, k, audio;
begin
    if (store_dir == "") toast(tr("t_no_store")); return 0; end
    if (dl_job || !dl_possible(i)) return 0; end
    durl = entry_url[i]; dhdr = entry_aargs[i];
    audio = mode >= 1; if (dl_possible(i) == 2) audio = 1; end
    if (entry_dir[i] == K_AFOLDER)
        // se ejecuta la pagina del elemento (la lista de la pantalla sigue como esta: no se toca) y se coge su primer video (o audio)
        if (addon_run(entry_url[i], entry_aargs[i]) != 0) return 0; end
        k = 0; while (k < ad_nit && ad_it_kind[k] != 1) k++; end
        if (k >= ad_nit) k = 0; while (k < ad_nit && ad_it_kind[k] != 2) k++; end end
        if (k >= ad_nit) toast(tr("t_dl_fail")); return 0; end
        if (ad_it_kind[k] == 2) audio = 1; end
        durl = ad_it_url[k]; dhdr = ad_it_hdr[k];
    end
    dext = mode >= 10 ? dl_fmt_ext(mode - 10) : (audio ? ".m4a" : ".mp4");
    mkdir(downloads_dir);
    dname = "";
    for (r = 0; r < len(entries[i]); r++)                                     // sin los caracteres que un nombre de fichero no admite
        c = asc(substr(entries[i], r, 1));
        if (c == 47 || c == 92 || c == 58 || c == 42 || c == 63 || c == 34 || c == 60 || c == 62 || c == 124 || c < 32) dname = dname + "_"; else dname = dname + substr(entries[i], r, 1); end
    end
    while (len(dname) > 80) dname = utf8_chop(dname); end
    if (dname == "") dname = "video"; end
    dpath = join_path(downloads_dir, dname + dext); dn = 1;
    while (fexists(dpath)) dn++; dpath = join_path(downloads_dir, dname + " (" + dn + ")" + dext); end
    if (mode >= 10) r = video_download_convert_begin(durl, dhdr, dpath, dl_fmt_id(mode - 10));
    elseif (audio) r = video_download_audio_begin(durl, dhdr, dpath);
    else r = video_download_begin(durl, dhdr, dpath); end
    if (r != 0) toast(tr("t_dl_fail")); return 0; end
    dl_job = 1; dl_path = dpath; dl_title = entries[i];
    s_amsg = tr("s_downloading") + " " + dl_title; addon_busy = 1;
    prog_start(tr("s_downloading") + " " + dl_title, 1);                     // con boton de cancelar
end

// un paso por fotograma: se cancela con el boton de la ventana del sistema (PS5) o con atras (PC)
function dl_step()
private int st, p; string why;
begin
    if (ov_cancel_asked()) video_download_cancel(); end
    st = video_download_poll();
    if (st == -1)
        p = video_download_percent();
        ov_pct = p;
        s_amsg = tr("s_downloading") + " " + dl_title + "  " + p + "%";
        return 0;
    end
    dl_job = 0; addon_busy = 0; s_amsg = ""; prog_stop();
    dl_path = video_download_path();                                          // en audio la extension la decide el motor segun el codec
    if (st == 0)
        toast(tr("t_dl_ok") + " " + dl_title);
    elseif (st == -2)
        fremove(dl_path); toast(tr("t_dl_cancel"));
    else
        why = video_download_error();
        fremove(dl_path);
        show_error(tr("s_downloads"), tr("t_dl_fail") + ": " + why);
    end
end

// Instala un addon de fuera de la tienda (Ajustes > Addons y fuentes > Origenes desconocidos): se baja main.addon desde la
// direccion (o desde la carpeta que se escribe), se comprueba que es un addon y se guarda en el almacen de addons
function addon_install_url(string url)
private string abase, aid, adir, nm, tmp, ch; int st, i;
begin
    if (!set_unknown) toast(tr("st_needs_unknown")); return 0; end
    if (store_dir == "") toast(tr("t_no_store")); return 0; end
    if (len(url) < 9 || url == "https://") return 0; end
    if (lcase(substr(url, len(url) - 10, 10)) != "main.addon")
        if (substr(url, len(url) - 1, 1) != "/") url += "/"; end
        url += "main.addon";
    end
    abase = substr(url, 0, len(url) - 10);
    toast(tr("s_loading")); frame;
    st = http_fetch(url, "", "GET", "");
    tmp = join_path(store_dir, "addon_nuevo.tmp");
    if (st != 200 || !http_save(tmp))
        show_error(tr("st_install_url"), tr("t_addon_fail") + ": " + (st > 0 ? tr("t_store_http") + " " + st : http_error())); return 0;
    end
    if (!ad_peek_info(tmp)) fremove(tmp); show_error(tr("st_install_url"), tr("t_store_badfile")); return 0; end
    nm = ad_i_name; aid = "";
    for (i = 0; i < len(ad_i_id); i++)                                  // el id es el nombre de la carpeta: solo letras, numeros, - y _
        ch = lcase(substr(ad_i_id, i, 1));
        if ((ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-" || ch == "_") aid += ch; end
    end
    if (aid == "") fremove(tmp); show_error(tr("st_install_url"), tr("t_store_badfile")); return 0; end
    adir = join_path(join_path(store_dir, "addons"), aid);
    mkdir(join_path(store_dir, "addons")); mkdir(adir);
    if (!http_save(join_path(adir, "main.addon"))) fremove(tmp); show_error(tr("st_install_url"), tr("t_store_nosave")); return 0; end
    fremove(tmp);
    // opcionales: el logo y la traduccion a este idioma, si estan junto al addon
    if (http_fetch(abase + "logo.png", "", "GET", "") == 200) http_save(join_path(adir, "logo.png")); end
    if (lang_cur != "en")
        mkdir(join_path(adir, "lang"));
        if (http_fetch(abase + "lang/" + lang_cur + ".txt", "", "GET", "") == 200) http_save(join_path(join_path(adir, "lang"), lang_cur + ".txt")); end
    end
    toast(tr("t_addon_installed") + " " + nm);
end

function open_store_menu()
begin
    menu_clear();
    menu_add(tr("m_refresh"), MA_STORE_REFRESH);
    menu_add(tr("m_back"), MA_CANCEL);
    menu_show(tr("mt_store"));
end
