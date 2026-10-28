// ==========================================================================================================
//  dlna.prg - ver los servidores de la red local: DLNA / UPnP (Plex, Jellyfin, Kodi, MiniDLNA, un router con disco...) y los
//  servidores WebDAV (https://...) y FTP (ftp://...) que el usuario anade. El motor (libmod_video) los busca y lista sus carpetas en
//  segundo plano; aqui se muestran como carpetas y archivos del explorador. Los archivos se reproducen por su direccion.
//  No se escribe nada en los servidores.
// ==========================================================================================================
const
    DL_PAGE = 200;                       // elementos que se piden de cada vez (DLNA)
end

global
    int    dlna_mode;                    // 0 no, 1 lista de servidores, 2 dentro de un servidor
    int    dlna_job;                     // 1 buscando servidores, 2 carpeta DLNA, 3 carpeta WebDAV, 4 carpeta FTP
    int    dn_srv;                       // servidor DLNA abierto
    string dn_ids[16]; string dn_titles[16]; int dn_depth;     // carpetas por las que se ha entrado (pila): id (DLNA) o ruta (WebDAV / FTP)
    int    dn_start, dn_total, dn_t;     // por donde va la paginacion, cuantos hay en total, fotogramas esperando
    string dn_pending_id = "";           // carpeta que se esta pidiendo
    int    dn_kind;                      // servidor abierto: 1 DLNA, 2 WebDAV, 3 FTP
    string dn_pfx = "";                  // WebDAV / FTP: esquema://usuario:clave@servidor:puerto (para armar las direcciones)
    string ns_name[16]; string ns_url[16]; string ns_user[16]; string ns_pass[16]; int ns_n;    // servidores WebDAV / FTP guardados
    string ns_tmp_url = "", ns_tmp_user = "";      // alta de un servidor en curso
    string dn_req_url = "", dn_req_hdr = "", dn_req_body = ""; int dn_wait;      // peticion WebDAV pendiente de empezar (solo se puede una a la vez)
end

declare function dlna_list_servers() end
declare function ns_load() end
declare function net_add_start() end
declare function string url_enc(string t) end
declare function string trim_text(string t) end
declare function string ns_host_of(string u) end

// la lista de servidores: los DLNA encontrados, los WebDAV / FTP guardados y la fila para anadir uno
function dlna_list_servers()
private int i;
begin
    n_entries = 1; sel = 0; top_row = 0;
    for (i = 0; i < dlna_count() && n_entries < 30; i++)
        entries[n_entries] = utf8_to_latin1(dlna_name(i)); entry_dir[n_entries] = K_DLNASRV; entry_url[n_entries] = "" + i; entry_size[n_entries] = 0;
        entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
    end
    for (i = 0; i < ns_n && n_entries < 40; i++)
        entries[n_entries] = utf8_to_latin1(ns_name[i]) + "   (" + (substr(ns_url[i], 0, 3) == "ftp" ? "FTP" : "WebDAV") + ")"; entry_dir[n_entries] = K_NETSRV; entry_url[n_entries] = "" + i; entry_size[n_entries] = 0;
        entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
    end
    entries[n_entries] = tr("m_ns_add"); entry_dir[n_entries] = K_NETADD; entry_url[n_entries] = ""; entry_size[n_entries] = 0;
    entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
    dir_ver++; lbl_ver = -1;
end

// entra en la pantalla de servidores y empieza a buscarlos
function dlna_open()
begin
    ns_load();
    n_entries = 0; addon_mode = 0; store_mode = 0; marks_clear(); cur_list = "";
    sel = 0; top_row = 0; dir_ver++; grid_mode = 0; resume_mode = 0;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    dlna_mode = 1; dn_depth = 0; lbl_ver = -1;
    if (dlna_scan() == 0 || dlna_scan_state() == 1)
        dlna_job = 1; dn_t = 0; s_amsg = tr("s_dlna_search"); addon_busy = 1;
    else
        dlna_list_servers();
    end
end

