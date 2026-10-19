// ==========================================================================================================
//  xtream.prg - cuentas de paneles IPTV con la API de Xtream Codes.
//  El reproductor pregunta por el servidor, el usuario y la clave, llama a player_api.php y muestra
//  el árbol de categorías de TV en vivo, VOD y series. Los canales se reproducen con la URL que
//  usa el panel: <servidor>/live/<usuario>/<clave>/<id>.ts
// ==========================================================================================================
global
    string xt_server = "", xt_user = "", xt_pass = "";
    int    xt_level = 0;              // 0 = tipos, 1 = categorías, 2 = canales, 3 = episodios
    int    xt_type = 0;               // 0 = TV en vivo, 1 = VOD, 2 = series
    int    xt_job = 0;                // 1 = pedir categorías, 2 = pedir canales, 3 = pedir episodios
    int    xt_screen = 0;             // 1 = la pantalla de Xtream está abierta
    string xt_cat_id[600], xt_cat_name[600]; int xt_cat_n = 0;
    string xt_str_id[900], xt_str_name[900], xt_str_icon[900], xt_str_ext[900], xt_str_src[900]; int xt_str_n = 0;
    string xt_ser_id[400], xt_ser_name[400], xt_ser_icon[400]; int xt_ser_n = 0;
    string xt_epi_id[600], xt_epi_name[600], xt_epi_src[600]; int xt_epi_n = 0;
    string xt_body = "";              // última respuesta de la API
    string xt_cat_sel = "", xt_ser_sel = "";
    int    xt_err = 0;                // último error de la API

declare function string xt_url(string path) end
declare function int xt_get(string path) end
declare function int xt_load(int what) end
declare function string xt_item(string obj, string field) end
declare function string xt_next_obj(string body, int pos) end
declare function int xt_open_level(int level) end
declare function string xt_stream_url(int i) end
declare function int xt_step() end
declare function int xt_enter(string name) end

// --------------------------------------------------------------------------------------------- cuentas
// la URL de la API con el usuario y la clave
function string xt_url(string path)
begin
    return xt_server + path + "&username=" + au_esc(xt_user) + "&password=" + au_esc(xt_pass);
end

// pide algo a la API y deja la respuesta en xt_body
function int xt_get(string path)
private int st, n;
begin
    xt_err = 0;
    if (xt_server == "") return 0; end
    st = http_fetch(xt_url(path), "", "GET", "");
    if (st != 200) xt_err = st > 0 ? st : 1; return 0; end
    n = http_length();
    if (n <= 0) xt_err = -1; return 0; end
    if (n >= HTTP_MAX) n = HTTP_MAX - 1; end
    xt_body = ad_buf_str(0, http_read(&ad_buf[0], n));
    return 1;
end

// --------------------------------------------------------------------------------------------- JSON
// el valor de un campo de un objeto JSON: {"name":"x"} -> "x"
// los valores sin comillas (numeros, true/false) tambien se devuelven como texto
function string xt_item(string obj, string field)
private int p, q; string key;
begin
    key = chr(34) + field + chr(34);
    p = find(obj, key);
    if (p < 0) return ""; end
    p += len(key);
    while (p < len(obj) && substr(obj, p, 1) != ":") p++; end
    p++;
    while (p < len(obj) && (substr(obj, p, 1) == " " || substr(obj, p, 1) == chr(9) || substr(obj, p, 1) == chr(10) || substr(obj, p, 1) == chr(13))) p++; end
    if (substr(obj, p, 1) != chr(34))
        q = p;                                   // numero o booleano: hasta la coma o la llave
        while (q < len(obj) && substr(obj, q, 1) != "," && substr(obj, q, 1) != "}" && substr(obj, q, 1) != "]") q++; end
        return substr(obj, p, q - p);
    end
    p++; q = p;
    while (q < len(obj) && substr(obj, q, 1) != chr(34)) q++; end
    return substr(obj, p, q - p);
end

// el siguiente objeto "{}" de un array JSON
function string xt_next_obj(string body, int pos)
private int p, q;
begin
    p = find(body, "{", pos);
    if (p < 0) return ""; end
    q = find(body, "}", p);
    if (q < 0) return ""; end
    return substr(body, p, q - p + 1);
