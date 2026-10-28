// ==========================================================================================================
//  dlna.prg - ver los servidores de medios de la red local (DLNA / UPnP: Plex, Jellyfin, Kodi, MiniDLNA, un router con disco...).
//  El motor (libmod_video: dlna.c) los busca y lista sus carpetas en segundo plano; aqui se muestran como carpetas y archivos
//  del explorador. Los archivos se reproducen por la direccion http que da el servidor. No se escribe nada en ellos.
// ==========================================================================================================
const
    DL_PAGE = 200;                       // elementos que se piden de cada vez
end

global
    int    dlna_mode;                    // 0 no, 1 lista de servidores, 2 dentro de un servidor
    int    dlna_job;                     // 1 buscando servidores, 2 pidiendo una carpeta
    int    dn_srv;                       // servidor abierto
    string dn_ids[16]; string dn_titles[16]; int dn_depth;     // carpetas por las que se ha entrado (pila)
    int    dn_start, dn_total, dn_t;     // por donde va la paginacion, cuantos hay en total, fotogramas esperando
    string dn_pending_id = "";           // carpeta que se esta pidiendo
    int    dn_more_start;                // desde donde pedir al pulsar "mas"
end

// entra en la pantalla de servidores y empieza a buscarlos
function dlna_open()
begin
    n_entries = 0; addon_mode = 0; store_mode = 0; marks_clear(); cur_list = "";
    sel = 0; top_row = 0; dir_ver++; grid_mode = 0; resume_mode = 0;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    dlna_mode = 1; dn_depth = 0; lbl_ver = -1;
    if (dlna_scan() == 0 || dlna_scan_state() == 1)
        dlna_job = 1; dn_t = 0; s_amsg = tr("s_dlna_search"); addon_busy = 1;
    end
end

// pide el contenido de una carpeta (oid) del servidor abierto, a partir de start
function dlna_ask(string oid, int start)
begin
    if (dlna_browse(dn_srv, oid, start, DL_PAGE) != 0) toast(tr("t_ru_busy")); return 0; end
    dlna_job = 2; dn_t = 0; dn_pending_id = oid; dn_start = start;
    s_amsg = tr("s_loading"); addon_busy = 1;
end

// llena la lista con lo que ha respondido el servidor ("C<TAB>id<TAB>titulo<TAB>hijos" / "I<TAB>url<TAB>titulo<TAB>bytes<TAB>segundos<TAB>tipo")
function dlna_fill(string txt, int append)
private int p, q, n, nf, k; string ln, f[6], dur;
begin
    if (!append)
        n_entries = 0; sel = 0; top_row = 0;
        entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    else
        if (n_entries > 0 && entry_dir[n_entries - 1] == K_DLNAMORE) n_entries--; end        // se quita la fila "mas"
    end
    n = 0;
    while (txt != "" && n_entries < MAX_ENTRIES - 1)
        p = find(txt, chr(10));
        if (p < 0) ln = txt; txt = ""; else ln = substr(txt, 0, p); txt = substr(txt, p + 1); end
        if (ln == "") continue; end
        nf = 0;
        while (nf < 6)
            q = find(ln, chr(9));
            if (q < 0) f[nf] = ln; nf++; break; end
            f[nf] = substr(ln, 0, q); ln = substr(ln, q + 1); nf++;
        end
        if (f[0] == "C" && nf >= 3)
            entries[n_entries] = utf8_to_latin1(f[2]); entry_dir[n_entries] = K_DLNADIR; entry_url[n_entries] = f[1]; entry_size[n_entries] = 0;
            entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++; n++;
        elseif (f[0] == "I" && nf >= 6)
            entries[n_entries] = utf8_to_latin1(f[2]); entry_dir[n_entries] = K_URL; entry_url[n_entries] = f[1]; entry_size[n_entries] = atoi(f[3]);
            entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++; n++;
        end
    end
    dn_total = dlna_total();
    if (dn_start + DL_PAGE < dn_total && n_entries < MAX_ENTRIES - 1)
        entries[n_entries] = tr("s_dlna_more") + " (" + (dn_start + DL_PAGE) + " / " + dn_total + ")"; entry_dir[n_entries] = K_DLNAMORE; entry_url[n_entries] = ""; entry_size[n_entries] = 0;
        entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
    end
    dir_ver++; lbl_ver = -1;
end

// un paso por fotograma mientras se busca o se espera una carpeta
function dlna_step()
private int st, i;
begin
    dn_t++;
    if (act_press[A_BACK] || (ptr_rclick)) dlna_job = 0; addon_busy = 0; s_amsg = ""; go_up(); return 0; end
    if (dlna_job == 1)
        st = dlna_scan_state();
        if (st == 2 || dn_t > 900)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            n_entries = 1;
            for (i = 0; i < dlna_count() && n_entries < 30; i++)
                entries[n_entries] = utf8_to_latin1(dlna_name(i)); entry_dir[n_entries] = K_DLNASRV; entry_url[n_entries] = "" + i; entry_size[n_entries] = 0;
                entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
            end
            if (dlna_count() == 0) toast(tr("s_dlna_none")); end
            dir_ver++; lbl_ver = -1;
        end
    elseif (dlna_job == 2)
        st = dlna_browse_state();
        if (st == 2)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            dlna_fill(dlna_result(), dn_start > 0);
            if (dn_start == 0 && n_entries <= 1) toast(tr("s_empty")); end
        elseif (st == 3 || dn_t > 1500)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            show_error(tr("s_dlna"), tr("t_dlna_fail") + ": " + dlna_error());
            if (dn_depth > 0) dn_depth--; end
        end
    end
end

// un elemento de la pantalla de servidores: servidor, carpeta o "mas"
function dlna_activate(int i)
begin
    switch (entry_dir[i])
        case K_DLNASRV:
            dn_srv = atoi(entry_url[i]); dn_depth = 1; dn_ids[0] = "0"; dn_titles[0] = entries[i]; dlna_mode = 2;
            dlna_ask("0", 0);
        end
        case K_DLNADIR:
            if (dn_depth < 15) dn_ids[dn_depth] = entry_url[i]; dn_titles[dn_depth] = entries[i]; dn_depth++; end
            dlna_ask(entry_url[i], 0);
        end
        case K_DLNAMORE:
            dlna_ask(dn_ids[dn_depth - 1], dn_start + DL_PAGE);
        end
    end
end

// Atras: sube una carpeta del servidor, o vuelve a la lista de servidores, o al inicio
function dlna_back()
begin
    if (dlna_mode == 2 && dn_depth > 1)
        dn_depth--;
        dlna_ask(dn_ids[dn_depth - 1], 0);
    elseif (dlna_mode == 2)
        dlna_mode = 1; dn_depth = 0; dlna_open();
    else
        dlna_mode = 0; cur_dir = home_dir; read_dir();
    end
end

// el titulo de la cabecera: "Servidores de red / Plex / Peliculas"
function string dlna_path()
private int i; string t;
begin
    t = "  " + tr("m_network");
    for (i = 0; i < dn_depth; i++) t += "  /  " + dn_titles[i]; end
    return t;
end
