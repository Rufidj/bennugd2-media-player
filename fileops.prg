// ==========================================================================================================
//  fileops.prg - copiar, mover y borrar archivos y carpetas desde el explorador, con barra de progreso.
//  Solo usa funciones de BennuGD (fopen/fread/fwrite, mkdir, rm, rmdir, fmove) y trabaja un poco en cada
//  fotograma, asi la pantalla sigue viva, la barra avanza y se puede cancelar.
//
//  Primero se "planifica": se recorren las carpetas y se anota cada archivo/carpeta (con su destino).
//  Despues se ejecuta el plan: copiar = carpetas primero y archivos por trozos; borrar = al reves (lo de
//  dentro antes que la carpeta). Mover = renombrar (instantaneo en el mismo disco) y, si no se puede,
//  copiar y despues borrar el original. Nunca se pisa nada: el que pega elige un nombre libre.
// ==========================================================================================================
const
    FO_MAX = 20000;                      // entradas (archivos + carpetas) que admite un trabajo
    FO_CHUNK = 262144;                   // bytes por lectura
    FO_COPY = 1; FO_MOVE = 2; FO_DEL = 3; FO_INFO = 4;
end

global
    string clip_path[255]; int clip_dir[255]; int clip_n; int clip_mode;    // portapapeles: rutas, si son carpeta, cuantas y 1 copiar / 2 mover
    int    entry_mark[MAX_ENTRIES];                                         // elementos marcados en la carpeta que se esta viendo
    int    mark_n;
    string fo_src[FO_MAX]; string fo_dst[FO_MAX]; int fo_isdir[FO_MAX]; int fo_size[FO_MAX];
    int    fo_n, fo_scan_i, fo_run_i, fo_top;                              // entradas, siguiente a explorar, siguiente a ejecutar, elementos de primer nivel
    int    fo_job, fo_phase, fo_mode;                                      // 0 libre; fase 1 planificar, 2 copiar, 3 borrar; modo
    int    fo_total, fo_done, fo_errs, fo_moved;
    string fo_err1 = "", fo_name = "", fo_after = "";
    int    fo_fi, fo_fo;                                                   // archivo que se esta copiando (lectura / escritura)
    byte pointer fo_buf;
    int    fo_info_bytes, fo_info_files, fo_info_dirs;
    string fo_i_mod = "", fo_i_cre = "", fo_i_path = ""; int fo_i_hid, fo_i_ro, fo_i_isdir;   // propiedades del elemento (cuando es uno solo)
    string fo_in[255]; int fo_in_dir[255]; int fo_in_n; string fo_cap = "";
    int    fo_delafter;                                                    // mover entre discos: tras copiar hay que borrar los originales
end

declare function int fo_start(int mode) end

// ¿existe algo (archivo o carpeta) en esa ruta?
function int path_exists(string p)
private int dh;
begin
    if (fexists(p)) return 1; end
    dh = diropen(join_path(p, "*"));
    if (dh) dirclose(dh); return 1; end
    return 0;
end

function int path_is_dir(string p)
private int dh;
begin
    dh = diropen(join_path(p, "*"));
    if (dh) dirclose(dh); return 1; end
    return 0;
end

// un nombre que no existe en la carpeta: "nombre", "nombre (2)", "nombre (3)"...  (la extension se respeta)
function string unique_name(string dir, string nm)
private string stem, ex; int k, p;
begin
    if (!path_exists(join_path(dir, nm))) return nm; end
    stem = nm; ex = "";
    p = len(nm) - 1;
    while (p > 0 && substr(nm, p, 1) != ".") p--; end
    if (p > 0 && len(nm) - p <= 6) stem = substr(nm, 0, p); ex = substr(nm, p, len(nm) - p); end
    for (k = 2; k < 1000; k++)
        if (!path_exists(join_path(dir, stem + " (" + k + ")" + ex))) return stem + " (" + k + ")" + ex; end
    end
    return nm;
end

// ---------------------------------------------------------------- marcas y portapapeles
function marks_clear()
private int i;
begin
    for (i = 0; i < MAX_ENTRIES; i++) entry_mark[i] = 0; end
    mark_n = 0;
end

function mark_toggle(int i)
begin
    if (i <= 0 || i >= n_entries || entries[i] == "..") return 0; end
    entry_mark[i] = !entry_mark[i];
    mark_n += entry_mark[i] ? 1 : -1;