end

// --------------------------------------------------------------------------------------------- carga
// what: 0 = categorías, 1 = canales, 2 = series, 3 = episodios
function int xt_load(int what)
private int pos, n; string obj, cid, nm, ic, ex, sc;
begin
    xt_cat_n = 0; xt_str_n = 0; xt_ser_n = 0; xt_epi_n = 0;
    if (what == 0)
        if (!xt_get("/player_api.php?action=get_" + (xt_type == 0 ? "live" : (xt_type == 1 ? "vod" : "series")) + "_categories")) return 0; end
        pos = 0; n = 0;
        while (n < 600)
            obj = xt_next_obj(xt_body, pos);
            if (obj == "") break; end
            pos = find(xt_body, "}", pos) + 1;
            cid = xt_item(obj, "category_id"); nm = xt_item(obj, "category_name");
            if (cid != "" && nm != "")
                xt_cat_id[xt_cat_n] = cid; xt_cat_name[xt_cat_n] = nm; xt_cat_n++; n++;
            end
        end
        return 1;
    end
    if (what == 1)
        if (xt_type == 2)
            if (!xt_get("/player_api.php?action=get_series")) return 0; end
            pos = 0; n = 0;
            while (n < 400)
                obj = xt_next_obj(xt_body, pos);
                if (obj == "") break; end
                pos = find(xt_body, "}", pos) + 1;
                cid = xt_item(obj, "series_id"); nm = xt_item(obj, "name"); ic = xt_item(obj, "cover");
                if (cid != "" && nm != "")
                    xt_ser_id[xt_ser_n] = cid; xt_ser_name[xt_ser_n] = nm; xt_ser_icon[xt_ser_n] = ic; xt_ser_n++; n++;
                end
            end
            return 1;
        end
        if (!xt_get("/player_api.php?action=get_" + (xt_type == 0 ? "live" : "vod") + "_streams&category_id=" + au_esc(xt_cat_sel))) return 0; end
        pos = 0; n = 0;
        while (n < 900)
            obj = xt_next_obj(xt_body, pos);
            if (obj == "") break; end
            pos = find(xt_body, "}", pos) + 1;
            cid = xt_item(obj, "stream_id"); nm = xt_item(obj, "name"); ic = xt_item(obj, "stream_icon"); ex = xt_item(obj, "container_extension"); sc = xt_item(obj, "direct_source");
            if (cid != "" && nm != "")
                xt_str_id[xt_str_n] = cid; xt_str_name[xt_str_n] = nm; xt_str_icon[xt_str_n] = ic;
                xt_str_ext[xt_str_n] = (ex != "") ? ex : (xt_type == 0 ? "ts" : "mp4");
                xt_str_src[xt_str_n] = sc; xt_str_n++; n++;
            end
        end
        return 1;
    end
    if (what == 2)
        if (!xt_get("/player_api.php?action=get_series_info&series_id=" + au_esc(xt_ser_sel))) return 0; end
        // los episodios vienen dentro de un objeto: "episodes":[{"id":"1","title":"..."}]
        pos = find(xt_body, "\"episodes\"");
        if (pos < 0) return 0; end
        n = 0;
        while (n < 600)
            obj = xt_next_obj(xt_body, pos);
            if (obj == "") break; end
            pos = find(xt_body, "}", pos) + 1;
            cid = xt_item(obj, "id"); nm = xt_item(obj, "title"); sc = xt_item(obj, "direct_source");
            if (cid == "") cid = xt_item(obj, "episode_id"); end
            if (nm == "") nm = xt_item(obj, "episode_num"); end
            if (cid != "" && nm != "")
                xt_epi_id[xt_epi_n] = cid; xt_epi_name[xt_epi_n] = nm; xt_epi_src[xt_epi_n] = sc; xt_epi_n++; n++;
            end
        end
        return 1;
    end
    return 0;
end