// carpeta del servidor abierto: oid (id DLNA o ruta), a partir de start (solo DLNA pagina)
function dlna_ask(string oid, int start)
private string u, hdr;
begin
    if (dn_kind == 1)
        if (dlna_browse(dn_srv, oid, start, DL_PAGE) != 0) toast(tr("t_ru_busy")); return 0; end
        dlna_job = 2;
    elseif (dn_kind == 2)
        hdr = "Depth: 1" + chr(13) + chr(10) + "Content-Type: application/xml" + chr(13) + chr(10);
        dn_req_url = dn_pfx + oid; dn_req_hdr = hdr;
        dn_req_body = "<?xml version=" + chr(34) + "1.0" + chr(34) + "?><propfind xmlns=" + chr(34) + "DAV:" + chr(34) + "><prop><resourcetype/><getcontentlength/><displayname/></prop></propfind>";
        dn_wait = http_fetch_begin(dn_req_url, dn_req_hdr, "PROPFIND", dn_req_body) != 0;      // si hay otra peticion en marcha, se reintenta en cada fotograma
        dlna_job = 3;
    else
        if (ftp_list_begin(dn_pfx + oid) != 0) toast(tr("t_ru_busy")); return 0; end
        dlna_job = 4;
    end
    dn_t = 0; dn_pending_id = oid; dn_start = start;
    s_amsg = tr("s_loading"); addon_busy = 1;
end

// ¿se muestra esta entrada de un servidor WebDAV / FTP? (carpetas y multimedia; con "mostrar todos los archivos", todo)
function int net_show(string nm)
begin
    return set_allfiles || is_video(nm) || is_audio(nm) || is_image(nm) || lcase(ext_of(nm)) == "torrent";
end

// llena la lista con lo que ha respondido el servidor ("C<TAB>id<TAB>titulo<TAB>hijos" / "I<TAB>url<TAB>titulo<TAB>bytes<TAB>segundos<TAB>tipo")
function dlna_fill(string txt, int append)
private int p, q, n, nf; string ln, f[6], href, base;
begin
    if (!append)
        n_entries = 0; sel = 0; top_row = 0;
        entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; entry_aargs[0] = ""; entry_info[0] = ""; n_entries = 1;
    else
        if (n_entries > 0 && entry_dir[n_entries - 1] == K_DLNAMORE) n_entries--; end        // se quita la fila "mas"
    end
    n = 0; base = dn_depth > 0 ? dn_ids[dn_depth - 1] : "";
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
            entries[n_entries] = utf8_to_latin1(f[2]); entry_dir[n_entries] = K_DLNADIR; entry_size[n_entries] = 0;
            entry_url[n_entries] = f[1];                                                      // DLNA: el id; WebDAV: la ruta que dio el servidor
            if (dn_kind == 3) entry_url[n_entries] = base + url_enc(f[1]) + "/"; end          // FTP: la ruta de la carpeta
            entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++; n++;
        elseif (f[0] == "I" && nf >= 6)
            if (dn_kind == 1 || net_show(f[2]))
                entries[n_entries] = utf8_to_latin1(f[2]); entry_size[n_entries] = atoi(f[3]);
                if (dn_kind == 1) entry_url[n_entries] = f[1];
                elseif (dn_kind == 2) entry_url[n_entries] = dn_pfx + f[1];
                else entry_url[n_entries] = dn_pfx + base + url_enc(f[1]); end
                entry_dir[n_entries] = K_URL; entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++; n++;
            end
        end
    end
    if (dn_kind == 1)
        dn_total = dlna_total();
        if (dn_start + DL_PAGE < dn_total && n_entries < MAX_ENTRIES - 1)
            entries[n_entries] = tr("s_dlna_more") + " (" + (dn_start + DL_PAGE) + " / " + dn_total + ")"; entry_dir[n_entries] = K_DLNAMORE; entry_url[n_entries] = ""; entry_size[n_entries] = 0;
            entry_logo[n_entries] = ""; entry_aargs[n_entries] = ""; entry_info[n_entries] = ""; n_entries++;
        end
    end
    dir_ver++; lbl_ver = -1;
end

