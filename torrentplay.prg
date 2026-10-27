// ==========================================================================================================
//  torrentplay.prg - reproducir un torrent: un enlace magnet o un archivo .torrent (de una carpeta, de una direccion
//  o de un addon). El motor BitTorrent esta en libmod_video; aqui solo se lleva el proceso: buscar los archivos del
//  torrent, elegir cual ver si hay varios, esperar a que haya lo imprescindible y abrirlo.
//  Los datos se descargan en <almacen>/torrents y se borran al terminar (salvo que se pida conservarlos).
// ==========================================================================================================
const
    TOR_NEED_MB = 5;                     // MB que se esperan por delante del punto de reproduccion antes de abrir
end

global
    int    tor_job;                      // 0 nada, 1 buscando los archivos, 2 eligiendo archivo, 3 preparando el video
    int    tor_h;                        // torrent en curso (0 = ninguno)
    int    tor_playing;                  // 1 = el video que se ve viene de ese torrent (se libera al pararlo)
    int    tor_sel;                      // archivo elegido
    int    tor_pick[10];                 // archivos del menu de eleccion
    uint32 tor_t0;
    int    set_tor_keep, set_tor_up;     // ajustes: conservar lo descargado; subida (indice)
end

function int is_torrent_src(string p)
begin
    return lcase(substr(p, 0, 8)) == "magnet:?" || lcase(ext_of(p)) == "torrent";
end

// subida permitida a otros, en KB/s (0 = nunca)
function int tor_up_kb(int k)
begin
    switch (k)
        case 1: return 50; end
        case 2: return 200; end
        case 3: return 1000; end
    end
    return 0;
end

function tor_apply_settings()
begin
    torrent_upload_limit(tor_up_kb(set_tor_up) * 1024);
end

function tor_cleanup()
begin
    if (tor_h) torrent_remove(tor_h, !set_tor_keep); tor_h = 0; end
    tor_job = 0; tor_playing = 0;
    prog_stop();
end

// al arrancar se borra lo que quedo de una sesion anterior (si se salio con el torrent a medias), salvo que se conserve
function tor_purge()
private int dh; string nm, dir;
begin
    if (set_tor_keep) return 0; end
    dir = store_dir != "" ? join_path(store_dir, "torrents") : join_path(cd(), "torrents");
    dh = diropen(join_path(dir, "*"));
    if (!dh) return 0; end
    nm = dirread(dh);
    while (nm != "")
        if (len(nm) == 44 && lcase(ext_of(nm)) == "dat") fremove(join_path(dir, nm)); end            // solo los de 40 letras hexadecimales + .dat
        nm = dirread(dh);
    end
    dirclose(dh);
end

// abre el torrent: el resto lo hace tor_step() en cada fotograma
function int tor_begin(string src)
begin
    if (tor_job || tor_playing) tor_cleanup(); end
    close_preview();
    tor_h = torrent_add(src);
    if (tor_h <= 0) tor_h = 0; show_error(tr("s_torrent"), tr("t_tor_fail")); return 0; end
    tor_job = 1; tor_t0 = get_timer();
    prog_start(tr("s_tor_connect"), 1);
    return 1;
end

// el archivo elegido empieza a prepararse
function tor_use_file(int fi)
begin
    tor_sel = fi; torrent_select(tor_h, fi);
    tor_job = 3; tor_t0 = get_timer();
    prog_stop(); prog_start(tr("s_tor_buffer"), 1);
end

// ¿hay varios archivos que se puedan ver? entonces se pregunta cual
function tor_pick_file()
private int i, n, nm, best, k; string nme;
begin
    n = torrent_files(tor_h); nm = 0; best = torrent_main(tor_h);
    menu_clear();
    for (i = 0; i < n && menu_n < 9; i++)
        nme = torrent_file_name(tor_h, i);
        if (is_video(nme) || is_audio(nme))
            tor_pick[menu_n] = i;
            menu_add(fit_text(base_name(nme), 640) + "   " + fmt_size(torrent_file_size(tor_h, i)), MA_TOR_FILE + menu_n);
            nm++;
        end
    end
    if (nm == 0) tor_use_file(best >= 0 ? best : 0); return 0; end
    if (nm == 1) tor_use_file(tor_pick[0]); return 0; end
    menu_add(tr("m_cancel"), MA_CANCEL);
    prog_stop(); tor_job = 2;
    menu_show(tr("mt_tor_files"));
end

function tor_cancel()
begin
    tor_cleanup();
    toast(tr("t_tor_cancel"));
end

// un paso por fotograma (se cancela con atras / circulo)
function tor_step()
private int st, p, need; string u;
begin
    if (tor_job == 2) tor_cleanup(); return 0; end                      // el menu se cerro sin elegir
    if (ov_cancel_asked()) tor_cancel(); return 0; end
    st = torrent_state(tor_h);
    if (st == 2)
        u = torrent_error(tor_h); tor_cleanup();
        show_error(tr("s_torrent"), tr("t_tor_fail") + ": " + u); return 0;
    end
    if (tor_job == 1)
        ov_title = tr("s_tor_connect") + "   (" + torrent_peers(tor_h) + " " + tr("s_tor_peers") + ")";
        if (st == 1) tor_pick_file(); end
    elseif (tor_job == 3)
        p = torrent_ready(tor_h);
        need = TOR_NEED_MB * 1048576; if (need > torrent_file_size(tor_h, tor_sel) / 4) need = (int)(torrent_file_size(tor_h, tor_sel) / 4); end
        ov_pct = p < 100 ? p * 70 / 100 : 70 + (int)(torrent_buffered(tor_h) * 30 / (need > 0 ? need : 1));
        if (ov_pct > 99) ov_pct = 99; end
        ov_title = tr("s_tor_buffer") + "   " + (torrent_rate(tor_h) / 1024) + " KB/s   " + torrent_peers(tor_h) + " " + tr("s_tor_peers");
        if (p >= 100 && torrent_buffered(tor_h) >= need)
            u = torrent_url(tor_h, tor_sel);
            prog_stop(); tor_job = 0; tor_playing = 1;
            start_video(u);
            if (!vh) tor_cleanup(); end
        end
    end
end

// texto con la velocidad y los peers, para mostrar mientras se ve
function string tor_stats()
begin
    if (!tor_playing || !tor_h) return ""; end
    return "   " + (torrent_rate(tor_h) / 1024) + " KB/s  " + torrent_peers(tor_h) + " " + tr("s_tor_peers") + "  " + torrent_percent(tor_h) + "%";
end