// --------------------------------------------------------------------------------------------- pantalla
// monta el nivel actual (0 = tipos, 1 = categorías, 2 = canales, 3 = episodios)
function int xt_open_level(int level)
private int i;
begin
    xt_level = level;
    n_entries = 0; sel = 0; top_row = 0; dir_ver++;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; n_entries = 1;
    if (level == 0)
        entries[1] = tr("xt_live"); entry_dir[1] = K_XCAT; entry_url[1] = "live"; entry_size[1] = 0; entry_logo[1] = ""; n_entries = 2;
        entries[2] = tr("xt_vod"); entry_dir[2] = K_XCAT; entry_url[2] = "vod"; entry_size[2] = 0; entry_logo[2] = ""; n_entries = 3;
        entries[3] = tr("xt_series"); entry_dir[3] = K_XCAT; entry_url[3] = "series"; entry_size[3] = 0; entry_logo[3] = ""; n_entries = 4;
        return 1;
    end
    if (level == 1)
        for (i = 0; i < xt_cat_n; i++)
            entries[n_entries] = xt_cat_name[i]; entry_dir[n_entries] = K_XCAT; entry_url[n_entries] = xt_cat_id[i];
            entry_size[n_entries] = 0; entry_logo[n_entries] = ""; n_entries++;
        end
        return 1;
    end
    if (level == 2)
        if (xt_type == 2)
            for (i = 0; i < xt_ser_n; i++)
                entries[n_entries] = xt_ser_name[i]; entry_dir[n_entries] = K_XSER; entry_url[n_entries] = xt_ser_id[i];
                entry_size[n_entries] = 0; entry_logo[n_entries] = xt_ser_icon[i]; n_entries++;
            end
            return 1;
        end
        for (i = 0; i < xt_str_n; i++)
            entries[n_entries] = xt_str_name[i]; entry_dir[n_entries] = K_XSTR; entry_url[n_entries] = xt_str_id[i];
            entry_size[n_entries] = 0; entry_logo[n_entries] = xt_str_icon[i]; n_entries++;
        end
        return 1;
    end
    if (level == 3)
        for (i = 0; i < xt_epi_n; i++)
            entries[n_entries] = xt_epi_name[i]; entry_dir[n_entries] = K_XSTR; entry_url[n_entries] = xt_epi_id[i];
            entry_size[n_entries] = 0; entry_logo[n_entries] = ""; n_entries++;
        end
        return 1;
    end
    return 0;
end

// la URL de reproducción de un canal
function string xt_stream_url(int i)
private int k;
begin
    k = i - 1;
    if (xt_level == 3)
        if (k >= 0 && k < xt_epi_n && xt_epi_src[k] != "") return xt_epi_src[k]; end
        return xt_server + "/series/" + xt_user + "/" + xt_pass + "/" + xt_ser_sel + "/" + entry_url[i] + ".ts";
    end
    if (k >= 0 && k < xt_str_n && xt_str_src[k] != "") return xt_str_src[k]; end
    if (xt_type == 1) return xt_server + "/movie/" + xt_user + "/" + xt_pass + "/" + entry_url[i] + "." + xt_str_ext[sel - 1]; end
    return xt_server + "/live/" + xt_user + "/" + xt_pass + "/" + entry_url[i] + ".ts";
end

// --------------------------------------------------------------------------------------------- entrada
// abre la pantalla de Xtream con la cuenta guardada
function int xt_enter(string name)
private int st;
begin
    au_load(join_path(lists_dir, name + ".m3u"));
    if (au_mode != "xtream") return 0; end
    xt_server = au_server; xt_user = au_user; xt_pass = au_pass;
    if (xt_server == "") return 0; end
    xt_screen = 1; xt_level = 0; xt_type = 0; xt_cat_sel = ""; xt_ser_sel = "";
    cur_list = ""; cur_dir = lists_dir;
    xt_open_level(0);
    return 1;
end

// un paso de la carga (una petición por fotograma, como en la tienda)
function int xt_step()
private int ok, what;
begin
    what = xt_job;
    xt_job = 0;
    if (what == 1) ok = xt_load(0);
    elseif (what == 2) ok = xt_load(1);
    else ok = xt_load(2); end
    if (!ok)
        show_error(tr("mt_account"), tr("t_xt_err") + " " + xt_err);
        return 0;
    end
    if (what == 1) xt_open_level(1);
    elseif (what == 2) xt_open_level(2);
    else xt_open_level(3); end
    return 1;
end