// un paso por fotograma mientras se busca o se espera una carpeta
function dlna_step()
private int st;
begin
    dn_t++;
    if (act_press[A_BACK] || ptr_rclick) dlna_job = 0; addon_busy = 0; s_amsg = ""; go_up(); return 0; end
    if (dlna_job == 1)
        st = dlna_scan_state();
        if (st == 2 || dn_t > 900)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            dlna_list_servers();
            if (dlna_count() == 0 && ns_n == 0) toast(tr("s_dlna_none")); end
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
            if (dn_depth > 1) dn_depth--; end
        end
    elseif (dlna_job == 3)
        if (dn_wait)
            if (http_fetch_begin(dn_req_url, dn_req_hdr, "PROPFIND", dn_req_body) == 0) dn_wait = 0; end
            if (dn_t > 600) dn_wait = 0; dlna_job = 0; addon_busy = 0; s_amsg = ""; show_error(tr("s_dlna"), tr("t_dlna_fail")); end
            return 0;
        end
        st = http_fetch_poll();
        if (st != -1)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            if (st == 200 && http_length() > 0)
                dlna_fill(webdav_parse(dn_pending_id), 0);
                if (n_entries <= 1) toast(tr("s_empty")); end
            else
                show_error(tr("s_dlna"), tr("t_dlna_fail") + ": " + (st > 0 ? "error " + st : http_error()));
                if (dn_depth > 1) dn_depth--; end
            end
        elseif (dn_t > 2400)
            dlna_job = 0; addon_busy = 0; s_amsg = ""; show_error(tr("s_dlna"), tr("t_dlna_fail"));
        end
    elseif (dlna_job == 4)
        st = ftp_list_poll();
        if (st != -1)
            dlna_job = 0; addon_busy = 0; s_amsg = "";
            if (st == 0)
                dlna_fill(ftp_list_result(), 0);
                if (n_entries <= 1) toast(tr("s_empty")); end
            else
                show_error(tr("s_dlna"), tr("t_dlna_fail") + ": " + ftp_list_error());
                if (dn_depth > 1) dn_depth--; end
            end
        elseif (dn_t > 2400)
            dlna_job = 0; addon_busy = 0; s_amsg = ""; show_error(tr("s_dlna"), tr("t_dlna_fail"));
        end
    end
end

// abre un servidor WebDAV / FTP guardado: arma el prefijo con usuario y clave y pide la carpeta de su direccion
function ns_open(int i)
private string u, rest, path, scheme, host; int p;
begin
    u = ns_url[i]; p = find(u, "://"); scheme = substr(u, 0, p + 3); rest = substr(u, p + 3);
    p = find(rest, "/"); if (p < 0) host = rest; path = "/"; else host = substr(rest, 0, p); path = substr(rest, p); end
    p = find(host, "@"); if (p >= 0) host = substr(host, p + 1); end                       // si la direccion ya llevaba usuario, se usa el que se dio aparte
    dn_pfx = scheme + (ns_user[i] != "" ? url_enc(ns_user[i]) + ":" + url_enc(ns_pass[i]) + "@" : "") + host;
    if (substr(path, len(path) - 1, 1) != "/") path += "/"; end
    dn_kind = scheme == "ftp://" ? 3 : 2;
    dn_depth = 1; dn_ids[0] = path; dn_titles[0] = ns_name[i]; dlna_mode = 2;
    dlna_ask(path, 0);
end

// un elemento de la pantalla de servidores: servidor, carpeta o "mas"
function dlna_activate(int i)
begin
    switch (entry_dir[i])
        case K_DLNASRV:
            dn_kind = 1; dn_srv = atoi(entry_url[i]); dn_depth = 1; dn_ids[0] = "0"; dn_titles[0] = entries[i]; dlna_mode = 2;
            dlna_ask("0", 0);
        end
        case K_NETSRV: ns_open(atoi(entry_url[i])); end
        case K_NETADD: net_add_start(); end
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

// ---------------------------------------------------------------- servidores WebDAV / FTP guardados
// Lo pegado en el teclado -> texto seguro dentro de una direccion
function string url_enc(string t)
private int i, c; string r;
begin
    r = "";
    for (i = 0; i < len(t); i++)
        c = asc(substr(t, i, 1));
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 46 || c == 95 || c == 126)
            r += chr(c);
        else
            r += "%" + substr("0123456789ABCDEF", c / 16, 1) + substr("0123456789ABCDEF", c % 16, 1);
        end
    end
    return r;