end

function mark_all()
private int i;
begin
    mark_n = 0;
    for (i = 0; i < n_entries; i++)
        entry_mark[i] = (i > 0 && entries[i] != ".." && (entry_dir[i] == K_FILE || entry_dir[i] == K_DIR || entry_dir[i] == K_LIST));
        if (entry_mark[i]) mark_n++; end
    end
end

// ¿se puede hacer algo con esta entrada? (solo archivos y carpetas reales)
function int entry_is_real(int i)
begin
    if (i < 0 || i >= n_entries || entries[i] == "..") return 0; end
    return entry_dir[i] == K_FILE || entry_dir[i] == K_DIR || entry_dir[i] == K_LIST;
end

// lo marcado (o, si no hay nada marcado, la entrada seleccionada) pasa a fo_in; devuelve cuantos son
function int sel_take()
private int i;
begin
    fo_in_n = 0;
    for (i = 0; i < n_entries && fo_in_n < 255; i++)
        if (entry_mark[i] && entry_is_real(i)) fo_in[fo_in_n] = join_path(cur_dir, entries[i]); fo_in_dir[fo_in_n] = entry_dir[i] == K_DIR; fo_in_n++; end
    end
    if (fo_in_n == 0 && entry_is_real(sel)) fo_in[0] = join_path(cur_dir, entries[sel]); fo_in_dir[0] = entry_dir[sel] == K_DIR; fo_in_n = 1; end
    return fo_in_n;
end

// copiar / mover: lo seleccionado se guarda en el portapapeles
function int clip_take(int mode)
private int i;
begin
    sel_take();
    for (i = 0; i < fo_in_n; i++) clip_path[i] = fo_in[i]; clip_dir[i] = fo_in_dir[i]; end
    clip_n = fo_in_n; clip_mode = mode;
    return clip_n;
end

// tamano de un archivo (abriendolo; hace falta para pesar bien lo que se copia en el primer nivel)
function int file_bytes(string path)
private int fh, n;
begin
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    n = flength(fh);
    fclose(fh);
    return n;
end

// ---------------------------------------------------------------- el trabajo
function fo_note_error(string what, string path)
begin
    fo_errs++;
    if (fo_err1 == "") fo_err1 = what + ": " + base_name(path); end
end

function fo_add(string s, string d, int isdir, int sz)
begin
    if (fo_n >= FO_MAX) fo_note_error("too many", s); return 0; end
    fo_src[fo_n] = s; fo_dst[fo_n] = d; fo_isdir[fo_n] = isdir; fo_size[fo_n] = sz;
    fo_n++;
end

// bytes con su tamano legible: "9.4 MB (9836112 bytes)"
function string fo_bytes(int b)
begin
    if (b <= 0) return "0 bytes"; end
    if (b < 1024) return b + " bytes"; end
    return fmt_size(b) + " (" + b + " bytes)";
end

// fecha, atributos... del elemento: solo se pueden leer recorriendo su carpeta
function fo_gather(string path)
private int dh; string nm, want;
begin
    fo_i_mod = ""; fo_i_cre = ""; fo_i_hid = 0; fo_i_ro = 0; fo_i_path = path;      // (las fechas solo se muestran si el sistema las da: en algunos aparece 1900)
    want = base_name(path);
    dh = diropen(join_path(parent_of(path), "*"));
    if (!dh) return 0; end
    nm = dirread(dh);
    while (nm != "")
        if (nm == want) fo_i_mod = fileinfo.modified; fo_i_cre = fileinfo.created; fo_i_hid = fileinfo.hidden; fo_i_ro = fileinfo.readonly; break; end
        nm = dirread(dh);
    end
    dirclose(dh);
    if (find(fo_i_mod, "1900") >= 0) fo_i_mod = ""; end
    if (find(fo_i_cre, "1900") >= 0) fo_i_cre = ""; end
end

function fo_line(string t)
begin
    menu_add(fit_text(utf8_to_latin1(t), 780), MA_CANCEL);
end

