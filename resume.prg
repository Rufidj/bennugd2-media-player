// ==========================================================================================================
//  resume.prg - recordar donde se dejo cada video (local, de una lista, de un addon o un torrent) y continuar desde ahi.
//  Se guarda en <almacen>/resume.cfg: una linea por video, "posicion TAB duracion TAB clave" (la clave es la ruta o direccion;
//  en un torrent, el nombre del torrent + el archivo + su tamano, porque la direccion local cambia cada vez). Solo se recuerdan
//  los de mas de 3 minutos que se dejaron pasados los 30 segundos y antes del 95 %. Al abrir uno recordado se pregunta.
// ==========================================================================================================
const
    RS_MAX = 300;
end

global
    string rs_key[RS_MAX]; int rs_pos[RS_MAX]; int rs_dur[RS_MAX]; int rs_n;
    string rs_cur_key = "";              // clave del video que se esta viendo
    int    rs_start_pos;                 // donde hay que empezar el que se acaba de abrir (ms)
    int    rs_save_t;                    // fotogramas desde el ultimo guardado periodico
    int    rs_skip;                      // rs_skip: no preguntar (viene de la ventana); rs_wait (en torrentplay.prg): la ventana esta abierta
    string rs_pending_path = ""; int rs_pending_pos;
    int    set_resume = 1;               // ajuste: recordar donde se dejo
end

function string rs_clean(string s)
private string r; int i, c;
begin
    r = "";
    for (i = 0; i < len(s); i++)
        c = asc(substr(s, i, 1));
        if (c == 9 || c == 10 || c == 13) r += " "; else r += substr(s, i, 1); end
    end
    return r;
end

function rs_load()
private int fh, p1, p2; string ln;
begin
    rs_n = 0;
    if (store_dir == "") return 0; end
    fh = fopen(join_path(store_dir, "resume.cfg"), O_READ);
    if (!fh) return 0; end
    while (!feof(fh) && rs_n < RS_MAX)
        ln = fgets(fh);
        while (len(ln) > 0 && (substr(ln, len(ln) - 1, 1) == chr(13) || substr(ln, len(ln) - 1, 1) == chr(10))) ln = substr(ln, 0, len(ln) - 1); end
        p1 = find(ln, chr(9));
        if (p1 > 0)
            p2 = find(ln, chr(9), p1 + 1);
            if (p2 > p1) rs_pos[rs_n] = atoi(substr(ln, 0, p1)); rs_dur[rs_n] = atoi(substr(ln, p1 + 1, p2 - p1 - 1)); rs_key[rs_n] = substr(ln, p2 + 1); rs_n++; end
        end
    end
    fclose(fh);
end

function rs_save()
private int fh, i;
begin
    if (store_dir == "") return 0; end
    fh = fopen(join_path(store_dir, "resume.cfg"), O_WRITE);
    if (!fh) return 0; end
    for (i = 0; i < rs_n; i++) fputs(fh, rs_pos[i] + chr(9) + rs_dur[i] + chr(9) + rs_key[i]); end
    fclose(fh);
end

function int rs_find(string k)
private int i;
begin
    for (i = 0; i < rs_n; i++) if (rs_key[i] == k) return i; end end
    return -1;
end

function rs_set(string k, int pos, int dur)
private int i;
begin
    i = rs_find(k);
    if (i >= 0)                                           // el mas reciente va el ultimo: se mueve al final
        while (i < rs_n - 1) rs_key[i] = rs_key[i + 1]; rs_pos[i] = rs_pos[i + 1]; rs_dur[i] = rs_dur[i + 1]; i++; end
        rs_n--; i = -1;
    end
    if (i < 0)
        if (rs_n >= RS_MAX) for (i = 1; i < rs_n; i++) rs_key[i - 1] = rs_key[i]; rs_pos[i - 1] = rs_pos[i]; rs_dur[i - 1] = rs_dur[i]; end rs_n--; end   // el mas antiguo se descarta
        i = rs_n; rs_key[i] = k; rs_n++;
    end
    rs_pos[i] = pos; rs_dur[i] = dur;
    rs_save();
end

function rs_remove(string k)
private int i, j;
begin
    i = rs_find(k);
    if (i < 0) return 0; end
    for (j = i + 1; j < rs_n; j++) rs_key[j - 1] = rs_key[j]; rs_pos[j - 1] = rs_pos[j]; rs_dur[j - 1] = rs_dur[j]; end
    rs_n--;
    rs_save();
end

// la clave del video que se abre ("" = no se recuerda: directos y emisiones HLS)
function string rs_key_of(string path)
begin
    if (hls_url != "") return ""; end
    if (tor_playing && tor_h) return "tor:" + rs_clean(torrent_name(tor_h)) + "/" + rs_clean(torrent_file_name(tor_h, tor_sel)) + "#" + tor_fsize; end
    return rs_clean(path);
end

// ¿vale la pena recordar esta posicion?
function int rs_worth(int p, int d)
begin
    return d >= 180000 && p >= 30000 && p < d * 95 / 100;
end

// se deja el video (parar, pasar a otro...): se guarda donde iba, o se olvida si lo acabo / apenas lo empezo
function rs_on_stop()
private int p, d;
begin
    if (!set_resume || rs_cur_key == "" || !vh) rs_cur_key = ""; return 0; end
    d = vdur(); p = vpos();
    if (getenv("MP_DEBUG") != "") say("RS stop key=[" + rs_cur_key + "] pos=" + p + " dur=" + d); end
    if (rs_worth(p, d)) rs_set(rs_cur_key, p, d); else rs_remove(rs_cur_key); end
    rs_cur_key = "";
end

// cada unos 15 segundos mientras se ve (por si se cierra la aplicacion)
function rs_tick()
private int p, d;
begin
    if (!set_resume || rs_cur_key == "" || !vh) return 0; end
    rs_save_t++;
    if (rs_save_t < 900) return 0; end
    rs_save_t = 0;
    d = vdur(); p = vpos();
    if (rs_worth(p, d)) rs_set(rs_cur_key, p, d); end
end

// ¿hay algo recordado para esto? si lo hay, pregunta y devuelve 1 (el video se abrira desde la ventana)
function int rs_ask(string path)
private string k; int i;
begin
    if (!set_resume || rs_skip) return 0; end
    k = rs_key_of(path);
    if (k == "") return 0; end
    i = rs_find(k);
    if (i < 0) return 0; end
    rs_pending_path = path; rs_pending_pos = rs_pos[i]; rs_wait = 1;
    menu_clear();
    menu_add(tr("m_resume") + " " + fmt_time(rs_pos[i]), MA_RS_YES);
    menu_add(tr("m_restart"), MA_RS_NO);
    menu_show(tr("mt_resume"));
    return 1;
end