end

function string ns_file()
begin
    return join_path(store_dir, "netservers.cfg");
end

function ns_load()
private int fh, p1, p2, p3; string ln;
begin
    ns_n = 0;
    if (store_dir == "") return 0; end
    fh = fopen(ns_file(), O_READ);
    if (!fh) return 0; end
    while (!feof(fh) && ns_n < 16)
        ln = fgets(fh);
        while (len(ln) > 0 && (substr(ln, len(ln) - 1, 1) == chr(13) || substr(ln, len(ln) - 1, 1) == chr(10))) ln = substr(ln, 0, len(ln) - 1); end
        p1 = find(ln, chr(9));
        if (p1 > 0)
            p2 = find(ln, chr(9), p1 + 1);
            if (p2 > p1)
                p3 = find(ln, chr(9), p2 + 1);
                if (p3 > p2) ns_name[ns_n] = substr(ln, 0, p1); ns_url[ns_n] = substr(ln, p1 + 1, p2 - p1 - 1); ns_user[ns_n] = substr(ln, p2 + 1, p3 - p2 - 1); ns_pass[ns_n] = substr(ln, p3 + 1); ns_n++; end
            end
        end
    end
    fclose(fh);
end

function ns_save()
private int fh, i;
begin
    if (store_dir == "") return 0; end
    fh = fopen(ns_file(), O_WRITE);
    if (!fh) return 0; end
    for (i = 0; i < ns_n; i++) fputs(fh, ns_name[i] + chr(9) + ns_url[i] + chr(9) + ns_user[i] + chr(9) + ns_pass[i]); end
    fclose(fh);
end

// "https://nas.local:5006/video/x" -> "nas.local"
function string ns_host_of(string u)
private int p; string h;
begin
    p = find(u, "://");
    h = p >= 0 ? substr(u, p + 3) : u;
    p = find(h, "/"); if (p >= 0) h = substr(h, 0, p); end
    p = find(h, "@"); if (p >= 0) h = substr(h, p + 1); end
    return h;
end

// Alta de un servidor: direccion -> usuario -> clave (tres pantallas del teclado)
function net_add_start()
begin
    if (ns_n >= 16) toast(tr("t_ns_full")); return 0; end
    kb_open(tr("k_ns_url"), "https://", KB_NETURL);
end

function net_add_url(string u)
begin
    u = trim_text(u);
    if (substr(lcase(u), 0, 7) != "http://" && substr(lcase(u), 0, 8) != "https://" && substr(lcase(u), 0, 6) != "ftp://") toast(tr("t_bad_url")); return 0; end
    ns_tmp_url = u;
    kb_open(tr("k_ns_user"), "", KB_NETUSER);
end

function net_add_user(string u)
begin
    ns_tmp_user = trim_text(u);
    kb_secret_next = 1;
    kb_open(tr("k_ns_pass"), "", KB_NETPASS);
end

function net_add_pass(string pw)
begin
    ns_name[ns_n] = ns_host_of(ns_tmp_url); ns_url[ns_n] = ns_tmp_url; ns_user[ns_n] = ns_tmp_user; ns_pass[ns_n] = pw; ns_n++;
    ns_save();
    toast(tr("t_ns_saved"));
    if (dlna_mode == 1) dlna_list_servers(); end
end

function net_remove(int i)
private int k;
begin
    if (i < 0 || i >= ns_n) return 0; end
    for (k = i; k < ns_n - 1; k++) ns_name[k] = ns_name[k + 1]; ns_url[k] = ns_url[k + 1]; ns_user[k] = ns_user[k + 1]; ns_pass[k] = ns_pass[k + 1]; end
    ns_n--; ns_save();
    toast(tr("t_ns_removed"));
    dlna_list_servers();
end

function string trim_text(string t)
begin
    while (len(t) > 0 && (substr(t, 0, 1) == " " || substr(t, 0, 1) == chr(9))) t = substr(t, 1); end
    while (len(t) > 0 && (substr(t, len(t) - 1, 1) == " " || substr(t, len(t) - 1, 1) == chr(9))) t = substr(t, 0, len(t) - 1); end
    return t;
end