// ventana de propiedades: una linea por dato (nombre, ruta, tipo, tamano exacto, fechas, atributos, y en video/audio resolucion, duracion y pistas)
function fo_show_info()
private int h, n, k; string t, ex;
begin
    menu_clear();
    if (fo_in_n == 1)
        ex = lcase(ext_of(fo_i_path));
        fo_line(tr("p_name") + base_name(fo_i_path));
        menu_add(tail_fit(utf8_to_latin1(tr("p_path") + parent_of(fo_i_path)), 780), MA_CANCEL);
        if (fo_i_isdir) t = tr("p_k_folder");
        elseif (is_video(fo_i_path)) t = tr("p_k_video") + " " + ucase(ex);
        elseif (is_audio(fo_i_path)) t = tr("p_k_audio") + " " + ucase(ex);
        elseif (is_image(fo_i_path)) t = tr("p_k_image") + " " + ucase(ex);
        elseif (ex == "m3u" || ex == "m3u8") t = tr("p_k_list");
        else t = tr("p_k_file") + (ex != "" ? " " + ucase(ex) : ""); end
        fo_line(tr("p_type") + t);
        fo_line(tr("s_size") + fo_bytes(fo_info_bytes));
        if (fo_i_isdir) fo_line(tr("p_contents") + fo_info_files + " " + tr("p_files") + ", " + (fo_info_dirs - 1) + " " + tr("p_folders")); end
        if (fo_i_mod != "") fo_line(tr("p_modified") + fo_i_mod); end
        if (fo_i_cre != "" && fo_i_cre != fo_i_mod) fo_line(tr("p_created") + fo_i_cre); end
        t = (fo_i_hid ? tr("p_hidden") : "") + (fo_i_hid && fo_i_ro ? ", " : "") + (fo_i_ro ? tr("p_readonly") : "");
        if (t != "") fo_line(tr("p_attr") + t); end
        if (!fo_i_isdir && is_image(fo_i_path))
            h = video_open(fo_i_path);
            if (h) fo_line(tr("s_res") + video_width(h) + "x" + video_height(h)); video_close(h); end
        end
        if (!fo_i_isdir && (is_video(fo_i_path) || is_audio(fo_i_path)))
            h = video_open(fo_i_path);
            if (h)
                if (!video_is_audio_only(h)) fo_line(tr("s_res") + video_width(h) + "x" + video_height(h)); end
                k = video_duration(h);
                if (k > 0) fo_line(tr("s_dur") + fmt_time(k)); end
                n = video_audio_tracks(h); t = "";
                for (k = 0; k < n && k < 6; k++) t += (k > 0 ? ", " : "") + lang_or_dash(video_audio_lang(h, k)); end
                fo_line(tr("s_audio_n") + n + "): " + t);
                n = video_subtitle_tracks(h); t = "";
                for (k = 0; k < n && k < 6; k++) t += (k > 0 ? ", " : "") + lang_or_dash(video_subtitle_lang(h, k)); end
                if (n > 0) fo_line(tr("s_subs_n") + n + "): " + t); end
                video_close(h);
            end
        end
    else
        fo_line(fo_in_n + " " + tr("p_sel"));
        menu_add(tail_fit(utf8_to_latin1(tr("p_path") + cur_dir), 780), MA_CANCEL);
        fo_line(tr("p_contents") + fo_info_files + " " + tr("p_files") + ", " + fo_info_dirs + " " + tr("p_folders"));
        fo_line(tr("s_size") + fo_bytes(fo_info_bytes));
    end
    menu_add(tr("m_back"), MA_CANCEL);
    menu_sel = menu_n - 1;
    menu_show(tr("m_props"));
end

function fo_finish(int st)                    // st: 0 bien, -2 cancelado
begin
    if (fo_fi) fclose(fo_fi); fo_fi = 0; end
    if (fo_fo) fclose(fo_fo); fo_fo = 0; end
    if (fo_buf) free(fo_buf); fo_buf = 0; end
    fo_job = 0; fo_phase = 0; prog_stop();
    if (fo_mode == FO_INFO) fo_show_info(); return 0; end
    if (fo_mode == FO_MOVE && clip_mode == 2 && st == 0 && fo_errs == 0) clip_n = 0; end
    read_dir();
    if (st == -2)
        toast(tr("t_fo_cancel"));
    elseif (fo_errs > 0)
        show_error(tr("mt_files"), tr("t_fo_errors") + " " + fo_errs + ". " + fo_err1);
    else
        toast(tr("t_fo_done"));
    end
end

