// ==========================================================================================================
//  update.prg - comprobar si hay una version nueva (la ultima release de GitHub). Solo avisa: no descarga nada.
// ==========================================================================================================
// "v1.1.2" / "1.1.2" -> 10102 (para comparar versiones)
function int ver_num(string v)
private int a, b, c, p;
begin
    if (substr(v, 0, 1) == "v" || substr(v, 0, 1) == "V") v = substr(v, 1); end
    a = atoi(v); p = find(v, ".");
    if (p < 0) return a * 10000; end
    v = substr(v, p + 1); b = atoi(v); p = find(v, ".");
    c = p < 0 ? 0 : atoi(substr(v, p + 1));
    return a * 10000 + b * 100 + c;
end

// pide a GitHub cual es la ultima version publicada (en segundo plano: la interfaz sigue viva)
function upd_begin(int manual)
begin
    if (upd_state || store_job || dl_job || xt_job || tor_job || ru_job || dlna_job) if (manual) toast(tr("t_ru_busy")); end return 0; end
    if (http_fetch_begin("https://api.github.com/repos/Rufidj/bennugd2-media-player/releases/latest", "", "GET", "") != 0) if (manual) toast(tr("s_update_fail")); end return 0; end
    upd_state = 1; upd_manual = manual; upd_t = 0;
end

// un paso por fotograma: al arrancar (unos segundos despues, con el explorador quieto) y mientras se espera la respuesta
function update_check()
private int st, n, p, q; string txt, tag;
begin
    if (upd_state == 0)
        if (set_updates && frame_n == 300 && state == ST_BROWSE && modal == M_NONE && store_dir != "" && getenv("MP_NOUPDATE") == "") upd_begin(0); end
        return 0;
    end
    upd_t++;
    st = http_fetch_poll();
    if (st == -1 && upd_t < 1200) return 0; end                    // sigue esperando (20 s como mucho)
    upd_state = 0;
    if (st != 200 || http_length() <= 0 || http_length() >= HTTP_MAX)
        if (upd_manual) toast(tr("s_update_fail")); end return 0;
    end
    n = http_read(&ad_buf[0], http_length());
    txt = ad_buf_str(0, n);
    p = find(txt, "\"tag_name\"");
    tag = "";
    if (p >= 0)
        p = find(txt, ":", p); q = find(txt, "\"", p + 1);
        if (q > 0) p = find(txt, "\"", q + 1); if (p > q) tag = substr(txt, q + 1, p - q - 1); end end
    end
    if (tag != "" && ver_num(tag) > ver_num(getenv("MP_APPVER") != "" ? getenv("MP_APPVER") : APP_VERSION))
        upd_new = tag; toast(tr("s_newver") + " " + tag + "   github.com/Rufidj/bennugd2-media-player/releases"); toast_t = 480;
    else
        upd_new = "";
        if (upd_manual) toast(tag == "" ? tr("s_update_fail") : tr("s_uptodate")); end
    end
    if (modal == M_SETTINGS) st_build(); end
end