// prepara el trabajo con lo que hay en clip_path (copiar / mover, destino cur_dir) o con la seleccion (borrar / datos)
function int fo_start(int mode)
private int i, k, isd, sz; string nm, dpath, spath;
begin
    if (fo_job) return 0; end
    fo_mode = mode; fo_n = 0; fo_scan_i = 0; fo_run_i = 0; fo_errs = 0; fo_err1 = ""; fo_done = 0; fo_total = 0; fo_moved = 0; fo_delafter = 0;
    fo_info_bytes = 0; fo_info_files = 0; fo_info_dirs = 0;
    if (mode == FO_DEL || mode == FO_INFO)
        if (sel_take() == 0) return 0; end
    else
        fo_in_n = clip_n;
        for (i = 0; i < clip_n; i++) fo_in[i] = clip_path[i]; fo_in_dir[i] = clip_dir[i]; end
    end
    if (mode == FO_INFO && fo_in_n == 1) fo_i_isdir = fo_in_dir[0]; fo_gather(fo_in[0]); end
    for (i = 0; i < fo_in_n; i++)
        spath = fo_in[i]; isd = fo_in_dir[i];
        if (mode == FO_COPY || mode == FO_MOVE)
            if (isd && (cur_dir == spath || substr(cur_dir, 0, len(spath) + 1) == spath + "/"))
                fo_note_error(tr("t_fo_inside"), spath); continue;
            end
            nm = unique_name(cur_dir, base_name(spath));
            dpath = join_path(cur_dir, nm);
            if (mode == FO_MOVE && parent_of(spath) == cur_dir) continue; end        // moverlo a donde ya esta no hace nada
            if (mode == FO_MOVE && fmove(spath, dpath) == 0) fo_moved++; continue; end       // mismo disco: instantaneo
        else
            dpath = "";
        end
        fo_add(spath, dpath, isd, isd ? 0 : file_bytes(spath));
    end
    fo_top = fo_n;
    if (fo_n == 0)
        if (fo_moved > 0 || fo_errs > 0) fo_finish(0); end
        return 0;
    end
    fo_buf = mem_alloc(FO_CHUNK);
    fo_job = 1; fo_phase = 1;
    fo_name = "";
    fo_cap = (mode == FO_COPY ? tr("s_copying") : (mode == FO_MOVE ? tr("s_moving") : (mode == FO_DEL ? tr("s_deleting") : tr("s_scanning"))));
    prog_start(fo_cap, 1); return 1;
end

// planificar: explora unas cuantas carpetas por fotograma
function fo_plan_step()
private int dh, budget, q; string nm, p;
begin
    budget = 60;
    while (fo_scan_i < fo_n && budget > 0)
        p = fo_src[fo_scan_i];
        if (fo_isdir[fo_scan_i])
            // borrar un enlace a carpeta: se quita el enlace, nunca lo que hay dentro
            if (fo_mode == FO_DEL && rm(p) == 1) fo_isdir[fo_scan_i] = 2; fo_done++; fo_scan_i++; continue; end
            dh = diropen(join_path(p, "*"));
            if (dh)
                nm = dirread(dh);
                while (nm != "")
                    if (nm != "." && nm != "..")
                        fo_add(join_path(p, nm), fo_mode == FO_DEL || fo_mode == FO_INFO ? "" : join_path(fo_dst[fo_scan_i], nm), fileinfo.directory, fileinfo.size);
                    end
                    nm = dirread(dh);
                end
                dirclose(dh);
            else
                fo_note_error("cannot read", p);
            end
        end
        fo_scan_i++; budget--;
    end
    if (fo_scan_i < fo_n) return 0; end
    // plan terminado: se cuenta lo que hay que hacer
    fo_total = 0;
    for (q = 0; q < fo_n; q++)
        if (fo_isdir[q] == 2) continue; end
        if (fo_isdir[q]) fo_info_dirs++; else fo_info_files++; fo_info_bytes += fo_size[q]; end
        fo_total += fo_size[q] + 4096;
    end
    fo_done = 0;
    if (fo_mode == FO_INFO) fo_finish(0); return 0; end
    fo_phase = (fo_mode == FO_DEL) ? 3 : 2;
    fo_run_i = (fo_phase == 3) ? fo_n - 1 : 0;
    fo_total = (fo_phase == 3) ? fo_n : fo_total;
    if (fo_total <= 0) fo_total = 1; end
end

function fo_progress()
private int p;
begin
    p = fo_done * 100 / fo_total;
    if (fo_delafter) p = 90 + p / 10; else if (fo_mode == FO_MOVE) p = p * 9 / 10; end end
    if (p > 99) p = 99; end
    ov_pct = p;
end

// copiar: carpetas y archivos por trozos (unos cuantos trozos por fotograma)
function fo_copy_step()
private int turns, n, i;
begin
    turns = 4;
    while (turns > 0 && fo_run_i < fo_n)
        i = fo_run_i;
        if (fo_isdir[i] == 2) fo_run_i++; continue; end
        if (fo_isdir[i])
            if (!path_is_dir(fo_dst[i]) && mkdir(fo_dst[i]) != 0) fo_note_error("cannot create", fo_dst[i]); end
            fo_done += 4096; fo_run_i++; turns--; continue;
        end
        if (!fo_fi)                                           // abrir origen y destino
            fo_name = base_name(fo_src[i]);
            fo_fi = fopen(fo_src[i], O_READ);
            if (!fo_fi) fo_note_error("cannot read", fo_src[i]); fo_done += fo_size[i] + 4096; fo_run_i++; continue; end
            fo_fo = fopen(fo_dst[i], O_WRITE);
            if (!fo_fo) fclose(fo_fi); fo_fi = 0; fo_note_error("cannot write", fo_dst[i]); fo_done += fo_size[i] + 4096; fo_run_i++; continue; end
        end
        n = fread(fo_buf, FO_CHUNK, fo_fi);                  // lee un trozo y lo escribe
        if (n > 0)
            if (fwrite(fo_buf, n, fo_fo) != n)
                fo_note_error("write failed", fo_dst[i]);
                fclose(fo_fi); fclose(fo_fo); fo_fi = 0; fo_fo = 0; fremove(fo_dst[i]);
                fo_run_i = fo_n; return 0;                   // sin sitio u otro fallo de escritura: se para todo
            end
            fo_done += n;
        end
        if (n <= 0 || feof(fo_fi))
            fclose(fo_fi); fclose(fo_fo); fo_fi = 0; fo_fo = 0;
            fo_done += 4096; fo_run_i++;
        end
        turns--;
    end
    fo_progress();
    if (fo_run_i < fo_n) return 0; end
    // copia terminada
    if (fo_mode == FO_MOVE && fo_errs == 0)                    // mover entre discos: ahora se borran los originales (solo si todo se copio bien)
        fo_delafter = 1; fo_phase = 3; fo_run_i = fo_n - 1; fo_done = 0; fo_total = fo_n; if (fo_total <= 0) fo_total = 1; end
        return 0;
    end
    fo_finish(0);
end

// borrar: del final al principio, asi lo de dentro de una carpeta cae antes que la carpeta
function fo_delete_step()
private int turns, i;
begin
    turns = 80;
    while (turns > 0 && fo_run_i >= 0)
        i = fo_run_i;
        if (fo_isdir[i] != 2)
            fo_name = base_name(fo_src[i]);
            if (fo_isdir[i])
                if (rmdir(fo_src[i]) != 0 && rm(fo_src[i]) != 1) fo_note_error("cannot delete", fo_src[i]); end      // (rm quita un enlace a carpeta)
            else
                if (rm(fo_src[i]) != 1) fo_note_error("cannot delete", fo_src[i]); end
            end
        end
        fo_done++; fo_run_i--; turns--;
    end
    fo_progress();
    if (fo_run_i < 0) fo_finish(0); end
end

// un paso por fotograma (se cancela con atras / circulo)
function fo_step()
begin
    if (ov_cancel_asked())
        if (fo_fi) fclose(fo_fi); fo_fi = 0; end
        if (fo_fo) fclose(fo_fo); fo_fo = 0; if (fo_run_i < fo_n) fremove(fo_dst[fo_run_i]); end end
        fo_finish(-2);
        return 0;
    end
    switch (fo_phase)
        case 1: fo_plan_step(); end
        case 2: fo_copy_step(); end
        case 3: fo_delete_step(); end
    end
    if (fo_job && fo_name != "") ov_title = fo_cap + ": " + utf8_to_latin1(fo_name); end
end
