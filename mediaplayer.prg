// MediaPlayer - reproductor multimedia para BennuGD2 (libmod_video)
//   explorador de archivos + reproductor con iconos que se ocultan solos.
// Mando (PS5): cruceta = mover, X = aceptar, O = atras, triangulo = subtitulos, touchpad/A = idioma de audio,
//   cuadrado = silenciar, L1/R1 = -/+10 s, START = pausa.   Teclado: flechas, Enter, Esc, S, M, espacio.
// Variables de entorno: MEDIA_DIR (carpeta inicial), MP_OPEN (abrir un archivo directamente),
//   MP_SHOT (ruta .png: guarda una captura tras unos fotogramas y sale; solo para pruebas).
//   Solo para pruebas tambien: MP_SELECT, MP_ENTER, MP_SCRIPT, MP_KB_TEXT (texto del teclado),
//   MP_AUTH_USER, MP_AUTH_PASS, MP_STORE_URL, MP_TRACE, MP_XT_ENTER (abre un panel de Xtream).

import "libmod_gfx";
import "libmod_input";
import "libmod_misc";
import "libmod_sound";
import "libmod_net";
import "libmod_video";

const
    SW = 1280;            // el diseño se piensa en 1280x720 (coordenadas "logicas")...
    SH = 720;
    RW = 1920;            // ...y se dibuja a 1920x1080: todo sale x1.5 (nitido en una TV)
    RH = 1080;
    UIN = 3; UID = 2;     // factor logico -> real = 3/2

    // acciones de entrada
    A_UP = 0; A_DOWN = 1; A_LEFT = 2; A_RIGHT = 3;
    A_OK = 4; A_BACK = 5; A_SUBS = 6; A_PAUSE = 7; A_SEEKB = 8; A_SEEKF = 9; A_MUTE = 10;
    A_AUDIO = 11; A_COUNT = 12;

    // botones del reproductor (orden en pantalla)
    B_PREV = 0; B_RW = 1; B_PLAY = 2; B_STOP = 3; B_FF = 4; B_NEXT = 5; B_SUBS = 6; B_AUDIO = 7; B_VOL = 8;
    B_COUNT = 9;

    // casillas de sprites
    S_VIDEO = 0; S_SHADE_BOT = 1; S_SHADE_TOP = 2; S_BTN = 3;          // 3..11
    S_FOCUS = 12; S_BAR_BG = 13; S_BAR_FG = 14; S_KNOB = 15;
    S_BROWSE_BG = 16; S_SEL = 17; S_ROWICON = 18;                      // 18..29
    S_HEADER = 30; S_PREVIEW = 31; S_PANEL = 32; S_VIZ = 33; S_MSEL = 34; S_BG = 35; S_WAVE = 36; S_HICON = 39; S_OVDIM = 45; S_OVBOX = 46; S_OVBG = 47; S_OVFG = 48; S_OVBTN = 49; S_OVICO = 50; S_TABUL = 51; S_TABSEL = 52; S_COUNT = 53;
    HINT_Y = 684;
    OV_TY = 290; OV_BARY = 350; OV_PY = 392; OV_BY = 452;              // ventana de progreso: titulo, barra, porcentaje y boton (en la rejilla de 1280x720)
    GK_MAX = 8192;
    VIZ_W = 660; VIZ_H = 340; VIZ_BASE = 270; VIZ_MAXH = 260;

    ROWS = 12;
    ROW_H = 46;
    ROW_Y0 = 118;
    // cuadricula (pantallas de Xtream): 4 columnas x 3 filas = los mismos 12 elementos por pagina
    GRID_COLS = 4; GRID_ROWS = 3;
    GRID_X0 = 66; GRID_X1 = 742; GRID_Y0 = 158; GRID_Y1 = 636;
    HIDE_AFTER = 200;       // fotogramas sin tocar nada hasta ocultar los iconos
    MAX_ENTRIES = 2047;

    ST_BROWSE = 0; ST_PLAY = 1;
    K_FILE = 0; K_DIR = 1; K_LIST = 2; K_URL = 3; K_MYLISTS = 4; K_ADDONS = 5; K_ADDON = 6; K_AFOLDER = 7; K_STORE = 8; K_SITEM = 9; K_DOWNLOADS = 10;
    K_XCAT = 12; K_XSTR = 13; K_XSER = 14;   // entradas de una pantalla de Xtream (categoría, canal, serie)
    // tienda de addons: repositorio oficial del reproductor (se puede apuntar a otro con MP_STORE_URL)
    STORE_URL = "https://raw.githubusercontent.com/Rufidj/bennugd2-media-player/main/addons";
    M_NONE = 0; M_MENU = 1; M_KB = 2; M_CREDITS = 3; M_SYSKB = 4;                             // pantallas modales (menu / teclado)
    KB_NEWLIST = 1; KB_RENAME_LIST = 2; KB_URL = 3; KB_NEW_TITLE = 4; KB_ENTRY_TITLE = 5; KB_LOGO = 6; KB_ADDON = 7; KB_ASET = 8;
    KB_AUTH_USER = 9; KB_AUTH_PASS = 10; KB_OPEN_LIST = 11; KB_AUTH_SERVER = 12; KB_TMDB = 13;
    MA_CANCEL = 0; MA_NEW_LIST = 1; MA_GOTO_LISTS = 2; MA_ADD_TO = 3; MA_NEW_AND_ADD = 4; MA_RENAME_LIST = 5; MA_DELETE_LIST = 6;
    MA_DELETE_YES = 7; MA_ADD_URL = 8; MA_RENAME_ENTRY = 9; MA_LOGO = 10; MA_REMOVE = 11; MA_UP = 12; MA_DOWN = 13; MA_SETTINGS = 14; MA_LANG = 15; MA_SKIN = 16; MA_ASETTINGS = 18; MA_ABOUT = 19; MA_TMDB = 28; MA_ASET = 300; MA_PICK = 100;
    MA_STORE_REFRESH = 20; MA_LIST_ACCOUNT = 21; MA_ACCOUNTS = 22; MA_ACC_EDIT = 23; MA_ACC_DEL = 24; MA_ACC_PICK = 110;
    MA_OPEN_LIST = 25; MA_ACC_OPEN = 26; MA_ACC_NEW = 27; MA_DOWNLOAD = 29; MA_DELETE_DL = 30; MA_DELETE_DL_YES = 31; MA_DL_VIDEO = 32; MA_DL_AUDIO = 33; MA_DL_FMT = 400;
end

global
    int fnt_ui, fnt_sub;                          // fuentes de mapa de bits (solo la cuadricula del teclado)
    int sf_id[4], sf_cur = -1;                    // fuentes de subtitulos por escritura: 0 latino/cirilico, 1 japones, 2 chino, 3 coreano
    int fnt_t, texts_ready; string cur_font = "";    // fuentes TrueType de la interfaz y de los subtitulos
    int g_icon[20];                      // 0 play 1 pause 2 stop 3 next 4 prev 5 ff 6 rw 7 subs 8 vol 9 mute 10 folder 11 video 12 back
    int g_shade, g_shade_top, g_knob, g_white, g_barbg, g_sel, g_ring, g_ovdim, g_ovbox, g_ovfill;

    // sprites genericos controlados desde el bucle principal
    int   spr_graph[S_COUNT];
    int   spr_x[S_COUNT];
    int   spr_y[S_COUNT];
    int   spr_sizey[S_COUNT];
    int   spr_sizex[S_COUNT];
    int   spr_alpha[S_COUNT];
    int   spr_z[S_COUNT];

    // entrada
    int act_hold[A_COUNT];
    int act_press[A_COUNT];
    int act_rep[A_COUNT];
    int any_input;

    // en Android los toques los convierte la app en teclas (ver TouchOverlayView)
    int touch_mode;                 // 1 = se esta manejando con el dedo
    int touch_x, touch_y;           // ultima posicion del dedo
    int touch_age;                  // fotogramas desde el ultimo toque

    // explorador
    string cur_dir;
    int    grid_last = -1;            // el modo (lista o cuadricula) con el que se crearon los textos de fila
    // logos (imagenes) de las casillas de la cuadricula: se bajan en segundo plano y se cachean
    int    cell_map[ROWS];            // textura del logo de cada casilla (0 = todavia no)
    string cell_logo[ROWS];           // URL del logo de la casilla
    string cell_file[ROWS];           // fichero en la cache
    int    cell_state[ROWS];          // 0 = pendiente, 1 = bajando, 2 = en cache, 3 = error
    int    logo_busy = 0;             // hay una descarga de logo en marcha
    int    cell_tmdb[ROWS];           // 1 = ya se ha consultado TMDb por ese logo
    string tmdb_key = "";             // clave de la API de TMDb (opcional)
    string entries[MAX_ENTRIES];
    int    entry_dir[MAX_ENTRIES];
    int    entry_size[MAX_ENTRIES];
    string entry_url[MAX_ENTRIES];
    string entry_logo[MAX_ENTRIES];          // logo de la emisora (tvg-logo del .m3u), "" si no hay
    string pending_logo = "";
    int    logo_h;                           // video (imagen) abierto con el logo de la emision actual
    string cur_list = "";                // lista .m3u abierta ("" = explorando una carpeta)
    string load_path = "", load_title = "", pending_title = "";
    int    load_wait;
    // previsualizacion (un fotograma aleatorio + informacion)
    int    pv_h, pv_idx = -1, pv_rest, pv_wait, pv_phase;
    string s_info[7];
    int    txt_info[7];
    int    n_entries;
    int    sel, top_row;
    string row_label[ROWS];
    int    txt_row[ROWS];
    int    txt_path, txt_hint, txt_empty;
    string s_path, s_hint, s_empty;

    // reproductor
    int state = ST_BROWSE;
    int vh = 0;                          // manejador de video
    int cur_file_idx;                    // indice en entries del video actual
    string cur_file;
    int overlay_a, overlay_t, focus;
    int vol = 100, muted;
    int sub_sel = -1;                    // -1 desactivados
    int sub_tracks;
    int audio_tracks, audio_sel;
    int txt_time, txt_title, txt_toast, txt_sub[6];
    string s_time, s_title, s_toast, s_sub[3];
    int toast_t;
    int vid_w, vid_h;
    int frame_n;

    string shot_path;
    int dir_ver, lbl_ver = -1, lbl_top = -1;     // cache de textos del explorador
    int last_sec = -1, last_dur = -1;            // cache del contador de tiempo
    int sub_lines;
    // modo musica + visualizador (draw_rectangles_filled lee estos arrays cada fotograma)
    int music_mode, viz_mode;                    // viz_mode: 0 barras, 1 onda
    int g_viz;
    string hls_url = "", hls_hdr = "", hls_dir = "", hls_title = "";   // stream HLS con cabeceras abierto desde un addon: se salta regenerando la lista local
    string cr_s[48]; int cr_st[48], cr_id[48], cr_n, cr_pos, cr_fast, cr_from;          // creditos: lineas, estilo, texto, avance (x100)
    string info_fit[7];                                                   // ultima version ajustada al ancho de cada linea de informacion
    string hls_vurl = "", hls_aurl = "", hls_ct_url[2], hls_ct_txt[2];            // listas del maestro y copia de sus textos
    int hls_seek_to = -1, hls_seek_t = 0, hls_streak = 0;                  // saltos pendientes (se juntan las pulsaciones seguidas)
    int hls_base = 0, hls_total = 0;                                     // ms de inicio de la lista local dentro del total, y duracion total
    int g_k[GK_MAX];                             // por grafico: escala a aplicar (ver sprite_proc)
    int viz_cur[32]; int viz_peak[32]; int viz_phase;
    int pv_audio;
    int txt_cache[128];
    int txt_want[128];
    // almacen y editor de listas
    string store_dir = "", lists_dir = "", home_dir = "", downloads_dir = "";
    string wl_t[2048]; string wl_u[2048]; string wl_l[2048]; int wl_n;     // lista de trabajo
    int modal, modal_ver, mlbl_ver = -1;
    // menu horizontal del inicio (estilo Kodi): secciones 0 Archivos, 1 Addons, 2 Tienda, 3 Mis listas, 4 Descargas
    int tab_focus;                              // 1 = el foco esta en la barra de secciones
    string s_tab[5]; int txt_tab[5]; int tab_x[5], tab_w[5]; int tab_key = -1;
    int dlg_key = -1;                           // forma de la ventana del menu (para recolocar sus textos solo cuando cambia)
    string menu_title = "", menu_opt[10]; int menu_act[10], menu_n, menu_sel; string pick_name[10];
    int kb_secret, kb_secret_next;
    int syskb_off;                                // 1 = no hay teclado del sistema (PC) o fallo: se usa el propio
    string kb_title = "", kb_text = "", kb_rows[5], kb_sp[6]; int kb_spx[6], kb_spw[6];
    int kb_purpose, kb_r, kb_c, kb_shift, kb_dirty;
    string op_title = "", op_url = "", op_logo = "", op_path = ""; int op_after, op_idx;
    string s_mtitle, s_mopt[10], s_mhint, s_kbtitle, s_kbin, s_kbrow[5], s_kbs[6];
    int txt_mtitle, txt_mopt[10], txt_mhint, txt_kbin, txt_kbrow[5], txt_kbs[6];
    // idioma y aspecto
    string lang_cur = "es"; string lang_k[200]; string lang_v[200]; int lang_n, lang_ver;
    int skin = 1;                                 // 0 clasico, 1 PlayStation
    int g_bg_ps, g_wave[3], g_pill, g_sym[4];
    int hint_key = -1, hint_n, hint_ic[6], hint_icx[6]; string s_h[6]; int txt_h[6];
    int sc_f[200], sc_a[200], sc_n;               // entrada guiada para pruebas (MP_SCRIPT)
    string last_sub_raw = "";                    // cache del subtitulo
    int shot_frame = 150;
end

declare function string ext_of(string f) end
declare function string parent_of(string p) end
declare function string join_path(string d, string f) end
declare function string base_name(string p) end
declare function string fmt_time(int ms) end
declare function string addon_signed_playlist(string url, string hdr) end
declare function int hls_reseek(int ms) end
declare function string pad2(int n) end
declare function string utf8_to_latin1(string s) end
declare function string tr(string k) end
declare function string next_choice(string choices, string cur) end
declare function int sub_font_id(int k) end
declare function int lang_script() end
declare function string next_lang() end
declare function string extinf_title(string ln) end
declare function string disp_name(int i) end
declare function string sub_name() end
declare function string entry_path(int i) end
declare function string lang_or_dash(string l) end
declare function string fmt_size(int b) end
declare function string cut_text(string t, int n) end
declare function string fit_text(string t, int maxw) end
declare function string tail_fit(string t, int maxw) end
declare function string utf8_chop(string t) end
declare function string store_state(int i) end
// cuentas de las listas (ver auth.prg)
declare function string au_sidecar(string listfile) end
declare function string au_spec_get(string spec, string key) end
declare function string au_esc(string s) end
declare function string ad_buf_str(int start, int n) end
declare function string xt_item(string obj, string field) end
declare function string au_apply(string url) end
declare function string au_headers() end
declare function int au_load(string listfile) end
declare function int au_store(string listfile) end
declare function int au_clear(string listfile) end
declare function int au_login() end
declare function int au_finish() end
declare function int au_set_spec(string spec) end
declare function string au_json_str(string body, string field) end
declare function string au_ask_value(string spec, string key, string def) end
declare function int au_ask_account(string listfile) end
declare function int xt_enter(string name) end
declare function int xt_step() end
declare function int xt_open_level(int level) end
declare function string xt_stream_url(int i) end
declare function int au_reset() end
declare function string au_test_val(string env, string def) end
declare function int open_accounts_menu() end
declare function int open_account_menu(int i) end

// Entrada guiada para pruebas: MP_SCRIPT="fotograma:accion,fotograma:accion,..." (up down left right ok back subs pause seekb seekf mute audio)
function load_script()
private string sc, tok; int p, q, f, a;
begin
    sc = getenv("MP_SCRIPT"); sc_n = 0;
    while (sc != "" && sc_n < 200)
        p = find(sc, ",");
        if (p < 0) tok = sc; sc = ""; else tok = substr(sc, 0, p); sc = substr(sc, p + 1); end
        q = find(tok, ":");
        if (q > 0)
            f = atoi(substr(tok, 0, q)); tok = substr(tok, q + 1); a = -1;
            if (tok == "up") a = A_UP; end        if (tok == "down") a = A_DOWN; end
            if (tok == "left") a = A_LEFT; end    if (tok == "right") a = A_RIGHT; end
            if (tok == "ok") a = A_OK; end        if (tok == "back") a = A_BACK; end
            if (tok == "subs") a = A_SUBS; end    if (tok == "pause") a = A_PAUSE; end
            if (tok == "seekb") a = A_SEEKB; end  if (tok == "seekf") a = A_SEEKF; end
            if (tok == "mute") a = A_MUTE; end    if (tok == "audio") a = A_AUDIO; end
            if (a >= 0) sc_f[sc_n] = f; sc_a[sc_n] = a; sc_n++; end
        end
    end
end

function apply_script()
private int i;
begin
    for (i = 0; i < sc_n; i++)
        if (sc_f[i] == frame_n) act_press[sc_a[i]] = 1; any_input = 1; end
    end
end

include "addon.prg";
include "auth.prg";
include "xtream.prg";
include "addon_ui.prg";

process main()
private
    string open_file;
    int i;
begin
    soundsys_init();
    set_mode(RW, RH);
    set_fps(60, 0);

    load_assets();
    for (i = 0; i < S_COUNT; i++) sprite_proc(i); end
    create_viz();
    // en Android el mando en pantalla lo pone la app
    if (getenv("ANDROID_ROOT") != "") touch_mode = 1; end

    storage_init();
    cfg_load();
    lang_load(lang_cur);          // carga el idioma, abre sus fuentes TrueType y crea los textos
    load_script();
    cur_dir = getenv("MEDIA_DIR");
    if (cur_dir == "" && getenv("ANDROID_ROOT") != "")
        // en Android se abre la carpeta de los archivos del telefono (los videos,
        // la musica...), que es lo unico que hay ahi
        cur_dir = fexists("/sdcard") ? "/sdcard" : cd();
    end
    if (cur_dir == "")
        // por defecto la carpeta "videos" junto al programa (en la PS5: /app0/videos)
        cur_dir = join_path(cd(), "videos"); home_dir = cur_dir;
        read_dir();
        if (n_entries <= (store_dir != "" ? 2 : 1)) cur_dir = cd(); home_dir = cur_dir; read_dir(); end
    else
        home_dir = cur_dir;
        read_dir();
    end
    if (getenv("MP_SELECT") != "") sel = atoi(getenv("MP_SELECT")); if (sel >= n_entries) sel = n_entries - 1; end end   // solo pruebas
    if (getenv("MP_XT_ENTER") != "") xt_enter(getenv("MP_XT_ENTER")); end   // solo pruebas
    if (getenv("MP_VIZ") != "") viz_mode = atoi(getenv("MP_VIZ")); end   // solo pruebas
    say("MediaPlayer: carpeta " + cur_dir + ", " + n_entries + " entradas");

    if (getenv("MP_TRACE") != "") http_trace("PATH:" + getenv("MP_TRACE")); end   // traza del motor de video (libmod_video)
    store_base = getenv("MP_STORE_URL");                                          // otra copia de la tienda (pruebas y espejos)
    shot_path = getenv("MP_SHOT");
    if (getenv("MP_SHOTF") != "") shot_frame = atoi(getenv("MP_SHOTF")); end
    open_file = getenv("MP_OPEN");
    if (open_file != "") start_video(open_file); end

    while (!wm_info.exit_status)
        frame_n++;
        read_input();
        apply_script();
        // con la tecla ESC se sale; en Android el boton de atras del sistema
        // tambien es ESC, y ahi solo se sale cuando ya no hay donde volver
        if (act_press[A_BACK] && state == ST_BROWSE && key(_ESC) && !ov_on)
            if (!touch_mode) exit(); end
            if (cur_dir == home_dir && modal == M_NONE && addon_mode == 0 && store_mode == 0 && cur_list == "") exit(); end
        end

        if (getenv("MP_ENTER") != "" && frame_n == 10) activate_entry(sel); end                       // solo pruebas
        if (getenv("MP_SEL2") != "" && frame_n == 12) sel = atoi(getenv("MP_SEL2")); end
        if (getenv("MP_ENTER2") != "" && frame_n == 40) sel = atoi(getenv("MP_ENTER2")); activate_entry(sel); end
        if (getenv("MP_AUDIO_AT") != "" && frame_n == atoi(getenv("MP_AUDIO_AT")) && vh) cycle_audio(); end   // solo pruebas
        if (load_wait > 0)
            load_wait--;
            if (load_wait == 0) s_toast = ""; toast_t = 0; start_video(load_path); load_path = ""; end
        end
        if (modal != M_NONE) update_modal(); elseif (state == ST_BROWSE) update_browser(); else update_player(); end
        layout_all();
        apply_texts();

        if (shot_path != "" && frame_n == shot_frame)
            map_save(0, screen_get(), shot_path);
            if (music_mode) map_save(0, g_viz, shot_path + ".viz.png"); end
            say("captura guardada: " + shot_path);
            exit();
        end
        frame;
    end
end

// ------------------------------------------------------------------ recursos
// marca un grafico como "ya a resolucion real" (1920x1080): no hay que ampliarlo
function hires(int g)
begin
    if (g > 0 && g < GK_MAX) g_k[g] = 100; end
end

// logico -> real
function int ur(int v)
begin
    return v * UIN / UID;
end

// anchura de un texto en unidades logicas (la fuente se dibuja a x1.5)
function int tw(string t)
begin
    return text_width(fnt_t, t) * UID / UIN;
end

function load_assets()
private
    string names[17] = "play", "pause", "stop", "next", "prev", "ff", "rw", "subs", "vol", "mute", "folder", "video", "back", "lang", "cloud", "note", "addon";
    int i;
begin
    for (i = 0; i < GK_MAX; i++) g_k[i] = 150; end
    for (i = 0; i <= 16; i++)
        g_icon[i] = map_load("res/" + names[i] + ".png");
        center_set(0, g_icon[i], 72, 72); hires(g_icon[i]);
    end
    fnt_ui  = fnt_new(0, map_load("res/font_ui.png"), CHARSET_ISO8859, 24, 51, 0, 255, 0);
    fnt_sub = fnt_new(0, map_load("res/font_sub.png"), CHARSET_ISO8859, 38, 78, 0, 255, 0);

    g_shade     = map_load("res/shade_bot.png");
    g_shade_top = map_load("res/shade_top.png");
    g_ring      = map_load("res/ring.png"); center_set(0, g_ring, 72, 72); hires(g_ring);
    g_knob      = map_load("res/knob.png"); center_set(0, g_knob, 20, 20); hires(g_knob);
    g_white = map_new(8, 8);   map_clear(0, g_white, rgba(255, 255, 255, 255));
    g_barbg = map_new(8, 8);   map_clear(0, g_barbg, rgba(255, 255, 255, 70));
    g_sel   = map_new(8, 8);   map_clear(0, g_sel, rgba(70, 130, 255, 120));
    g_ovdim = map_new(8, 8);   map_clear(0, g_ovdim, rgba(0, 0, 0, 160));            // ventana de progreso: fondo atenuado, caja y relleno
    g_ovbox = map_new(8, 8);   map_clear(0, g_ovbox, rgba(16, 28, 60, 250));
    g_ovfill = map_new(8, 8);  map_clear(0, g_ovfill, rgba(90, 170, 255, 255));
    g_bg_ps = map_load("res/bg_ps.png"); hires(g_bg_ps);
    for (i = 0; i < 3; i++) g_wave[i] = map_load("res/wave" + i + ".png"); hires(g_wave[i]); end
    g_pill  = map_load("res/sel_pill.png"); hires(g_pill);
    g_sym[0] = map_load("res/sym_cross.png"); g_sym[1] = map_load("res/sym_circle.png");
    g_sym[2] = map_load("res/sym_triangle.png"); g_sym[3] = map_load("res/sym_square.png");
    for (i = 0; i < 4; i++) center_set(0, g_sym[i], 36, 36); hires(g_sym[i]); end
end

// Visualizador: se dibuja en un mapa propio (map_clear + drawing_map + draw_*) que se muestra como un sprite
function create_viz()
begin
    g_viz = map_new(ur(VIZ_W), ur(VIZ_H));
    center_set(0, g_viz, ur(VIZ_W) / 2, ur(VIZ_H) / 2); hires(g_viz);
end

// dibujo del visualizador en unidades logicas sobre un mapa a resolucion real
function vrect(int px, int py, int w, int h)
begin
    draw_rectangle_filled(ur(px), ur(py), ur(w) > 0 ? ur(w) : 1, ur(h) > 0 ? ur(h) : 1);
end
function vline(int x0, int y0, int x1, int y1)
begin
    draw_line(ur(x0), ur(y0), ur(x1), ur(y1));
end

// Actualiza el visualizador a partir de VIDEO_SPECTRUM / VIDEO_WAVE
function update_viz()
private int b, t, h, hg, hy, hr, xb, y0;
begin
    if (!vh || !music_mode) return 0; end
    map_clear(0, g_viz, rgba(0, 0, 0, 0));
    drawing_map(0, g_viz);
    y0 = VIZ_BASE;
    if (viz_mode == 0)
        for (b = 0; b < 32; b++)
            t = video_spectrum(vh, b) * VIZ_MAXH * 13 / 2550;
            if (t > VIZ_MAXH) t = VIZ_MAXH; end
            if (t > viz_cur[b]) viz_cur[b] = (viz_cur[b] * 2 + t * 3) / 5; else viz_cur[b] = viz_cur[b] * 82 / 100; end
            if (viz_cur[b] > viz_peak[b]) viz_peak[b] = viz_cur[b]; else viz_peak[b] -= 2; if (viz_peak[b] < 0) viz_peak[b] = 0; end end
            h = viz_cur[b];
            hg = h < VIZ_MAXH * 6 / 10 ? h : VIZ_MAXH * 6 / 10;
            hy = h > VIZ_MAXH * 6 / 10 ? (h < VIZ_MAXH * 85 / 100 ? h - VIZ_MAXH * 6 / 10 : VIZ_MAXH * 25 / 100) : 0;
            hr = h > VIZ_MAXH * 85 / 100 ? h - VIZ_MAXH * 85 / 100 : 0;
            xb = 10 + b * 20;
            if (hg > 0) drawing_rgba(60, 220, 90, 255);   vrect(xb, y0 - hg, 16, hg); end
            if (hy > 0) drawing_rgba(245, 210, 40, 255);  vrect(xb, y0 - hg - hy, 16, hy); end
            if (hr > 0) drawing_rgba(245, 70, 55, 255);   vrect(xb, y0 - hg - hy - hr, 16, hr); end
            drawing_rgba(255, 255, 255, 230);             vrect(xb, y0 - viz_peak[b] - 6, 16, 3);
            if (h > 3) drawing_rgba(90, 160, 255, 80);    vrect(xb, y0 + 6, 16, h / 4); end
        end
    else
        drawing_rgba(120, 255, 190, 255);
        for (b = 0; b < 255; b++)
            vline(10 + b * 640 / 255, VIZ_H / 2 + video_wave(vh, b) * 18 / 10, 10 + (b + 1) * 640 / 255, VIZ_H / 2 + video_wave(vh, b + 1) * 18 / 10);
        end
    end
    drawing_map(0, 0);
end

function create_texts()
private int i; string e = "";
begin
    // z negativo = por encima de los sprites
    for (i = 0; i < ROWS; i++)
        txt_row[i] = write_var(fnt_t, ur(110), ur(ROW_Y0 + i * ROW_H + ROW_H / 2), -20, 3, row_label[i]);
    end
    txt_path  = write_var(fnt_t, ur(76), ur(40), -20, 3, s_path);
    txt_hint  = write_var(fnt_t, ur(SW / 2), ur(SH - 24), -20, 4, s_hint);
    txt_empty = write_var(fnt_t, ur(SW / 2), ur(SH / 2), -20, 4, s_empty);
    txt_time  = write_var(fnt_t, ur(60), ur(SH - 72), -20, 3, s_time);
    txt_title = write_var(fnt_t, ur(60), ur(50), -20, 3, s_title);
    for (i = 0; i < 7; i++) txt_info[i] = write_var(fnt_t, ur(770), ur(420 + i * 34), -20, 3, s_info[i]); end
    txt_mtitle = write_var(fnt_t, ur(80), ur(70), -30, 3, s_mtitle);
    txt_mhint  = write_var(fnt_t, ur(SW / 2), ur(SH - 30), -30, 4, s_mhint);
    for (i = 0; i < 10; i++) txt_mopt[i] = write_var(fnt_t, ur(120), ur(170 + i * 52), -30, 3, s_mopt[i]); end
    txt_kbin   = write_var(fnt_t, ur(110), ur(170), -30, 3, s_kbin);
    for (i = 0; i < 5; i++) txt_kbrow[i] = write_var(fnt_ui, ur(SW / 2), ur(250 + i * 56), -30, 4, s_kbrow[i]); end
    for (i = 0; i < 6; i++) txt_kbs[i] = write_var(fnt_t, ur(0), ur(250 + 5 * 56), -30, 3, s_kbs[i]); end
    for (i = 0; i < 6; i++) txt_h[i] = write_var(fnt_t, ur(0), ur(HINT_Y), -30, 3, s_h[i]); end
    txt_toast = write_var(fnt_t, ur(SW / 2), ur(120), -20, 4, s_toast);
    txt_amsg = write_var(fnt_t, ur(SW / 2), ur(SH / 2), -25, 4, s_amsg);
    txt_ovt = write_var(fnt_t, ur(SW / 2), ur(OV_TY), -30, 4, s_ovt);
    txt_ovp = write_var(fnt_t, ur(SW / 2), ur(OV_PY), -30, 4, s_ovp);
    txt_ovh = write_var(fnt_t, ur(SW / 2), ur(OV_BY), -30, 4, s_ovh);
    for (i = 0; i < 5; i++) txt_tab[i] = write_var(fnt_t, ur(0), ur(44), -20, 3, s_tab[i]); end
    create_sub_texts(sub_font_id(lang_script()));
end

// cada casilla es un proceso que copia el estado de los arrays
process sprite_proc(int slot)
private int gk;
begin
    loop
        graph  = spr_graph[slot];
        gk = (graph > 0 && graph < GK_MAX) ? g_k[graph] : 150;      // 100 = imagen ya a resolucion real, 150 = hay que ampliarla x1.5
        x      = spr_x[slot] * UIN / UID;
        y      = spr_y[slot] * UIN / UID;
        size_y = spr_sizey[slot] * gk / 100;
        size_x = spr_sizex[slot] * gk / 100;
        alpha  = spr_alpha[slot];
        z      = spr_z[slot];
        frame;
    end
end

// ------------------------------------------------------------------ entrada
// En Android (y en cualquier sitio con pantalla tactil) se maneja con el dedo:
// la app convierte los toques en teclas, pero el punto exacto del toque lo
// consulta el motor: con touches[] se sabe que fila hay debajo del dedo, y al
// tocarla se abre directamente.
// El motor suelta el dedo un fotograma despues, asi que se guarda la ultima
// posicion en la que estuvo (puede que ya no haya ningun dedo cuando el juego
// mira la tecla "aceptar").
// Devuelve el numero de entrada que hay bajo el dedo, o -1 si no hay ninguna.
function int touch_row()
private int t_x, t_y, t_r, t_i;
begin
    if (!touch_mode) return -1; end
    if (touch_age > 8) return -1; end;
    t_x = touch_x;
    t_y = touch_y;
    if (grid_mode == 1)                   // la cuadricula (la tienda, los addons)
        for (t_i = 0; t_i < ROWS; t_i++)
            if (abs(t_x - grid_cx(t_i)) < (GRID_X1 - GRID_X0) / GRID_COLS / 2 && abs(t_y - grid_cy(t_i)) < (GRID_Y1 - GRID_Y0) / GRID_ROWS / 2) return top_row + t_i; end
        end
        return -1;
    end
    t_r = (t_y - ROW_Y0) / ROW_H;          // la lista de archivos
    if (t_r < 0 || t_r >= ROWS) return -1; end
    if (t_r >= n_entries - top_row) return -1; end
    if (t_x < 30 || t_x > 700) return -1; end
    return top_row + t_r;
end

function read_input()
private
    int i, n, ax, ay;
    int h[A_COUNT];
begin
    for (i = 0; i < A_COUNT; i++) h[i] = 0; end
    if (getenv("MP_NOPAD") != "") for (i = 0; i < A_COUNT; i++) act_press[i] = 0; end return 0; end
    // el mando hay que seleccionarlo explicitamente: usa el primero conectado
    for (i = 0; i < 4; i++)
        if (joy_is_attached(i)) joy_select(i); break; end
    end
    ax = joy_getaxis(JOY_AXIS_LEFTX); ay = joy_getaxis(JOY_AXIS_LEFTY);

    h[A_UP]    = key(_UP)    || joy_getbutton(JOY_BUTTON_DPAD_UP)    || ay < -16000;
    h[A_DOWN]  = key(_DOWN)  || joy_getbutton(JOY_BUTTON_DPAD_DOWN)  || ay >  16000;
    h[A_LEFT]  = key(_LEFT)  || joy_getbutton(JOY_BUTTON_DPAD_LEFT)  || ax < -16000;
    h[A_RIGHT] = key(_RIGHT) || joy_getbutton(JOY_BUTTON_DPAD_RIGHT) || ax >  16000;
    h[A_OK]    = key(_ENTER) || joy_getbutton(JOY_BUTTON_A);
    h[A_BACK]  = key(_ESC)   || key(_BACKSPACE) || joy_getbutton(JOY_BUTTON_B);
    h[A_SUBS]  = key(_S)     || joy_getbutton(JOY_BUTTON_Y);
    h[A_PAUSE] = key(_SPACE) || joy_getbutton(JOY_BUTTON_START);
    h[A_SEEKB] = key(_N) || joy_getbutton(JOY_BUTTON_LEFTSHOULDER);
    h[A_SEEKF] = key(_P)|| joy_getbutton(JOY_BUTTON_RIGHTSHOULDER);
    h[A_AUDIO] = key(_A) || joy_getbutton(JOY_BUTTON_TOUCHPAD);
    h[A_MUTE]  = key(_M)     || joy_getbutton(JOY_BUTTON_X);

    // ultima posicion del dedo (el motor suelta el dedo un fotograma despues,
    // asi que puede que ya no haya ningun dedo cuando se mira la tecla)
    if (touch_mode && touches[0].active)
        touch_x = touches[0].x * UID / UIN;
        touch_y = touches[0].y * UID / UIN;
        touch_age = 0;
    else
        touch_age++;
    end

    any_input = 0;
    for (i = 0; i < A_COUNT; i++)
        act_press[i] = 0;
        if (h[i])
            if (!act_hold[i])
                act_press[i] = 1; act_rep[i] = 0;
            else
                act_rep[i]++;
                // repeticion solo para direcciones: tras 22 fotogramas, cada 5
                if (i <= A_RIGHT && act_rep[i] > 22 && (act_rep[i] % 5) == 0) act_press[i] = 1; end
            end
            any_input = 1;
        end
        act_hold[i] = h[i];
    end
    // prueba de estres (MP_FUZZ=1): pulsaciones pseudoaleatorias
    if (getenv("MP_FUZZ") != "" && (frame_n % 6) == 0)
        i = rand(0, 5);
        if (getenv("MP_FUZZ") == "2") i = rand(0, 2); end
        for (n = 0; n < A_COUNT; n++) act_press[n] = 0; end
        switch (i)
            case 0: act_press[A_UP] = 1; end
            case 1, 2: act_press[A_DOWN] = 1; end
            case 3: act_press[A_OK] = 1; end
            case 4: act_press[A_OK] = 1; end
            case 5: act_press[A_BACK] = 1; end
        end
        any_input = 1;
    end
    // el stick/rueda tambien cuenta como "tocar el mando"
    if (abs(joy_getaxis(JOY_AXIS_RIGHTX)) > 12000 || abs(joy_getaxis(JOY_AXIS_RIGHTY)) > 12000) any_input = 1; end
end

// ------------------------------------------------------------------ explorador
function read_dir()
private
    int dh, i, j, d;
    string nm, t_s; int t_d, t_z;
begin
    n_entries = 0; addon_mode = 0; store_mode = 0;
    sel = 0; top_row = 0; dir_ver++;
    grid_mode = 0;
    au_reset();                                           // fuera de una lista no hay ninguna cuenta activa
    if (parent_of(cur_dir) != cur_dir)
        entries[0] = ".."; entry_dir[0] = 1; n_entries = 1;
    end
    // Addons, Tienda, Mis listas y Descargas ya no son filas del inicio: son las secciones de la barra de arriba (ver tab_goto)
    dh = diropen(join_path(cur_dir, "*"));
    if (dh)
        nm = dirread(dh);
        while (nm != "" && n_entries < MAX_ENTRIES)
            if (nm != "." && nm != ".." && substr(nm, 0, 1) != ".")
                d = fileinfo.directory;
                if (!d && (lcase(ext_of(nm)) == "m3u" || lcase(ext_of(nm)) == "m3u8")) d = K_LIST; end
                if (d || is_video(nm) || is_audio(nm))
                    entries[n_entries] = nm; entry_dir[n_entries] = d; entry_size[n_entries] = fileinfo.size; entry_logo[n_entries] = ""; n_entries++;
                end
            end
            nm = dirread(dh);
        end
        dirclose(dh);
    end
    // ordenar: ".." primero, carpetas, luego videos; alfabetico sin distinguir mayusculas
    for (i = 1; i < n_entries; i++)
        t_s = entries[i]; t_d = entry_dir[i]; t_z = entry_size[i]; j = i - 1;
        while (j >= (entries[0] == ".." ? 1 : 0) && entry_less(t_s, t_d, entries[j], entry_dir[j]))
            entries[j + 1] = entries[j]; entry_dir[j + 1] = entry_dir[j]; entry_size[j + 1] = entry_size[j]; j--;
        end
        entries[j + 1] = t_s; entry_dir[j + 1] = t_d; entry_size[j + 1] = t_z;
    end
end

// Lista de enlaces M3U: "#EXTINF:-1,Titulo" seguido de la URL (las lineas "#..." sin mas se ignoran)
function read_list()
private int i;
begin
    n_entries = 0; sel = 0; top_row = 0; dir_ver++;
    entries[0] = ".."; entry_dir[0] = K_DIR; entry_url[0] = ""; entry_size[0] = 0; entry_logo[0] = ""; n_entries = 1;
    wl_load(cur_list);
    au_load(cur_list);
    for (i = 0; i < wl_n && n_entries < MAX_ENTRIES; i++)
        entries[n_entries] = wl_t[i]; entry_dir[n_entries] = K_URL; entry_url[n_entries] = wl_u[i]; entry_size[n_entries] = 0; entry_logo[n_entries] = wl_l[i];
        n_entries++;
    end
end

function entry_less(string a, int ad, string b, int bd)
begin
    if (ad != bd) return ad > bd; end
    return lcase(a) < lcase(b);
end

function is_audio(string f)
private string e;
begin
    e = lcase(ext_of(f));
    return e == "mp3" || e == "flac" || e == "wav" || e == "m4a" || e == "aac" || e == "opus" || e == "wma" || e == "mka" || e == "oga" || e == "ape";
end

function is_video(string f)
private string e;
begin
    e = lcase(ext_of(f));
    return e == "mp4" || e == "mkv" || e == "avi" || e == "webm" || e == "mov" || e == "m4v"
        || e == "ogv" || e == "ogg" || e == "mpg" || e == "mpeg" || e == "ts" || e == "wmv" || e == "flv";
end

function string ext_of(string f)
private int i;
begin
    for (i = len(f) - 1; i > 0; i--)
        if (substr(f, i, 1) == ".") return substr(f, i + 1); end
    end
    return "";
end

function string parent_of(string p)
private int i;
begin
    for (i = len(p) - 1; i > 0; i--)
        if (substr(p, i, 1) == "/") return substr(p, 0, i); end
    end
    if (len(p) > 1 && substr(p, 0, 1) == "/") return "/"; end
    return p;
end

function string join_path(string d, string f)
begin
    if (d == "/") return "/" + f; end
    return d + "/" + f;
end

function string base_name(string p)
private int i;
begin
    for (i = len(p) - 1; i >= 0; i--)
        if (substr(p, i, 1) == "/") return substr(p, i + 1); end
    end
    return p;
end

// ---- secciones del inicio (menu horizontal, estilo Kodi)
function int tab_count()
begin
    return store_dir != "" ? 5 : 2;
end

// seccion en la que esta el explorador (-1 = dentro de algo: un addon, una lista, una carpeta...: sin barra de secciones)
function int cur_section()
begin
    if (xt_screen == 1 || cur_list != "" || addon_mode == 2) return -1; end
    if (store_mode == 1) return 2; end
    if (addon_mode == 1) return 1; end
    if (store_dir != "" && cur_dir == lists_dir) return 3; end
    if (store_dir != "" && cur_dir == downloads_dir) return 4; end
    if (cur_dir == home_dir) return 0; end
    return -1;
end

function string tab_name(int k)
begin
    switch (k)
        case 0: return tr("s_files"); end
        case 1: return tr("s_addons"); end
        case 2: return tr("s_store"); end
        case 3: return tr("m_mylists"); end
    end
    return tr("s_downloads");
end

function tab_goto(int k)
begin
    pv_idx = -1;
    switch (k)
        case 0: cur_list = ""; cur_dir = home_dir; read_dir(); end
        case 1: read_addons(); end
        case 2: store_open(); end
        case 3: cur_list = ""; mkdir(lists_dir); cur_dir = lists_dir; read_dir(); end
        case 4: cur_list = ""; mkdir(downloads_dir); cur_dir = downloads_dir; read_dir(); end
    end
end

// true si ya se ha atendido la pulsacion (la barra de secciones la ha usado)
function int update_tabs()
private int ts, n, i;
begin
    ts = cur_section();
    if (ts < 0) tab_focus = 0; return 0; end
    n = tab_count();
    if (act_press[A_SEEKB]) tab_goto((ts + n - 1) % n); return 1; end             // L1 / R1 cambian de seccion desde cualquier fila
    if (act_press[A_SEEKF]) tab_goto((ts + 1) % n); return 1; end
    // un toque sobre una seccion
    if (touch_mode && act_press[A_OK] && touch_age <= 8 && touch_y < 84)
        for (i = 0; i < n; i++)
            if (touch_x >= tab_x[i] - 24 && touch_x <= tab_x[i] + tab_w[i] + 24) tab_goto(i); return 1; end
        end
    end
    if (tab_focus)
        if (act_press[A_LEFT])  tab_goto((ts + n - 1) % n); return 1; end
        if (act_press[A_RIGHT]) tab_goto((ts + 1) % n); return 1; end
        if (act_press[A_DOWN] || act_press[A_OK] || act_press[A_BACK]) tab_focus = 0; return 1; end
        return 1;
    end
    // subir desde la primera fila lleva el foco a la barra
    if (act_press[A_UP] && sel == (grid_mode == 1 ? sel % GRID_COLS : 0) && n_entries > 0)
        if (grid_mode != 1 || sel < GRID_COLS) tab_focus = 1; return 1; end
    end
    return 0;
end

// la barra: los nombres de las secciones, la actual subrayada (y con la seleccion cuando tiene el foco)
function draw_tabs(int ts)
private int i, n, tx, k;
begin
    n = tab_count();
    k = n * 100 + lang_ver * 7;
    if (k != tab_key)
        tab_key = k; tx = 60;
        for (i = 0; i < n; i++)
            s_tab[i] = tab_name(i); tab_w[i] = tw(s_tab[i]); tab_x[i] = tx;
            write_move(txt_tab[i], ur(tx), ur(44));
            tx += tab_w[i] + 60;
        end
    end
    for (i = 0; i < n; i++) txt_want[txt_tab[i]] = 8589934336 + (i == ts ? 255 : (tab_focus ? 210 : 150)); end
    put(S_TABUL, g_white, tab_x[ts] + tab_w[ts] / 2, 76, 100, tab_focus ? 0 : 255, -10);
    spr_sizex[S_TABUL] = tab_w[ts] * 100 / 8; spr_sizey[S_TABUL] = 4 * 100 / 8;
    if (tab_focus) put_sel(S_TABSEL, tab_x[ts] + tab_w[ts] / 2, 44, tab_w[ts] + 48, 52, -9); end
end

function update_browser()
private int old, r;
begin
    if (xt_job) xt_step(); return 0; end                          // Xtream: cargando categorías o canales
    if (store_job == 1) store_step(); return 0; end                // instalando: no se atiende al mando
    if (dl_job == 1) dl_step(); return 0; end                      // descargando un video: solo se puede cancelar
    if (store_load) store_fetch(); return 0; end                   // la tienda se pide en el fotograma siguiente (primero addons y después listas)
    if (act_press[A_MUTE]) if (store_mode == 1) open_store_menu(); else open_context_menu(); end return 0; end
    if (update_tabs()) return 0; end
    if (n_entries > 0)
        old = sel;
        if (grid_mode == 1)
            // en cuadricula: izquierda/derecha una casilla, arriba/abajo una fila
            if (act_press[A_UP])    sel -= GRID_COLS; end
            if (act_press[A_DOWN])  sel += GRID_COLS; end
            if (act_press[A_LEFT])  sel--; end
            if (act_press[A_RIGHT]) sel++; end
            if (sel < 0) sel = 0; end
            if (sel >= n_entries) sel = n_entries - 1; end
            if (sel < top_row) top_row = (sel / GRID_COLS) * GRID_COLS; end
            if (sel >= top_row + ROWS) top_row = ((sel - ROWS) / GRID_COLS + 1) * GRID_COLS; end
        else
            if (act_press[A_UP])    sel--; end
            if (act_press[A_DOWN])  sel++; end
            if (act_press[A_LEFT])  sel -= ROWS - 1; end
            if (act_press[A_RIGHT]) sel += ROWS - 1; end
            if (sel < 0) sel = (old == 0 && act_press[A_UP]) ? n_entries - 1 : 0; end
            if (sel >= n_entries) sel = (old == n_entries - 1 && act_press[A_DOWN]) ? 0 : n_entries - 1; end
            if (sel < top_row) top_row = sel; end
            if (sel >= top_row + ROWS) top_row = sel - ROWS + 1; end
        end

        if (act_press[A_OK])
            // si hay un dedo sobre una fila, se abre esa (el boton "aceptar" de
            // un mando no tiene donde estar, asi que manda el dedo)
            r = touch_row();
            if (r >= 0) sel = r; end
            activate_entry(sel);
        end
        update_preview();
    end
    if (act_press[A_BACK] || act_press[A_SUBS])
        go_up();
    end
end

function string fmt_size(int b)
begin
    if (b <= 0) return "-"; end
    if (b >= 1073741824) return (b / 1073741824) + "." + ((b / 107374182) % 10) + " GB"; end
    if (b >= 1048576) return (b / 1048576) + "." + ((b / 104857) % 10) + " MB"; end
    return (b / 1024) + " KB";
end

function string lang_or_dash(string l)
begin
    if (l == "") return "?"; end
    return l;
end

function string cut_text(string t, int n)
begin
    return fit_text(t, n * 14);
end

// cierra la previsualizacion actual (si la hay)
function close_preview()
begin
    if (pv_h) video_close(pv_h); end
    pv_h = 0; pv_phase = 0;
    spr_graph[S_PREVIEW] = 0;
end

// Si te quedas un momento sobre un video: se abre en silencio (decodificador por software, para no tocar el del hardware),
// salta a un punto aleatorio y se queda en pausa con ese fotograma, junto a su informacion.
function update_preview()
private int d, n, k, goto_skip_info; string t;
begin
    for (k = 0; k < 7; k++)                              // salvaguarda: ninguna linea de informacion se sale del panel
        if (s_info[k] != info_fit[k]) s_info[k] = fit_text(s_info[k], 420); info_fit[k] = s_info[k]; end
    end
    if (sel != pv_idx)
        close_preview();
        pv_idx = sel; pv_rest = 0;
        for (k = 0; k < 7; k++) s_info[k] = ""; end
        if (sel >= 0 && sel < n_entries && entries[sel] != "..")
            s_info[0] = cut_text(disp_name(sel), 28);
            switch (entry_dir[sel])
                case K_DIR:  s_info[1] = tr("s_folder"); end
                case K_LIST: s_info[1] = tr("s_linklist"); end
                case K_DOWNLOADS:
                    wrap_text(tr("s_downloads_info"), 420, 4);
                    for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                end
                case K_MYLISTS:
                    wrap_text(tr("s_mylists_info"), 420, 2);
                    for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                    s_info[1 + wrap_n] = tr("s_mylists_hint");
                end
                case K_ADDONS:
                    wrap_text(tr("s_addons_info"), 420, 5);
                    for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                end
                case K_ADDON:
                    wrap_text(entry_info[sel], 420, 5);
                    for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                    s_info[6] = tr("s_addon_hint");
                end
                case K_STORE:
                    wrap_text(tr("s_store_info"), 420, 5);
                    for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                end
                case K_SITEM:
                    s_info[1] = store_state(sel);
                    if (entry_skind[sel] == 1)
                        wrap_text(tr("s_store_list") + ": " + entry_info[sel], 420, 3);   // lista de TV/radio
                    else
                        wrap_text(entry_info[sel], 420, 4);                               // addon
                    end
                    for (k = 0; k < wrap_n; k++) s_info[2 + k] = wrap_l[k]; end
                end
                case K_AFOLDER:
                    s_info[1] = tr("s_folder");
                    wrap_text(entry_info[sel], 420, 4);
                    for (k = 0; k < wrap_n; k++) s_info[2 + k] = wrap_l[k]; end
                end
                case K_URL:
                    if (addon_mode == 2)
                        wrap_text(entry_info[sel], 420, 6);
                        for (k = 0; k < wrap_n; k++) s_info[1 + k] = wrap_l[k]; end
                    else
                        if (find(entry_url[sel], "://") < 0) s_info[1] = tr("s_localfile"); else s_info[1] = tr("s_netvideo"); end
                        s_info[2] = cut_text(substr(entry_url[sel], find(entry_url[sel], "://") + 3), 28);
                        if (find(entry_url[sel], "://") >= 0) s_info[3] = tr("s_streaming"); end
                    end
                end
                default: s_info[1] = tr("s_size") + fmt_size(entry_size[sel]); end
            end
        end
    end
    pv_rest++;
    if (pv_phase == 0 && pv_rest == (entry_dir[sel] == K_URL || entry_dir[sel] == K_AFOLDER ? 45 : 25) && sel >= 0 && sel < n_entries && (entry_dir[sel] == K_FILE || entry_dir[sel] == K_URL || entry_dir[sel] == K_XSTR || ((entry_dir[sel] == K_AFOLDER || entry_dir[sel] == K_ADDON) && entry_logo[sel] != "")) && entries[sel] != "..")
        video_use_hw(0);
        // emisoras con logo: se abre la imagen del logo; el resto de enlaces: el propio video por red (puede tardar un poco)
        if (entry_dir[sel] == K_XSTR)
            pv_h = video_open(xt_stream_url(sel));              // canal del panel: miniatura en movimiento, sin sonido
        elseif ((entry_dir[sel] == K_URL || entry_dir[sel] == K_AFOLDER || entry_dir[sel] == K_ADDON) && entry_logo[sel] != "") pv_h = video_open(entry_logo[sel]);
        elseif (au_headers() != "") pv_h = video_open_h(entry_path(sel), au_headers());
        else pv_h = video_open(entry_path(sel)); end
        video_use_hw(1);
        pv_phase = 3;                                   // 3 = no se pudo abrir
        if (pv_h)
            video_volume(pv_h, 0);
            d = video_duration(pv_h);
            if (video_is_audio_only(pv_h))
                pv_phase = 2;                           // musica sin portada: se muestra una nota, no hace falta decodificar
            else
                video_play(pv_h, 0);
                if (d > 2000) video_seek(pv_h, rand(d * 15 / 100, d * 75 / 100)); end
                pv_phase = 1; pv_wait = 0;
            end
            if (entry_dir[sel] == K_AFOLDER || entry_dir[sel] == K_ADDON || (entry_dir[sel] == K_URL && (entry_logo[sel] != "" || addon_mode == 2))) goto_skip_info = 1; else goto_skip_info = 0; end
            if (!goto_skip_info)
            if (video_is_audio_only(pv_h)) s_info[1] = tr("s_music"); else s_info[1] = tr("s_res") + video_width(pv_h) + "x" + video_height(pv_h); end
            if (d > 0) s_info[2] = tr("s_dur") + fmt_time(d); else s_info[2] = tr("s_dur_live"); end
            if (entry_dir[sel] == K_URL) s_info[3] = tr("s_net_streaming"); else s_info[3] = tr("s_size") + fmt_size(entry_size[sel]); end
            n = video_audio_tracks(pv_h);
            t = "";
            for (k = 0; k < n && k < 4; k++) t += (k > 0 ? ", " : "") + lang_or_dash(video_audio_lang(pv_h, k)); end
            s_info[4] = tr("s_audio_n") + n + "): " + cut_text(utf8_to_latin1(t), 16);
            n = video_subtitle_tracks(pv_h);
            t = "";
            for (k = 0; k < n && k < 4; k++) t += (k > 0 ? ", " : "") + lang_or_dash(video_subtitle_lang(pv_h, k)); end
            s_info[5] = tr("s_subs_n") + n + "): " + cut_text(utf8_to_latin1(t), 12);
            end
        end
    end
    if (pv_phase == 1)
        pv_wait++;
        // espera a que haya fotogramas de verdad (el decodificador puede tardar mas en la consola); como maximo 3 s
        if ((video_frames(pv_h) > 0 && pv_wait >= 30) || pv_wait >= (entry_dir[sel] == K_URL ? 420 : 180))
            video_pause(pv_h, 1);
            pv_phase = video_frames(pv_h) > 0 ? 2 : 3;
        end
    end
end

function go_up()
begin
    if (xt_screen == 1)
        if (xt_level > 0) xt_level--; xt_job = 0; xt_open_level(xt_level); return 0; end
        xt_screen = 0; grid_mode = 0; cur_dir = home_dir; read_dir(); return 0;
    end
    if (store_mode == 1)
        store_mode = 0; cur_dir = home_dir; read_dir();
    elseif (addon_mode == 2)
        addon_back();
    elseif (addon_mode == 1)
        addon_mode = 0; cur_dir = home_dir; read_dir();
    elseif (cur_list != "")
        cur_list = ""; read_dir();
    elseif (store_dir != "" && (cur_dir == lists_dir || cur_dir == downloads_dir))
        cur_dir = home_dir; read_dir();
    elseif (parent_of(cur_dir) != cur_dir)
        cur_dir = parent_of(cur_dir); read_dir();
    end
end

// ruta/URL real de una entrada
function string entry_path(int i)
begin
    if (entry_dir[i] == K_URL) return entry_url[i]; end
    return join_path(cur_dir, entries[i]);
end

// Las URL se abren en el fotograma siguiente: asi se ve tr("s_connecting") mientras el programa espera a la red
function request_open(int i)
begin
    cur_file_idx = i;
    hls_url = ""; hls_base = 0; hls_total = 0; hls_vurl = ""; hls_aurl = ""; hls_ct_url[0] = ""; hls_ct_url[1] = ""; hls_seek_to = -1;
    pending_title = entries[i]; pending_logo = entry_logo[i]; hls_title = entries[i];
    if (entry_dir[i] == K_URL)
        s_toast = tr("s_connecting"); toast_t = 600;
        load_path = au_apply(entry_url[i]); load_wait = 3;
        if (addon_mode > 0 && entry_aargs[i] != "") load_path = addon_signed_playlist(entry_url[i], entry_aargs[i]); if (load_path == "") load_wait = 0; s_toast = ""; toast_t = 0; end end
    else
        start_video(entry_path(i));
    end
end

function activate_entry(int i)
begin
    if (entries[i] == "..")
        go_up();
    elseif (entry_dir[i] == K_DIR)
        cur_dir = join_path(cur_dir, entries[i]); read_dir();
    elseif (entry_dir[i] == K_MYLISTS)
        cur_dir = lists_dir; read_dir();
    elseif (entry_dir[i] == K_DOWNLOADS)
        mkdir(downloads_dir); cur_dir = downloads_dir; read_dir();
    elseif (entry_dir[i] == K_ADDONS)
        read_addons();
    elseif (entry_dir[i] == K_STORE)
        store_open();
    elseif (entry_dir[i] == K_SITEM)
        store_install(i);
    elseif (entry_dir[i] == K_ADDON)
        addon_open(entry_url[i]);
    elseif (entry_dir[i] == K_AFOLDER)
        addon_goto(entry_url[i], entry_aargs[i]);
    elseif (entry_dir[i] == K_LIST)
        cur_list = join_path(cur_dir, entries[i]); read_list();
    elseif (entry_dir[i] == K_XCAT)
        if (xt_level == 0)
            xt_type = (entry_url[i] == "vod") ? 1 : ((entry_url[i] == "series") ? 2 : 0);
            xt_cat_sel = ""; xt_job = 1;
        else
            xt_cat_sel = entry_url[i]; xt_job = 2;
        end
    elseif (entry_dir[i] == K_XSER)
        xt_ser_sel = entry_url[i]; xt_job = 3;
    elseif (entry_dir[i] == K_XSTR)
        pending_title = disp_name(i); pending_logo = entry_logo[i];      // el titulo es el nombre del canal, no el .ts
        start_video(xt_stream_url(i));
    else
        request_open(i);
    end
end


// ====================================================================== aspecto (skin)
// Fondo degradado con tres olas que se desplazan despacio (solo con el aspecto PlayStation)
function draw_bg()
private int k, ox;
begin
    if (!skin) return 0; end
    put(S_BG, g_bg_ps, SW / 2, SH / 2, 100, 255, 30);
    for (k = 0; k < 3; k++)
        ox = (frame_n * (k + 1) / 4) % 1280;
        put(S_WAVE + k, g_wave[k], 1280 - ox, SH / 2, 100, 255, 28 - k);
    end
end

// Un numero corto a partir de la URL: sirve de nombre para el fichero de la cache
function string url_hash(string s)
private int h, i;
begin
    h = 5381;
    for (i = 0; i < len(s); i++) h = ((h % 1000003) * 33 + asc(substr(s, i, 1))) % 1000003; end
    return "" + h + "_" + len(s);
end

// Carpeta donde se guardan las imagenes de los logos
function string logo_dir()
begin
    if (store_dir == "") return ""; end
    return join_path(store_dir, "cache");
end

// La imagen se baja en un proceso aparte: la interfaz no se congela mientras espera
process logo_fetch(int slot, string url, string fn)
private int st;
begin
    st = http_fetch(url, "", "GET", "");
    if (st == 200 && http_length() > 0 && http_length() < 4000000) http_save(fn); end
    cell_state[slot] = fexists(fn) ? 2 : 3;
    logo_busy = 0;
    frame;
end

// El idioma de TMDb segun el del reproductor
function string tmdb_lang()
begin
    if (lang_cur == "en") return "en-US"; end
    if (lang_cur == "ru") return "ru-RU"; end
    if (lang_cur == "ja") return "ja-JP"; end
    if (lang_cur == "zh") return "zh-CN"; end
    if (lang_cur == "ko") return "ko-KR"; end
    return "es-ES";
end

// Busca el cartel de una pelicula o serie en TMDb (proceso aparte: no bloquea la interfaz)
process tmdb_fetch(int slot, string title)
private
    string q, body, poster, kind, cachef;
    int st, fh;
begin
    cachef = join_path(logo_dir(), "t" + url_hash(title) + ".txt");
    poster = "";
    fh = fopen(cachef, O_READ);
    if (fh)                                          // ya se habia buscado este titulo
        poster = fgets(fh);
        fclose(fh);
        if (poster != "") poster = "https://image.tmdb.org/t/p/w300" + poster; end
    else
        kind = (xt_type == 1) ? "movie" : "tv";
        q = "https://api.themoviedb.org/3/search/" + kind + "?api_key=" + tmdb_key + "&query=" + au_esc(title) + "&language=" + tmdb_lang();
        st = http_fetch(q, "", "GET", "");
        if (st == 200 && http_length() > 0 && http_length() < 2000000)
            body = ad_buf_str(0, http_length());
            poster = xt_item(body, "poster_path");
        end
        fh = fopen(cachef, O_WRITE);
        if (fh) fputs(fh, poster); fclose(fh); end
        if (poster != "") poster = "https://image.tmdb.org/t/p/w300" + poster; end
    end
    if (poster != "")
        cell_logo[slot] = poster;
        cell_file[slot] = join_path(logo_dir(), "l" + url_hash(poster) + ".img");
    end
    cell_state[slot] = 0;                           // ahora se baja el cartel (o el logo del panel)
    logo_busy = 0;
    frame;
end

// Pide los logos de las casillas visibles y los va abriendo (uno por fotograma)
function update_cell_logos()
private int i, rowi;
begin
    if (grid_mode != 1) return 0; end
    for (i = 0; i < ROWS; i++)
        rowi = top_row + i;
        if (rowi < n_entries && entry_logo[rowi] != "")
            if (cell_logo[i] != entry_logo[rowi])
                cell_logo[i] = entry_logo[rowi];
                cell_file[i] = join_path(logo_dir(), "l" + url_hash(entry_logo[rowi]) + ".img");
                cell_state[i] = fexists(cell_file[i]) ? 2 : 0;
                cell_tmdb[i] = 0;
                if (cell_map[i] > 0) map_del(0, cell_map[i]); end
                cell_map[i] = 0;
            end
            if (cell_state[i] == 0 && logo_busy == 0)
                mkdir(logo_dir());
                logo_busy = 1; cell_state[i] = 1;
                if (tmdb_key != "" && !cell_tmdb[i] && (xt_type == 1 || xt_type == 2))
                    cell_tmdb[i] = 1;                 // primero se pregunta a TMDb
                    tmdb_fetch(i, disp_name(rowi));
                else
                    logo_fetch(i, cell_logo[i], cell_file[i]);
                end
            end
            if (cell_state[i] == 2 && cell_map[i] == 0)
                cell_map[i] = map_load(cell_file[i]);
                if (cell_map[i] == 0) cell_state[i] = 3; end
            end
        else
            if (cell_map[i] > 0) map_del(0, cell_map[i]); end
            cell_map[i] = 0; cell_logo[i] = ""; cell_state[i] = 0;
        end
    end
end

// centro de la casilla i de la cuadricula
function int grid_cx(int i)
begin
    return GRID_X0 + (i % GRID_COLS) * (GRID_X1 - GRID_X0) / GRID_COLS + (GRID_X1 - GRID_X0) / GRID_COLS / 2;
end

function int grid_cy(int i)
begin
    return GRID_Y0 + (i / GRID_COLS) * (GRID_Y1 - GRID_Y0) / GRID_ROWS + (GRID_Y1 - GRID_Y0) / GRID_ROWS / 2;
end

// Selector: pastilla redondeada (PlayStation) o barra azul (clasico); w x h en pixeles
function put_sel(int slot, int px, int py, int w, int h, int zz)
begin
    if (skin)
        put(slot, g_pill, px, py, 100, 255, zz);
        spr_sizex[slot] = w * 100 / 704; spr_sizey[slot] = h * 100 / 48;
    else
        put(slot, g_sel, px, py, 100, 255, zz);
        spr_sizex[slot] = w * 100 / 8; spr_sizey[slot] = h * 100 / 8;
    end
end

// Barra de ayuda con los simbolos de botones de colores. ctx: 1 explorador, 2 menu, 3 teclado
function hint_set(int ctx)
private int k, hk, wtot, x0, w;
begin
    hk = ctx + lang_ver * 10 + skin * 1000;
    if (hk != hint_key)
        hint_key = hk;
        for (k = 0; k < 6; k++) s_h[k] = ""; hint_ic[k] = -1; end
        switch (ctx)
            case 1: hint_n = 3; hint_ic[0] = 0; s_h[0] = tr("h_open"); hint_ic[1] = 1; s_h[1] = tr("h_back"); hint_ic[2] = 3; s_h[2] = tr("h_options"); end
            case 5: hint_n = 3; hint_ic[0] = 0; s_h[0] = tr("h_install"); hint_ic[1] = 1; s_h[1] = tr("h_back"); hint_ic[2] = 3; s_h[2] = tr("h_options"); end
            case 4: hint_n = 1; hint_ic[0] = 1; s_h[0] = tr("h_back"); end
            case 2: hint_n = 2; hint_ic[0] = 0; s_h[0] = tr("h_choose"); hint_ic[1] = 1; s_h[1] = tr("h_cancel"); end
            default:
                hint_n = 6;
                hint_ic[0] = 0; s_h[0] = tr("h_type"); hint_ic[1] = 3; s_h[1] = tr("h_delete"); hint_ic[2] = 2; s_h[2] = tr("h_space");
                s_h[3] = "L1 " + tr("h_shift"); s_h[4] = "START " + tr("h_accept"); hint_ic[5] = 1; s_h[5] = tr("h_cancel");
            end
        end
        // en el movil no hay botones de consola: los simbolos sobran
        if (touch_mode) for (k = 0; k < 6; k++) hint_ic[k] = -1; end end
        wtot = 0;
        for (k = 0; k < hint_n; k++) wtot += (hint_ic[k] >= 0 ? 44 : 0) + tw(s_h[k]) + (k < hint_n - 1 ? 44 : 0); end
        x0 = (SW - wtot) / 2;
        for (k = 0; k < hint_n; k++)
            w = hint_ic[k] >= 0 ? 44 : 0;
            hint_icx[k] = x0 + 22;
            write_move(txt_h[k], ur(x0 + w), ur(HINT_Y));
            x0 += w + tw(s_h[k]) + 44;
        end
    end
    for (k = 0; k < hint_n; k++)
        txt_want[txt_h[k]] = 8589934336 + (210);
        if (hint_ic[k] >= 0) put(S_HICON + k, g_sym[hint_ic[k]], hint_icx[k], HINT_Y + 2, 80, 255, -12); end
    end
end

// ====================================================================== fuentes TrueType y medida de textos
// quita el ultimo caracter UTF-8
function string utf8_chop(string t)
private int i;
begin
    i = len(t) - 1;
    while (i > 0 && (asc(substr(t, i, 1)) & 192) == 128) i--; end
    if (i < 0) i = 0; end
    return substr(t, 0, i);
end

// recorta con "..." para que el texto quepa en maxw pixeles (con la fuente de la interfaz)
function string fit_text(string t, int maxw)
begin
    if (fnt_t <= 0 || tw(t) <= maxw) return t; end
    while (len(t) > 1 && tw(t + "...") > maxw) t = utf8_chop(t); end
    return t + "...";
end

// la cola de un texto largo (para la linea del teclado)
function string tail_fit(string t, int maxw)
private int i, n;
begin
    if (fnt_t <= 0 || tw(t) <= maxw) return t; end
    n = len(t);
    for (i = 1; i < n; i++)
        if ((asc(substr(t, i, 1)) & 192) != 128 && tw("..." + substr(t, i)) <= maxw) return "..." + substr(t, i); end
    end
    return t;
end

// Abre la fuente del idioma actual (clave lang_font) y vuelve a crear todos los textos con ella
function apply_lang_font()
private string f; int i;
begin
    f = tr("lang_font");
    if (f == "lang_font") f = "res/fonts/ui_latin.ttf"; end
    if (f == cur_font && texts_ready) return 0; end
    if (texts_ready) write_delete(ALL_TEXT); for (i = 0; i < 6; i++) txt_sub[i] = 0; end sf_cur = -1; end
    if (f != cur_font)
        if (fnt_t > 0) fnt_unload(fnt_t); end
        fnt_t = ttf_load(f);
        if (fnt_t > 0) ttf_set_size(fnt_t, 42); end
        cur_font = f;
    end
    for (i = 0; i < 128; i++) txt_cache[i] = 0; txt_want[i] = 0; end
    create_texts();
    texts_ready = 1;
    hint_key = -1; mlbl_ver = -1; lbl_ver = -1;
end

// ---- fuentes de subtitulos: se elige la que cubre la escritura del texto (se cargan al primer uso)
function sub_font_id(int k)
begin
    if (k < 0 || k > 3) k = 0; end
    if (sf_id[k] <= 0)
        sf_id[k] = ttf_load(k == 1 ? "res/fonts/ui_ja.otf" : (k == 2 ? "res/fonts/ui_zh.otf" : (k == 3 ? "res/fonts/ui_ko.otf" : "res/fonts/ui_latin.ttf")));
        if (sf_id[k] > 0) ttf_set_size(sf_id[k], 60); end
    end
    sf_cur = k;
    return sf_id[k];
end

// escritura de la interfaz segun el idioma
function lang_script()
begin
    if (lang_cur == "ja") return 1; end
    if (lang_cur == "zh") return 2; end
    if (lang_cur == "ko") return 3; end
    return 0;
end

// escritura de un texto UTF-8: 3 coreano, 1 japones (si hay kana), 2 chino (hanzi sin kana), 0 resto
function script_of(string t)
private int i, n, b0, b1, b2, cp, han;
begin
    n = len(t); han = 0;
    for (i = 0; i < n; i++)
        b0 = asc(substr(t, i, 1));
        if (b0 >= 224 && b0 < 240 && i + 2 < n)
            b1 = asc(substr(t, i + 1, 1)); b2 = asc(substr(t, i + 2, 1));
            cp = ((b0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63);
            if ((cp >= 44032 && cp <= 55203) || (cp >= 4352 && cp <= 4607) || (cp >= 12592 && cp <= 12687)) return 3; end
            if (cp >= 12352 && cp <= 12543) return 1; end
            if (cp >= 19968 && cp <= 40959) han = 1; end
            i += 2;
        elseif (b0 >= 192 && b0 < 224) i++;
        elseif (b0 >= 240) i += 3;
        end
    end
    if (han) return (lang_cur == "ja" ? 1 : 2); end        // solo caracteres chinos: japones si la interfaz esta en japones, si no chino
    return 0;
end

// (re)crea las 6 etiquetas de subtitulos (3 lineas x sombra) con la fuente indicada
function create_sub_texts(int fid)
private int i;
begin
    for (i = 0; i < 6; i++)
        if (txt_sub[i] > 0) write_delete(txt_sub[i]); txt_cache[txt_sub[i]] = 0; end
    end
    for (i = 0; i < 3; i++)
        txt_sub[i * 2]     = write_var(fid, ur(SW / 2 + 2), 0, -21, 7, s_sub[i]);
        txt_sub[i * 2 + 1] = write_var(fid, ur(SW / 2), 0, -22, 7, s_sub[i]);
        write_set_rgba(txt_sub[i * 2], 0, 0, 0, 255);
    end
end

// ====================================================================== idioma y ajustes
// Devuelve el texto de la clave en el idioma actual (ya en ISO-8859-1 para la fuente); si falta, la propia clave
function string tr(string k)
private int i;
begin
    for (i = 0; i < lang_n; i++)
        if (lang_k[i] == k) return lang_v[i]; end
    end
    return k;
end

function string disp_name(int i)
begin
    return entries[i];
end

// carga lang/<codigo>.txt (lineas clave=valor, UTF-8)
function lang_load(string code)
private int fh, p; string ln;
begin
    fh = fopen("lang/" + code + ".txt", O_READ);
    if (!fh) return 0; end
    lang_n = 0;
    while (!feof(fh) && lang_n < 200)
        ln = fgets(fh);
        p = find(ln, "=");
        if (p > 0 && substr(ln, 0, 1) != "#")
            lang_k[lang_n] = substr(ln, 0, p); lang_v[lang_n] = substr(ln, p + 1); lang_n++;
        end
    end
    fclose(fh);
    lang_cur = code; lang_ver++;
    // fuerza que los textos ya construidos se rehagan
    lbl_ver = -1; pv_idx = -1; mlbl_ver = -1; kb_dirty = 1; last_sec = -1;
    apply_lang_font();
    return 1;
end

// idiomas disponibles (un archivo lang/<codigo>.txt cada uno)
function is_lang(string c)
begin
    return c == "es" || c == "en" || c == "ru" || c == "ja" || c == "zh" || c == "ko";
end

function string next_lang()
begin
    if (lang_cur == "es") return "en"; end
    if (lang_cur == "en") return "ru"; end
    if (lang_cur == "ru") return "ja"; end
    if (lang_cur == "ja") return "zh"; end
    if (lang_cur == "zh") return "ko"; end
    return "es";
end

function cfg_load()
private int fh, p; string ln, k, v;
begin
    if (store_dir == "") return 0; end
    fh = fopen(join_path(store_dir, "config.cfg"), O_READ);
    if (!fh) return 0; end
    while (!feof(fh))
        ln = fgets(fh);
        p = find(ln, "=");
        if (p > 0)
            k = substr(ln, 0, p); v = substr(ln, p + 1);
            if (k == "lang" && is_lang(v)) lang_cur = v; end
            if (k == "skin") skin = atoi(v) ? 1 : 0; end
            if (k == "tmdb") tmdb_key = v; end
        end
    end
    fclose(fh);
end

function cfg_save()
private int fh;
begin
    if (store_dir == "") return 0; end
    fh = fopen(join_path(store_dir, "config.cfg"), O_WRITE);
    if (!fh) return 0; end
    fputs(fh, "lang=" + lang_cur);
    fputs(fh, "skin=" + skin);
    fputs(fh, "tmdb=" + tmdb_key);
    fclose(fh);
end

function open_settings_menu(int keep)
begin
    menu_clear();
    menu_add(tr("m_lang") + tr("lang_name"), MA_LANG);
    menu_add(tr("m_skin") + (skin ? tr("skin_ps") : tr("skin_classic")), MA_SKIN);
    menu_add(tr("m_accounts"), MA_ACCOUNTS);
    menu_add(tr("m_tmdb"), MA_TMDB);
    menu_add(tr("m_about"), MA_ABOUT);
    menu_add(tr("m_back"), MA_CANCEL);
    menu_show(tr("mt_settings"));
    menu_sel = keep;
end

// ====================================================================== almacen, listas y editor
// Carpeta donde se guardan las listas: la primera de las candidatas en la que se pueda escribir
function storage_init()
private string c[5]; int i;
begin
    c[0] = getenv("MP_STORE");
    c[1] = "/data/mediaplayer";
    c[2] = "/mnt/usb0/mediaplayer";
    c[3] = "/download0/mediaplayer";
    c[4] = join_path(cd(), "mediaplayer_data");
    store_dir = "";
    for (i = 0; i < 5; i++)
        if (c[i] != "" && is_writable(c[i]))
            store_dir = c[i]; break;
        end
    end
    if (store_dir == "")
        // ninguna carpeta se puede escribir de verdad: se usa igualmente la mejor candidata, porque
        // el motor guarda en memoria y asi los ajustes y las listas funcionan al menos en esta sesion
        if (getenv("MP_STORE") != "") store_dir = getenv("MP_STORE"); else store_dir = c[4]; end
    end
    lists_dir = join_path(store_dir, "listas"); downloads_dir = join_path(store_dir, "descargas");
    mkdir(store_dir); mkdir(lists_dir); mkdir(join_path(store_dir, "addons")); mkdir(join_path(store_dir, "addons_data"));
    say("MediaPlayer: almacen = [" + store_dir + "]");
end

// ¿se puede escribir DE VERDAD en esta carpeta?  El fopen de los prg guarda en memoria cuando la
// ruta no existe (dice que si aunque en el disco no haya nada), asi que se prueba con http_write,
// que escribe con el disco real: asi en un PC no se elige /data/mediaplayer, que no se puede crear
function int is_writable(string d)
begin
    mkdir(d);
    mkdir(join_path(d, "listas"));
    if (!http_write(join_path(d, ".probe"), "ok")) return 0; end
    fremove(join_path(d, ".probe"));
    return 1;
end

// ISO-8859-1 -> UTF-8 (un caracter)
function string latin1_to_utf8(string ch)
private int c;
begin
    c = asc(ch);
    if (c < 128) return ch; end
    return chr(194 + (c >> 6)) + chr(128 + (c & 63));
end

// ---- lista de trabajo (titulo/url/logo de cada entrada de un .m3u)
// texto tras la primera coma fuera de comillas de una linea #EXTINF
function string extinf_title(string ln)
private int i, n, inq;
begin
    n = len(ln); inq = 0;
    for (i = 8; i < n; i++)
        if (substr(ln, i, 1) == "\"") inq = !inq; end
        if (!inq && substr(ln, i, 1) == ",") return substr(ln, i + 1); end
    end
    return "";
end

function wl_load(string path)
private
    int fh, q1, q2; string ln, title, logo;
begin
    wl_n = 0;
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    title = ""; logo = "";
    while (!feof(fh) && wl_n < 2047)
        ln = fgets(fh);
        if (len(ln) >= 3 && asc(substr(ln, 0, 1)) == 239) ln = substr(ln, 3); end      // marca BOM de UTF-8
        if (len(ln) > 0)
            if (substr(ln, 0, 8) == "#EXTINF:")
                // #EXTINF:-1 tvg-logo="https://...",Titulo   (el titulo va tras la primera coma que no este entre comillas)
                logo = "";
                q1 = find(ln, "tvg-logo=\"");
                if (q1 >= 0)
                    q2 = find(ln, "\"", q1 + 10);
                    if (q2 > q1) logo = substr(ln, q1 + 10, q2 - q1 - 10); end
                end
                title = extinf_title(ln);
            elseif (substr(ln, 0, 1) != "#")
                wl_t[wl_n] = title != "" ? title : ln; wl_u[wl_n] = ln; wl_l[wl_n] = logo;
                wl_n++; title = ""; logo = "";
            end
        end
    end
    fclose(fh);
    return 1;
end

function wl_save(string path)
private int fh, i;
begin
    fh = fopen(path, O_WRITE);
    if (!fh) toast(tr("t_save_fail")); return 0; end
    fputs(fh, "#EXTM3U");
    for (i = 0; i < wl_n; i++)
        if (wl_l[i] != "") fputs(fh, "#EXTINF:-1 tvg-logo=\"" + wl_l[i] + "\"," + wl_t[i]); else fputs(fh, "#EXTINF:-1," + wl_t[i]); end
        fputs(fh, wl_u[i]);
    end
    fclose(fh);
    return 1;
end

function string safe_name(string n)
private string r = ""; int i, c;
begin
    for (i = 0; i < len(n); i++)
        c = asc(substr(n, i, 1));
        if (c == 47 || c == 92 || c == 58 || c == 42 || c == 63 || c == 34 || c == 60 || c == 62 || c == 124 || c < 32) r += "_"; else r += substr(n, i, 1); end
    end
    return r;
end

function string list_path(string name)
begin
    return join_path(lists_dir, safe_name(name) + ".m3u");
end

function add_to_list(string path, string title, string url, string logo)
begin
    wl_load(path);
    if (wl_n >= 2047) toast(tr("t_list_full")); return 0; end
    wl_t[wl_n] = title; wl_u[wl_n] = url; wl_l[wl_n] = logo; wl_n++;
    return wl_save(path);
end

// ---- menus (pantalla completa) ----------------------------------------
function menu_clear()
begin
    menu_n = 0; menu_sel = 0;
end

function menu_add(string text, int act)
begin
    if (menu_n < 10) menu_opt[menu_n] = text; menu_act[menu_n] = act; menu_n++; end
end

function menu_show(string title)
begin
    menu_title = title; modal = M_MENU; modal_ver++;
end

function open_context_menu()
private string nm;
begin
    menu_clear();
    if (addon_mode > 0)
        // un video de un addon se puede guardar en la consola (los avisos de radio y audio no)
        if (dl_possible(sel) > 0) menu_add(tr("m_download"), MA_DOWNLOAD); end
        if (addon_mode == 2 || (sel > 0 && sel < n_entries && entry_dir[sel] == K_ADDON)) menu_add(tr("m_addon_settings"), MA_ASETTINGS); end
        menu_add(tr("m_settings"), MA_SETTINGS);
        menu_add(tr("m_cancel"), MA_CANCEL);
        menu_show(tr("s_addons"));
        return 0;
    end
    if (store_dir == "") toast(tr("t_no_store")); open_settings_menu(0); return 0; end
    if (cur_list != "")
        if (sel > 0 && sel < n_entries)
            menu_add(tr("m_rename_entry"), MA_RENAME_ENTRY);
            menu_add(tr("m_logo"), MA_LOGO);
            menu_add(tr("m_up"), MA_UP);
            menu_add(tr("m_down"), MA_DOWN);
            menu_add(tr("m_remove"), MA_REMOVE);
        end
        menu_add(tr("m_add_url"), MA_ADD_URL);
        menu_add(tr("m_list_account"), MA_LIST_ACCOUNT);
    else
        if (sel >= 0 && sel < n_entries && entry_dir[sel] == K_LIST)
            menu_add(tr("m_rename_list"), MA_RENAME_LIST);
            menu_add(tr("m_delete_list"), MA_DELETE_LIST);
            menu_add(tr("m_list_account"), MA_LIST_ACCOUNT);
        elseif (sel >= 0 && sel < n_entries && entry_dir[sel] == K_FILE)
            menu_add(tr("m_add_to"), MA_ADD_TO);
            if (cur_dir == downloads_dir) menu_add(tr("m_delete_dl"), MA_DELETE_DL); end
        end
        menu_add(tr("m_new_list"), MA_NEW_LIST);
        menu_add(tr("m_open_list"), MA_OPEN_LIST);
        menu_add(tr("m_goto_lists"), MA_GOTO_LISTS);
    end
    menu_add(tr("m_settings"), MA_SETTINGS);
    menu_add(tr("m_cancel"), MA_CANCEL);
    menu_show(cur_list != "" ? tr("mt_edit_list") : tr("mt_options"));
end

// elegir una lista para anadir lo pendiente (op_title / op_url)
function open_pick_list()
private int dh, k; string nm;
begin
    menu_clear();
    dh = diropen(join_path(lists_dir, "*"));
    if (dh)
        nm = dirread(dh);
        while (nm != "" && menu_n < 9)
            if (lcase(ext_of(nm)) == "m3u") pick_name[menu_n] = nm; menu_add(utf8_to_latin1(substr(nm, 0, len(nm) - 4)), MA_PICK + menu_n); end
            nm = dirread(dh);
        end
        dirclose(dh);
    end
    if (menu_n < 9) menu_add(tr("m_new_list_pick"), MA_NEW_AND_ADD); end
    menu_add(tr("m_cancel"), MA_CANCEL);
    menu_show(tr("mt_add_to_list"));
end

function menu_run(int act)
private int k;
begin
    modal = M_NONE;
    switch (act)
        case MA_CANCEL: end
        case MA_SETTINGS: open_settings_menu(0); end
        case MA_ASETTINGS:
            if (addon_mode == 1) addon_open_settings(entry_url[sel]); else addon_open_settings(addon_dir); end
        end
        case MA_LANG:
            lang_load(next_lang()); cfg_save(); open_settings_menu(0);
        end
        case MA_ABOUT: credits_open(); end
        case MA_TMDB:  kb_open(tr("k_tmdb"), tmdb_key, KB_TMDB); end
        case MA_DOWNLOAD:
            // se elige el formato: el video tal cual, el audio original o el audio convertido a otro formato
            dl_pick = sel;
            menu_clear();
            if (dl_possible(sel) == 1) menu_add(tr("m_dl_video"), MA_DL_VIDEO); end
            menu_add(tr("m_dl_audio"), MA_DL_AUDIO);
            for (k = 0; k < 5; k++) menu_add(tr("m_dl_conv") + " " + dl_fmt_name(k), MA_DL_FMT + k); end
            menu_add(tr("m_cancel"), MA_CANCEL);
            menu_show(tr("mt_dl_format"));
        end
        case MA_DL_VIDEO: dl_start(dl_pick, 0); end
        case MA_DL_AUDIO: dl_start(dl_pick, 1); end
        case MA_DELETE_DL:
            op_path = join_path(cur_dir, entries[sel]);
            menu_clear(); menu_add(tr("m_yes_delete") + " \"" + cut_text(utf8_to_latin1(entries[sel]), 24) + "\"", MA_DELETE_DL_YES); menu_add(tr("m_no"), MA_CANCEL);
            menu_show(tr("mt_sure"));
        end
        case MA_DELETE_DL_YES: fremove(op_path); toast(tr("t_dl_deleted")); read_dir(); end
        case MA_STORE_REFRESH: store_open(); end
        case MA_SKIN:
            skin = !skin; cfg_save(); open_settings_menu(1);
        end
        case MA_NEW_LIST:   op_after = 0; kb_open(tr("k_new_list"), "", KB_NEWLIST); end
        case MA_OPEN_LIST:  kb_open(tr("k_open_list"), "", KB_OPEN_LIST); end
        case MA_GOTO_LISTS: cur_list = ""; cur_dir = lists_dir; read_dir(); end
        case MA_ADD_TO:
            op_title = entries[sel]; op_url = entry_path(sel); op_logo = "";
            open_pick_list();
        end
        case MA_NEW_AND_ADD: op_after = 1; kb_open(tr("k_new_list"), "", KB_NEWLIST); end
        case MA_RENAME_LIST:
            op_path = join_path(cur_dir, entries[sel]);
            kb_open(tr("k_rename_list"), substr(entries[sel], 0, len(entries[sel]) - 4), KB_RENAME_LIST);
        end
        case MA_DELETE_LIST:
            op_path = join_path(cur_dir, entries[sel]);
            menu_clear(); menu_add(tr("m_yes_delete") + " \"" + cut_text(utf8_to_latin1(entries[sel]), 24) + "\"", MA_DELETE_YES); menu_add(tr("m_no"), MA_CANCEL);
            menu_show(tr("mt_sure"));
        end
        case MA_DELETE_YES: fremove(op_path); toast(tr("t_list_deleted")); read_dir(); end
        case MA_ADD_URL:    kb_open(tr("k_url"), "https://", KB_URL); end
        case MA_RENAME_ENTRY: wl_load(cur_list); op_idx = sel - 1; kb_open(tr("k_title"), utf8_to_latin1(wl_t[op_idx]), KB_ENTRY_TITLE); end
        case MA_LOGO:         wl_load(cur_list); op_idx = sel - 1; kb_open(tr("k_logo"), wl_l[op_idx] != "" ? wl_l[op_idx] : "https://", KB_LOGO); end
        case MA_REMOVE:
            wl_load(cur_list); op_idx = sel - 1; list_remove(op_idx); wl_save(cur_list); read_list(); toast(tr("t_removed"));
        end
        case MA_UP:   wl_load(cur_list); op_idx = sel - 1; list_swap(op_idx, op_idx - 1); wl_save(cur_list); read_list(); reselect(op_idx > 0 ? op_idx : 1); end
        case MA_DOWN: wl_load(cur_list); op_idx = sel - 1; list_swap(op_idx, op_idx + 1); wl_save(cur_list); read_list(); reselect(op_idx + 1 < wl_n ? op_idx + 2 : op_idx + 1); end
        case MA_LIST_ACCOUNT:
            if (cur_list != "") au_ask_account(cur_list);
            elseif (sel >= 0 && sel < n_entries && entry_dir[sel] == K_LIST) au_ask_account(join_path(cur_dir, entries[sel]));
            end
        end
        case MA_ACCOUNTS: open_accounts_menu(); end
        case MA_ACC_NEW:
            au_ask_next = 0; au_ask_name = ""; au_ask_file = "";
            au_mode = "xtream"; au_login_url = ""; au_server = ""; au_user = ""; au_pass = ""; au_token = "";
            kb_open(tr("k_xt_server"), au_test_val("MP_AUTH_SERVER", ""), KB_AUTH_SERVER);
        end
        case MA_ACC_EDIT:
            au_ask_account(join_path(lists_dir, acc_name[acc_sel] + ".m3u"));
        end
        case MA_ACC_OPEN:
            xt_enter(acc_name[acc_sel]);
        end
        case MA_ACC_DEL:
            au_clear(join_path(lists_dir, acc_name[acc_sel] + ".m3u"));
            toast(tr("t_auth_del"));
            open_accounts_menu();
        end
        default:
            if (act >= MA_ASET && act < MA_ASET + 24) addon_edit_setting(act - MA_ASET); end
            if (act >= MA_DL_FMT && act < MA_DL_FMT + 5) dl_start(dl_pick, 10 + act - MA_DL_FMT); end
            if (act >= MA_PICK && act < MA_PICK + 9)
                if (add_to_list(join_path(lists_dir, pick_name[act - MA_PICK]), op_title, op_url, op_logo)) toast(tr("t_added")); end
            end
            if (act >= MA_ACC_PICK && act < MA_ACC_PICK + 8) open_account_menu(act - MA_ACC_PICK); end
        end
    end
end

function reselect(int i)
begin
    if (i < 0) i = 0; end
    if (i >= n_entries) i = n_entries - 1; end
    sel = i; top_row = 0;
    if (sel >= ROWS) top_row = sel - ROWS + 1; end
end

function list_remove(int i)
private int k;
begin
    if (i < 0 || i >= wl_n) return 0; end
    for (k = i; k < wl_n - 1; k++) wl_t[k] = wl_t[k + 1]; wl_u[k] = wl_u[k + 1]; wl_l[k] = wl_l[k + 1]; end
    wl_n--;
end

function list_swap(int a, int b)
private string t, u, l;
begin
    if (a < 0 || b < 0 || a >= wl_n || b >= wl_n) return 0; end
    t = wl_t[a]; u = wl_u[a]; l = wl_l[a];
    wl_t[a] = wl_t[b]; wl_u[a] = wl_u[b]; wl_l[a] = wl_l[b];
    wl_t[b] = t; wl_u[b] = u; wl_l[b] = l;
end

// ---- teclado en pantalla ------------------------------------------------
function kb_open(string title, string initial, int purpose)
private int r, k; string s;
begin
    kb_title = title; kb_text = initial; if (getenv("MP_KB_TEXT") != "" && purpose != KB_AUTH_USER && purpose != KB_AUTH_PASS && purpose != KB_AUTH_SERVER) kb_text = getenv("MP_KB_TEXT"); end; kb_purpose = purpose; kb_secret = kb_secret_next; kb_secret_next = 0;
    kb_rows[0] = "1234567890"; kb_rows[1] = "qwertyuiop";
    kb_rows[2] = "asdfghjkl" + chr(241); kb_rows[3] = "zxcvbnm.-_"; kb_rows[4] = ":/?=&%+@,~";
    kb_sp[0] = tr("kb_shift"); kb_sp[1] = tr("kb_space"); kb_sp[2] = tr("kb_del"); kb_sp[3] = "https://"; kb_sp[4] = tr("kb_ok"); kb_sp[5] = tr("m_cancel");
    // posiciones (en pixeles) de las teclas de la fila especial, centradas
    k = 0;
    for (r = 0; r < 6; r++) kb_spw[r] = tw(kb_sp[r]); k += kb_spw[r] + 44; end
    k -= 44;
    kb_spx[0] = (SW - k) / 2;
    for (r = 1; r < 6; r++) kb_spx[r] = kb_spx[r - 1] + kb_spw[r - 1] + 44; end
    kb_r = 0; kb_c = 0; kb_shift = 0; kb_dirty = 1;
    // PS5: el teclado de la consola (si no esta disponible o falla, se usa este)
    if (!syskb_off && getenv("MP_KB_TEXT") == "")
        k = 0;
        if (kb_secret) k |= 1; end
        if (purpose == KB_URL || purpose == KB_LOGO || purpose == KB_AUTH_SERVER) k |= 2; end
        r = system_keyboard_open(kb_title, kb_text, 220, k);
        if (r == 0) modal = M_SYSKB; modal_ver++; return 0; end
        if (r != -2 && !kb_secret) syskb_off = 1; end      // una contrasena que el teclado del sistema no admite usa el propio solo esta vez
    end
    modal = M_KB; modal_ver++;
end

function kb_rebuild_rows()
private int r, c; string s, ch;
begin
    for (r = 0; r < 5; r++)
        s = "";
        for (c = 0; c < 10; c++)
            ch = substr(kb_rows[r], c, 1);
            if (kb_shift) ch = ucase(ch); end
            s += ch;
            if (c < 9) s += "  "; end
        end
        s_kbrow[r] = s;
    end
    s = "";
    for (r = 0; r < 6; r++)
        s += kb_sp[r];
        if (r < 5) s += "   "; end
    end
    for (r = 0; r < 6; r++) s_kbs[r] = kb_sp[r]; write_move(txt_kbs[r], ur(kb_spx[r]), ur(250 + 5 * 56)); end
    // lo escrito (se ve la cola si es largo) + cursor
    if (kb_secret)
        s = "";
        for (r = 0; r < len(kb_text) && r < 60; r++) s += "*"; end
        s_kbin = s + "_";
    else
        s_kbin = tail_fit(kb_text, 1000) + "_";
    end
    s_kbtitle = kb_title;
    kb_dirty = 0;
end

function kb_press()
private string ch;
begin
    if (kb_r < 5)
        ch = substr(kb_rows[kb_r], kb_c, 1);
        if (kb_shift) ch = ucase(ch); end
        if (len(kb_text) < 220) kb_text += latin1_to_utf8(ch); end
    else
        switch (kb_c)
            case 0: kb_shift = !kb_shift; end
            case 1: if (len(kb_text) < 220) kb_text += " "; end end
            case 2: kb_backspace(); end
            case 3: if (len(kb_text) < 200) kb_text += "https://"; end end
            case 4: kb_accept(); return 0; end
            case 5: modal = M_NONE; return 0; end
        end
    end
    kb_dirty = 1;
end

function kb_backspace()
begin
    if (len(kb_text) == 0) return 0; end
    kb_text = utf8_chop(kb_text);
    kb_dirty = 1;
end

function kb_accept()
private string nm, path; int ok;
begin
    modal = M_NONE;
    switch (kb_purpose)
        case KB_NEWLIST:
            nm = safe_name(kb_text);
            if (nm == "") toast(tr("t_name_empty")); return 0; end
            path = list_path(nm);
            if (fexists(path)) toast(tr("t_exists")); return 0; end
            wl_n = 0;
            if (wl_save(path))
                toast(tr("t_list_created") + nm);
                if (op_after) add_to_list(path, op_title, op_url, op_logo); toast(tr("t_created_added")); end
                if (lcase(cur_dir) == lcase(lists_dir) && cur_list == "") read_dir(); end
            end
        end
        case KB_RENAME_LIST:
            nm = safe_name(kb_text);
            if (nm == "") return 0; end
            fmove(op_path, join_path(parent_of(op_path), nm + ".m3u")); toast(tr("t_renamed")); read_dir();
        end
        case KB_OPEN_LIST:
            op_path = kb_text;
            if (op_path == "" || !fexists(op_path)) toast(tr("t_no_file")); return 0; end
            cur_list = op_path; cur_dir = parent_of(op_path);
            read_list();
        end
        case KB_URL:
            if (find(kb_text, "://") < 0 && substr(kb_text, 0, 1) != "/") toast(tr("t_bad_url")); return 0; end
            op_url = kb_text;
            op_title = substr(kb_text, find(kb_text, "://") + 3);
            kb_open(tr("k_entry_title"), utf8_to_latin1(cut_text(op_title, 40)), KB_NEW_TITLE);
        end
        case KB_NEW_TITLE:
            if (add_to_list(cur_list, kb_text != "" ? kb_text : op_url, op_url, "")) read_list(); reselect(n_entries - 1); toast(tr("t_added")); end
        end
        case KB_ENTRY_TITLE:
            wl_t[op_idx] = kb_text; if (wl_save(cur_list)) read_list(); reselect(op_idx + 1); end
        end
        case KB_ADDON: ask_ok = 1; ask_text = kb_text; end
        case KB_ASET: host_setting_set(ad_st_name[aset_idx], kb_text); addon_settings_menu(aset_idx); end
        case KB_AUTH_SERVER:
            au_server = kb_text;
            if (au_ask_name == "")
                au_ask_name = safe_name(au_server);
                au_ask_file = join_path(lists_dir, au_ask_name + ".m3u");
            end
            kb_open(tr("k_auth_user"), au_test_val("MP_AUTH_USER", au_user), KB_AUTH_USER);
        end
        case KB_AUTH_USER:
            au_user = kb_text; kb_secret_next = 1;
            kb_open(tr("k_auth_pass"), au_test_val("MP_AUTH_PASS", ""), KB_AUTH_PASS);
        end
        case KB_AUTH_PASS:
            au_pass = kb_text;
            if (au_mode == "xtream")
                au_finish();
                xt_enter(au_ask_name);
            else
                if (au_finish() == -1)
                    show_error(tr("mt_account"), tr("t_auth_login"));
                    au_ask_next = 0;
                else
                    if (au_ask_next == 1) store_install(au_ask_row); else toast(tr("t_auth_saved")); end
                end
            end
        end
        case KB_TMDB:
            tmdb_key = kb_text; cfg_save(); open_settings_menu(0); toast(tr("t_tmdb_saved"));
        end
        case KB_LOGO:
            wl_l[op_idx] = (kb_text == "https://") ? "" : kb_text; if (wl_save(cur_list)) read_list(); reselect(op_idx + 1); toast(tr("t_logo_updated")); end
        end
    end
end

// ---- control y dibujo del modal -------------------------------------------
// ---------------------------------------------------------------- creditos (tipo pelicula)
function cr_add(string t, int style)
private int k;
begin
    if (t == "") cr_s[cr_n] = ""; cr_st[cr_n] = style; cr_n++; return 0; end
    wrap_text(t, 980, 2);
    for (k = 0; k < wrap_n && cr_n < 46; k++) cr_s[cr_n] = wrap_l[k]; cr_st[cr_n] = style; cr_n++; end
end

function credits_open()
private int i;
begin
    cr_n = 0;
    cr_add(tr("cr_title"), 1); cr_add("", 0);
    cr_add(tr("cr_created"), 1); cr_add(tr("cr_names"), 0); cr_add("", 0);
    cr_add(tr("cr_h_thanks"), 1); cr_add(tr("cr_t1"), 0); cr_add(tr("cr_t2"), 0); cr_add("", 0);
    cr_add(tr("cr_h_also"), 1);
    for (i = 1; i <= 7; i++) cr_add(tr("cr_a" + i), 0); end
    cr_add("", 0); cr_add(tr("cr_end"), 1);
    for (i = 0; i < cr_n; i++)
        cr_id[i] = 0;
        if (cr_s[i] != "")
            cr_id[i] = write_var(fnt_t, ur(SW / 2), ur(SH + 40 + i * 56), -5, 4, cr_s[i]);   // detras de las sombras (-10) y de la ayuda (-12/-30)
            if (cr_st[i] == 1) write_set_rgba(cr_id[i], 255, 210, 90, 255); else write_set_rgba(cr_id[i], 255, 255, 255, 255); end
        end
    end
    cr_pos = 0; cr_fast = 0; modal = M_CREDITS; modal_ver++;
end

function credits_close()
private int i;
begin
    for (i = 0; i < cr_n; i++)
        if (cr_id[i] > 0) write_delete(cr_id[i]); cr_id[i] = 0; end
    end
    cr_n = 0;
    open_settings_menu(2);
end

function update_modal()
private int st, ok, i;
begin
    if (modal == M_MENU)
        if (act_press[A_UP])   menu_sel = (menu_sel + menu_n - 1) % menu_n; end
        if (act_press[A_DOWN]) menu_sel = (menu_sel + 1) % menu_n; end
        if (act_press[A_OK])   menu_run(menu_act[menu_sel]); end
        if (act_press[A_BACK] || act_press[A_MUTE]) modal = M_NONE; end
    elseif (modal == M_CREDITS)
        cr_pos += cr_fast ? 300 : 80;
        if (act_press[A_OK]) cr_fast = !cr_fast; end
        if (act_press[A_BACK] || act_press[A_MUTE]) credits_close(); return 0; end
        if (cr_n > 0 && SH + 40 + (cr_n - 1) * 56 - cr_pos / 100 < -30) credits_close(); end
    elseif (modal == M_SYSKB)
        // el teclado de la consola va en su propia ventana: aqui solo se espera a que se cierre (los botones los lee el)
        st = system_keyboard_status();
        if (st == 2)
            ok = system_keyboard_ok(); kb_text = system_keyboard_text(); system_keyboard_close();
            for (i = 0; i < A_COUNT; i++) act_press[i] = 0; end        // el boton que cerro el teclado no debe llegar al explorador
            if (ok) kb_accept(); else modal = M_NONE; end
        elseif (st == 0)
            modal = M_NONE;
        end
    elseif (modal == M_KB)
        if (act_press[A_UP])
            if (kb_r == 5) kb_c = kb_c * 10 / 6; if (kb_c > 9) kb_c = 9; end end
            kb_r = (kb_r + 5) % 6;
            if (kb_r == 5) kb_c = kb_c * 6 / 10; end
        end
        if (act_press[A_DOWN])
            if (kb_r == 5) kb_c = kb_c * 10 / 6; if (kb_c > 9) kb_c = 9; end end
            kb_r = (kb_r + 1) % 6;
            if (kb_r == 5) kb_c = kb_c * 6 / 10; end
        end
        if (act_press[A_LEFT])  kb_c = (kb_c + (kb_r == 5 ? 5 : 9)) % (kb_r == 5 ? 6 : 10); end
        if (act_press[A_RIGHT]) kb_c = (kb_c + 1) % (kb_r == 5 ? 6 : 10); end
        if (act_press[A_OK])     kb_press(); end
        if (act_press[A_MUTE])   kb_backspace(); end
        if (act_press[A_SUBS])   if (len(kb_text) < 220) kb_text += " "; kb_dirty = 1; end end
        if (act_press[A_SEEKB])  kb_shift = !kb_shift; kb_dirty = 1; end
        if (act_press[A_PAUSE])  kb_accept(); end
        if (act_press[A_BACK])   modal = M_NONE; end
    end
end

// los textos del menu / teclado solo se rehacen al abrir o cambiar de pantalla
function modal_labels()
private int i;
begin
    if (mlbl_ver == modal_ver) return 0; end
    if (modal == M_MENU)
        s_mtitle = menu_title;
        for (i = 0; i < 10; i++) s_mopt[i] = i < menu_n ? fit_text(menu_opt[i], 900) : ""; end
        s_mhint = tr("h_menu");
    else
        s_mtitle = kb_title;
        s_mhint = tr("h_kb");
    end
    mlbl_ver = modal_ver; dlg_key = -1;
end

// Menu de opciones al estilo Kodi: ventana centrada y translucida sobre el explorador atenuado, con titulo, una linea
// y una barra de seleccion de ancho completo
function draw_menu_dialog()
private int i, w, h, x0, y0, k;
begin
    modal_labels();
    w = tw(s_mtitle) + 120; if (w < 560) w = 560; end
    for (i = 0; i < menu_n; i++) k = tw(s_mopt[i]) + 130; if (k > w) w = k; end end
    if (w > 1100) w = 1100; end
    h = 112 + menu_n * 52;
    x0 = (SW - w) / 2; y0 = (SH - h) / 2;
    put(S_OVDIM, g_ovdim, SW / 2, SH / 2, 100, 255, -21);
    spr_sizex[S_OVDIM] = SW / 8 * 100; spr_sizey[S_OVDIM] = SH / 8 * 100;
    put(S_OVBOX, g_ovbox, SW / 2, SH / 2, 100, 255, -22);
    spr_sizex[S_OVBOX] = w * 100 / 8; spr_sizey[S_OVBOX] = h * 100 / 8;
    put(S_OVBG, g_barbg, SW / 2, y0 + 78, 100, 255, -23);
    spr_sizex[S_OVBG] = (w - 60) * 100 / 8; spr_sizey[S_OVBG] = 2 * 100 / 8;
    k = (menu_n * 2000 + w) * 4096 + tw(s_mtitle);
    if (k != dlg_key)                                // los textos se recolocan solo si cambia la forma de la ventana
        dlg_key = k;
        write_move(txt_mtitle, ur((SW - tw(s_mtitle)) / 2), ur(y0 + 40));
        for (i = 0; i < 10; i++) write_move(txt_mopt[i], ur(x0 + 54), ur(y0 + 118 + i * 52)); end
    end
    txt_want[txt_mtitle] = 8589934336 + (255);
    for (i = 0; i < menu_n; i++) txt_want[txt_mopt[i]] = 8589934336 + (i == menu_sel ? 255 : 190); end
    put_sel(S_MSEL, SW / 2, y0 + 118 + menu_sel * 52, w - 36, 46, -24);
    if (skin) hint_set(2); else txt_want[txt_mhint] = 8589934336 + (170); end
end

function draw_modal()
private int i, bx, by, k; string t;
begin
    // fondo de pantalla completa
    if (skin)
        draw_bg();
    else
        put(S_BROWSE_BG, g_sel, SW / 2, SH / 2, 100, 255, 20);
        spr_sizex[S_BROWSE_BG] = SW / 8 * 100; spr_sizey[S_BROWSE_BG] = SH / 8 * 100;
    end
    if (modal == M_CREDITS)
        for (i = 0; i < cr_n; i++)
            if (cr_id[i] > 0) write_move(cr_id[i], ur(SW / 2), ur(SH + 40 + i * 56 - cr_pos / 100)); end
        end
        put(S_SHADE_TOP, g_shade_top, SW / 2, 64, 100, 255, -10);
        spr_sizex[S_SHADE_TOP] = SW / 64 * 100; spr_sizey[S_SHADE_TOP] = 150;
        put(S_SHADE_BOT, g_shade, SW / 2, SH - 128, 100, 255, -10);
        spr_sizex[S_SHADE_BOT] = SW / 64 * 100; spr_sizey[S_SHADE_BOT] = 100;
        if (skin) hint_set(4); else txt_want[txt_mhint] = 8589934336 + (170); end
        return 0;
    end
    modal_labels();
    txt_want[txt_mtitle] = 8589934336 + (255);
    if (modal == M_SYSKB)
        txt_want[txt_mhint] = 8589934336 + (0);
    elseif (skin) hint_set(modal == M_MENU ? 2 : 3); else txt_want[txt_mhint] = 8589934336 + (170); end
    if (modal == M_MENU)
        for (i = 0; i < menu_n; i++)
            txt_want[txt_mopt[i]] = 8589934336 + (i == menu_sel ? 255 : 190);
        end
        k = tw(menu_opt[menu_sel]) + 100; if (k < 640) k = 640; end
        put_sel(S_MSEL, 80 + k / 2, 170 + menu_sel * 52, k, 46, 15);
    elseif (modal == M_KB)
        if (kb_dirty) kb_rebuild_rows(); end
        txt_want[txt_kbin] = 8589934336 + (255);
        put(S_PANEL, g_barbg, SW / 2, 170, 100, 255, 12);
        spr_sizex[S_PANEL] = 1100 / 8 * 100; spr_sizey[S_PANEL] = 44 * 100 / 8;
        for (i = 0; i < 5; i++) txt_want[txt_kbrow[i]] = 8589934336 + (230); end
        for (i = 0; i < 6; i++) txt_want[txt_kbs[i]] = 8589934336 + (230); end
        if (kb_r < 5)
            bx = SW / 2 - (28 * 1556) / 200 + ((kb_c * 6 + 1) * 1556) / 200; by = 250 + kb_r * 56;   // 15,56 px de avance por caracter de la fuente
            put_sel(S_MSEL, bx, by, 40, 44, 15);
        else
            bx = kb_spx[kb_c] + kb_spw[kb_c] / 2; by = 250 + 5 * 56;
            put_sel(S_MSEL, bx, by, kb_spw[kb_c] + 28, 44, 15);
        end
    end
end

// ------------------------------------------------------------------ reproductor
function start_video(string path)
private int i;
begin
    http_trace("start_video: close_preview");
    close_preview(); pv_idx = -1;
    http_trace("start_video: video_close");
    if (vh) video_close(vh); vh = 0; end
    http_trace("start_video: video_open");
    if (au_headers() != "") vh = video_open_h(path, au_headers()); else vh = video_open(path); end
    http_trace("start_video: abierto " + vh);
    if (!vh)
        toast(tr("t_open_fail"));
        state = ST_BROWSE;
        return 0;
    end
    cur_file = path;
    vid_w = video_width(vh); vid_h = video_height(vh);
    spr_graph[S_VIDEO] = video_graph(vh);

    // subtitulo externo con el mismo nombre (.srt)
    i = len(path) - len(ext_of(path));
    if (find(path, "://") < 0 && fexists(substr(path, 0, i) + "srt")) video_subtitle_load(vh, substr(path, 0, i) + "srt"); end
    sub_tracks = video_subtitle_tracks(vh);
    sub_sel = sub_tracks > 0 ? 0 : -1;
    video_subtitle_select(vh, sub_sel);

    music_mode = video_is_audio_only(vh) || is_audio(path);
    for (i = 0; i < 32; i++) viz_cur[i] = 0; viz_peak[i] = 0; end
    if (logo_h) video_close(logo_h); logo_h = 0; end
    if (music_mode && pending_logo != "")           // el logo se abre como un "video" de un solo fotograma (FFmpeg lee la imagen por red)
        video_use_hw(0);
        logo_h = video_open(pending_logo);
        video_use_hw(1);
        if (logo_h) video_play(logo_h, 0); end
    end
    pending_logo = "";
    if (hls_url != "" && hls_total == 0) hls_total = video_duration(vh); end
    audio_tracks = video_audio_tracks(vh);
    audio_sel = 0;
    video_volume(vh, muted ? 0 : vol * 128 / 100);
    video_play(vh, 0);
    state = ST_PLAY;
    overlay_a = 255; overlay_t = 0; focus = B_PLAY;
    s_title = pending_title != "" ? utf8_to_latin1(pending_title) : base_name(path);
    pending_title = "";
    if (sub_tracks > 0) toast(tr("t_subs") + sub_name()); end
    return 1;
end

function stop_video()
begin
    if (vh) video_close(vh); end
    vh = 0;
    spr_graph[S_VIDEO] = 0;
    music_mode = 0;
    if (logo_h) video_close(logo_h); logo_h = 0; end
    s_sub[0] = ""; s_sub[1] = ""; s_sub[2] = "";
    state = ST_BROWSE;
    lbl_ver = -1; last_sec = -1; pv_idx = -1;
end

function toast(string t)
begin
    s_toast = t; toast_t = 150;
end

function string sub_name()
begin
    if (sub_sel < 0) return tr("t_off"); end
    return video_subtitle_lang(vh, sub_sel);
end

function cycle_subs()
begin
    if (sub_tracks == 0) toast(tr("t_no_subs")); return 0; end
    sub_sel++;
    if (sub_sel >= sub_tracks) sub_sel = -1; end
    video_subtitle_select(vh, sub_sel);
    toast(tr("t_subs") + sub_name());
end

function cycle_audio()
begin
    if (audio_tracks < 2)
        toast(audio_tracks == 0 ? tr("t_no_audio") : tr("t_one_audio"));
        return 0;
    end
    audio_sel = (audio_sel + 1) % audio_tracks;
    video_audio_select(vh, audio_sel);
    toast(tr("t_audio") + video_audio_lang(vh, audio_sel));
end

function set_volume(int v)
begin
    vol = v < 0 ? 0 : (v > 100 ? 100 : v);
    muted = 0;
    video_volume(vh, vol * 128 / 100);
    toast(tr("t_volume") + vol + "%");
end

function toggle_mute()
begin
    muted = !muted;
    video_volume(vh, muted ? 0 : vol * 128 / 100);
    toast(muted ? tr("t_muted") : tr("t_volume") + vol + "%");
end

// posicion y duracion totales (en una lista HLS regenerada la posicion del motor es relativa a hls_base)
function int vpos()
begin
    if (hls_seek_to >= 0) return hls_seek_to; end
    return video_position(vh) + hls_base;
end

function int vdur()
begin
    if (hls_total > 0) return hls_total; end
    return video_duration(vh);
end

function seek_rel(int ms)
private int p;
begin
    if (hls_url != "")
        // cada salto reabre el stream: las pulsaciones seguidas se juntan en uno solo y el paso crece si se mantiene
        if (get_timer() - hls_seek_t > 1500) hls_streak = 0; end
        hls_streak++; hls_seek_t = get_timer();
        p = hls_streak < 4 ? 1 : (hls_streak < 8 ? 3 : (hls_streak < 14 ? 6 : 12));
        p = vpos() + ms * p;
        if (p < 0) p = 0; end
        if (vdur() > 0 && p > vdur() - 500) p = vdur() - 500; end
        hls_seek_to = p;
        return 0;
    end
    p = vpos() + ms;
    if (p < 0) p = 0; end
    if (vdur() > 0 && p > vdur() - 500) p = vdur() - 500; end
    video_seek(vh, p - hls_base);
end

function toggle_pause()
begin
    if (video_is_playing(vh)) video_pause(vh, 1); else video_pause(vh, 0); end
end

function next_video(int dir)
private int i;
begin
    i = cur_file_idx + dir;
    while (i >= 0 && i < n_entries)
        if ((entry_dir[i] == K_FILE || entry_dir[i] == K_URL) && entries[i] != "..")
            request_open(i); return 1;
        end
        i += dir;
    end
    toast(dir > 0 ? tr("t_no_more") : tr("t_no_prev"));
    return 0;
end

function press_button(int b)
begin
    switch (b)
        case B_PREV: next_video(-1); end
        case B_RW:   seek_rel(-10000); end
        case B_PLAY: toggle_pause(); end
        case B_STOP: stop_video(); end
        case B_FF:   seek_rel(10000); end
        case B_NEXT: next_video(1); end
        case B_SUBS: cycle_subs(); end
        case B_AUDIO: cycle_audio(); end
        case B_VOL:  toggle_mute(); end
    end
end

function update_player()
private int shown, hs;
begin
    if (!vh) state = ST_BROWSE; return 0; end

    // salto pendiente en un stream HLS: se ejecuta cuando se deja de pulsar
    if (hls_seek_to >= 0 && get_timer() - hls_seek_t > 450)
        hs = hls_seek_to; hls_seek_to = -1;
        if (!hls_reseek(hs)) video_seek(vh, hs - hls_base); end
    end

    // fin del video: siguiente o volver al explorador
    if (video_is_finished(vh))
        if (!next_video(1)) stop_video(); end
        return 0;
    end

    shown = overlay_a > 40;   // los iconos estan "tocables" mientras se ven

    if (any_input && !(act_hold[A_UP] && !shown && 0)) overlay_t = 0; end

    // atajos que funcionan siempre
    if (act_press[A_SEEKB]) seek_rel(-10000); toast("-10 s"); end
    if (act_press[A_SEEKF]) seek_rel(10000);  toast("+10 s"); end
    if (act_press[A_PAUSE]) toggle_pause(); end
    if (act_press[A_SUBS])
        if (music_mode) viz_mode = !viz_mode; toast(viz_mode ? tr("t_viz_wave") : tr("t_viz_bars")); else cycle_subs(); end
    end
    if (act_press[A_AUDIO]) cycle_audio(); end
    if (act_press[A_MUTE])  toggle_mute(); end
    if (act_press[A_BACK])
        if (shown && video_is_playing(vh) == 0) stop_video(); return 0; end
        stop_video(); return 0;
    end

    if (shown)
        // con iconos visibles: la cruceta mueve el foco
        if (act_press[A_LEFT])  focus = (focus + B_COUNT - 1) % B_COUNT; end
        if (act_press[A_RIGHT]) focus = (focus + 1) % B_COUNT; end
        if (act_press[A_UP])    set_volume(vol + 5); end
        if (act_press[A_DOWN])  set_volume(vol - 5); end
        if (act_press[A_OK])    press_button(focus); end
    else
        // iconos ocultos: la cruceta salta/regula, X pausa
        if (act_press[A_LEFT])  seek_rel(-10000); toast("-10 s"); end
        if (act_press[A_RIGHT]) seek_rel(10000);  toast("+10 s"); end
        if (act_press[A_UP])    set_volume(vol + 5); end
        if (act_press[A_DOWN])  set_volume(vol - 5); end
        if (act_press[A_OK])    toggle_pause(); end
    end

    // el overlay se queda si esta en pausa (y siempre en la musica)
    if (!video_is_playing(vh) || music_mode) overlay_t = 0; end
    if (overlay_t < HIDE_AFTER)
        overlay_t++;
        overlay_a += 24; if (overlay_a > 255) overlay_a = 255; end
    else
        overlay_a -= 10; if (overlay_a < 0) overlay_a = 0; end
    end
    if (toast_t > 0) toast_t--; end
end

// ------------------------------------------------------------------ composicion
function string fmt_time(int ms)
private int s;
begin
    s = ms / 1000;
    if (s >= 3600) return (s / 3600) + ":" + pad2((s / 60) % 60) + ":" + pad2(s % 60); end
    return pad2(s / 60) + ":" + pad2(s % 60);
end

function string pad2(int n)
begin
    if (n < 10) return "0" + n; end
    return "" + n;
end

// UTF-8 -> ISO-8859-1 para las fuentes de mapa de bits
// Antes convertia UTF-8 a ISO-8859-1 para la fuente de mapa de bits; la interfaz usa fuentes TrueType (UTF-8), asi que es la identidad
function string utf8_to_latin1(string s)
begin
    return s;
end

function hide_sprites()
private int i;
begin
    for (i = 0; i < S_COUNT; i++)
        if (i != S_VIDEO) spr_alpha[i] = 0; spr_graph[i] = 0; end
    end
end

function put(int slot, int g, int px, int py, int sz, int a, int zz)
begin
    spr_graph[slot] = g; spr_x[slot] = px; spr_y[slot] = py;
    spr_sizey[slot] = sz; spr_sizex[slot] = sz; spr_alpha[slot] = a; spr_z[slot] = zz;
end

// Cambiar el color de un texto lo vuelve a generar y acumula memoria: layout_all solo anota lo que quiere
// (txt_want) y aqui se aplica unicamente lo que ha cambiado de verdad
function apply_texts()
private int tid, k;
begin
    for (tid = 1; tid < 128; tid++)
        k = txt_want[tid];
        if (k != 0 && k != txt_cache[tid])
            txt_cache[tid] = k;
            write_set_rgba(tid, (k >> 24) & 255, (k >> 16) & 255, (k >> 8) & 255, k & 255);
        end
    end
end

function layout_all()
private
    int i, a, bx, by, n, pos, dur, pct, px, g, rowi, k, p1, p2, lines, w, h;
    string t, l[3];
begin
    hide_sprites();
    for (i = 0; i < ROWS; i++) txt_want[txt_row[i]] = 8589934336 + (0); end
    txt_want[txt_path] = 8589934336 + (0); txt_want[txt_hint] = 8589934336 + (0); txt_want[txt_empty] = 8589934336 + (0);
    txt_want[txt_time] = 8589934336 + (0); txt_want[txt_title] = 8589934336 + (0); txt_want[txt_toast] = 8589934336 + (0);
    for (i = 0; i < 6; i++) txt_want[txt_sub[i]] = 8589934336 + (0); end
    for (i = 0; i < 7; i++) txt_want[txt_info[i]] = 8589934336 + (0); end
    for (i = 0; i < 5; i++) txt_want[txt_tab[i]] = 8589934336 + (0); end
    txt_want[txt_amsg] = 8589934336 + (0); txt_want[txt_ovt] = 8589934336 + (0); txt_want[txt_ovp] = 8589934336 + (0); txt_want[txt_ovh] = 8589934336 + (0);
    txt_want[txt_mtitle] = 8589934336 + (0); txt_want[txt_mhint] = 8589934336 + (0); txt_want[txt_kbin] = 8589934336 + (0); for (i = 0; i < 6; i++) txt_want[txt_kbs[i]] = 8589934336 + (0); end
    for (i = 0; i < 10; i++) txt_want[txt_mopt[i]] = 8589934336 + (0); end
    for (i = 0; i < 5; i++) txt_want[txt_kbrow[i]] = 8589934336 + (0); end
    for (i = 0; i < 6; i++) txt_want[txt_h[i]] = 8589934336 + (0); end
    for (i = 0; i < 6; i += 2) txt_want[txt_sub[i]] = 4294967296; end

    if (modal != M_NONE && !(modal == M_MENU && state == ST_BROWSE)) draw_modal(); return 0; end

    if (state == ST_BROWSE)
        // ---- explorador
        update_cell_logos();
        // los textos solo se rehacen al cambiar de carpeta o de pagina (crear cadenas cada fotograma es caro y las acumula)
        if (lbl_ver != dir_ver || lbl_top != top_row)
            if (store_mode == 1) s_path = "  " + tr("s_store"); elseif (addon_mode == 2) s_path = "  " + addon_name; elseif (addon_mode == 1) s_path = "  " + tr("s_addons"); elseif (cur_list != "") s_path = "  " + utf8_to_latin1(base_name(cur_list)) + "   " + tr("s_internet_tag"); else s_path = "  " + utf8_to_latin1(cur_dir); end
                s_empty = tr("s_empty");
            s_hint = tr("h_browser") + "    [" + (store_dir != "" ? cut_text(store_dir, 24) : tr("s_nostore")) + "]";
            for (i = 0; i < ROWS; i++)
                rowi = top_row + i;
                if (rowi < n_entries)
                    row_label[i] = disp_name(rowi);
                    row_label[i] = fit_text(row_label[i], grid_mode == 1 ? 150 : 590);
                    if (getenv("MP_DEBUG") != "" && grid_mode == 1) say("GRIDLBL [" + i + "] '" + row_label[i] + "' tw=" + tw(row_label[i]) + " orig='" + disp_name(rowi) + "'"); end
                else
                    row_label[i] = "";
                end
            end
            // al cambiar entre lista y cuadricula los textos de fila se recrean en su sitio:
            // moverlos con write_move no vale (el identificador se recicla y se rompe el dibujo)
            if (grid_mode != grid_last)
                grid_last = grid_mode;
                for (i = 0; i < ROWS; i++)
                    if (txt_row[i] > 0) write_delete(txt_row[i]); txt_cache[txt_row[i]] = 0; end
                    if (grid_mode == 1)
                        // alineacion 4 = centrado: el motor lo recentra cada vez que cambia el texto
                        txt_row[i] = write_var(fnt_t, ur(grid_cx(i)), ur(grid_cy(i) + 30), -20, 4, row_label[i]);
                    else
                        txt_row[i] = write_var(fnt_t, ur(110), ur(ROW_Y0 + i * ROW_H + ROW_H / 2), -20, 3, row_label[i]);
                    end
                end
            end

            lbl_ver = dir_ver; lbl_top = top_row;
        end
        k = cur_section();
        if (k >= 0)
            draw_tabs(k);
        else
            txt_want[txt_path] = 8589934336 + (255);
            put(S_HEADER, g_icon[10], 42, 40, 40, 200, -10);
        end
        draw_bg();
        if (modal == M_MENU)
            // el menu de opciones se dibuja encima (ver mas abajo) con su propia barra de ayuda
        elseif (skin) hint_set(store_mode == 1 ? 5 : 1); else txt_want[txt_hint] = 8589934336 + (150); end

        if (n_entries == 0 && !addon_busy)
            txt_want[txt_empty] = 8589934336 + (200);
        end
        for (i = 0; i < ROWS; i++)
            rowi = top_row + i;
            if (rowi < n_entries)
                by = ROW_Y0 + i * ROW_H + ROW_H / 2;
                if (grid_mode == 1) by = grid_cy(i); end
                txt_want[txt_row[i]] = 8589934336 + (rowi == sel && !tab_focus ? 255 : 190);
                switch (entry_dir[rowi])
                    case K_DIR, K_MYLISTS, K_AFOLDER, K_DOWNLOADS: g = g_icon[10]; end
                    case K_ADDONS, K_ADDON: g = g_icon[16]; end
                    case K_STORE: g = g_icon[14]; end
                    case K_SITEM: if (entry_skind[rowi] == 1) g = entry_siver[rowi] != "" ? g_icon[11] : g_icon[14]; else g = entry_siver[rowi] != "" ? g_icon[16] : g_icon[14]; end end
                    case K_LIST: g = g_icon[14]; end
                    case K_URL: g = (addon_mode == 2 && entry_akind[rowi] == 1) ? g_icon[11] : ((addon_mode == 2 && entry_akind[rowi] >= 2) ? g_icon[15] : g_icon[14]); end
                    default: g = is_audio(entries[rowi]) ? g_icon[15] : g_icon[11]; end
                end
                if (entries[rowi] == "..") g = g_icon[12]; end
                if (grid_mode == 1)
                    if (cell_map[i] > 0)
                        // el logo del canal, centrado en la casilla
                        k = 0; w = graphic_info(0, cell_map[i], G_WIDTH); h = graphic_info(0, cell_map[i], G_HEIGHT);
                        if (w > 0) k = 10000 / w; end
                        if (h > 0 && 6000 / h < k) k = 6000 / h; end   // que el logo no llegue al nombre
                        put(S_ROWICON + i, cell_map[i], grid_cx(i), by - 26, k, rowi == sel ? 255 : 210, -10);
                    else
                        put(S_ROWICON + i, g, grid_cx(i), by - 26, 48, rowi == sel ? 255 : 170, -10);
                    end
                    if (rowi == sel && !tab_focus) put_sel(S_SEL, grid_cx(i), by - 26, 150, 118, 2); end
                else
                    put(S_ROWICON + i, g, 70, by, 38, rowi == sel ? 255 : 170, -10);
                    if (rowi == sel && !tab_focus) put_sel(S_SEL, 382, by, 700, ROW_H, 2); end
                end
            end
        end
        // panel de previsualizacion: recuadro 460x260 + informacion
        put(S_PANEL, g_barbg, 990, 260, 100, 255, 6);
        spr_sizex[S_PANEL] = 460 / 8 * 100; spr_sizey[S_PANEL] = 260 / 8 * 100 + 1;
        if (pv_phase == 2 && pv_h)
            if (video_width(pv_h) > 0) k = 460 * 100 / video_width(pv_h); i = 260 * 100 / video_height(pv_h); else k = 100; i = 100; end
            if (i < k) k = i; end
            put(S_PREVIEW, video_graph(pv_h), 990, 260, k, 255, 5);
            if (video_is_audio_only(pv_h)) put(S_PREVIEW, g_icon[15], 990, 260, 190, 230, 5); end
        elseif (grid_mode == 1 && sel >= 0 && sel < n_entries && sel - top_row >= 0 && sel - top_row < ROWS && cell_map[sel - top_row] > 0)
            // mientras llega la miniatura del canal se ve su logo (tarda menos)
            k = 460 * 100 / graphic_info(0, cell_map[sel - top_row], G_WIDTH);
            i = graphic_info(0, cell_map[sel - top_row], G_HEIGHT) > 0 ? 260 * 100 / graphic_info(0, cell_map[sel - top_row], G_HEIGHT) : 100;
            if (i < k) k = i; end
            if (k > 0) put(S_PREVIEW, cell_map[sel - top_row], 990, 260, k, 255, 5); end
        end
        for (i = 0; i < 7; i++) txt_want[txt_info[i]] = 8589934336 + (i == 0 ? 255 : 200); end
        if (pv_phase == 3) s_info[2] = tr("s_nopreview"); end
        if (addon_busy && !ov_on) txt_want[txt_amsg] = 8589934336 + (255); end
        if (ov_on) draw_overlay(); end
        if (modal == M_MENU) draw_menu_dialog(); end
        if (toast_t > 0) toast_t--; end
        if (toast_t > 0) txt_want[txt_toast] = 8589934336 + (255); end
        return 0;
    end

    // ---- reproductor
    if (music_mode)
        // fondo oscuro, portada (si el archivo la trae) o nota, y el visualizador a la derecha
        if (skin)
            draw_bg();
        else
            put(S_BROWSE_BG, g_sel, SW / 2, SH / 2, 100, 255, 20);
            spr_sizex[S_BROWSE_BG] = SW / 8 * 100; spr_sizey[S_BROWSE_BG] = SH / 8 * 100;
        end
        if (logo_h && video_width(logo_h) > 0)
            // logo de la emisora sobre un fondo claro translucido (por si es de letras oscuras)
            put(S_PANEL, g_barbg, 330, 290, 100, 255, 12);
            spr_sizex[S_PANEL] = 380 / 8 * 100; spr_sizey[S_PANEL] = 380 / 8 * 100;
            k = 360 * 100 / video_width(logo_h); i = 360 * 100 / video_height(logo_h);
            if (i < k) k = i; end
            put(S_VIDEO, video_graph(logo_h), 330, 290, k, 255, 10);
        elseif (vid_w > 0 && vid_h > 0)
            k = 360 * 100 / vid_w; i = 360 * 100 / vid_h;
            if (i < k) k = i; end
            put(S_VIDEO, spr_graph[S_VIDEO], 330, 290, k, 255, 10);
        else
            put(S_VIDEO, g_icon[15], 330, 290, 330, 230, 10);
        end
        update_viz();
        put(S_VIZ, g_viz, 900, 330, 100, 255, -3);
        txt_want[txt_title] = 8589934336 + (255);
    elseif (vid_w > 0 && vid_h > 0)
        k = SW * 100 / vid_w; i = SH * 100 / vid_h;
        if (i < k) k = i; end
        put(S_VIDEO, spr_graph[S_VIDEO], SW / 2, SH / 2, k, 255, 10);
    end

    a = overlay_a;
    if (a > 0)
        // sombras arriba y abajo
        put(S_SHADE_BOT, g_shade, SW / 2, SH - 128, 100, a, 5);
        spr_sizex[S_SHADE_BOT] = SW / 64 * 100; spr_sizey[S_SHADE_BOT] = 100;
        put(S_SHADE_TOP, g_shade_top, SW / 2, 64, 100, a * 2 / 3, 5);
        spr_sizex[S_SHADE_TOP] = SW / 64 * 100; spr_sizey[S_SHADE_TOP] = 100;

        // botones
        by = SH - 72;
        for (i = 0; i < B_COUNT; i++)
            switch (i)
                case B_PREV: g = g_icon[4]; end
                case B_RW:   g = g_icon[6]; end
                case B_PLAY: g = video_is_playing(vh) ? g_icon[1] : g_icon[0]; end
                case B_STOP: g = g_icon[2]; end
                case B_FF:   g = g_icon[5]; end
                case B_NEXT: g = g_icon[3]; end
                case B_SUBS: g = g_icon[7]; end
                case B_AUDIO: g = g_icon[13]; end
                case B_VOL:  g = (muted || vol == 0) ? g_icon[9] : g_icon[8]; end
            end
            if (i <= B_NEXT) bx = SW / 2 - 250 + i * 100; else bx = SW - 290 + (i - B_SUBS) * 90; end
            put(S_BTN + i, g, bx, by, i == focus ? 80 : 62, a * (i == focus ? 255 : 200) / 255, -10);
            if (i == B_SUBS && sub_sel < 0) spr_alpha[S_BTN + i] = a * 110 / 255; end
            if (i == focus)
                put(S_FOCUS, g_ring, bx, by, 100, a, -5);
            end
        end

        // barra de progreso
        dur = vdur(); pos = vpos();
        pct = dur > 0 ? pos * 1000 / dur : 0;
        if (pct > 1000) pct = 1000; end
        put(S_BAR_BG, g_barbg, 60 + 580, SH - 135, 100, a, -8);
        spr_sizex[S_BAR_BG] = 1160 / 8 * 100; spr_sizey[S_BAR_BG] = 100;
        put(S_BAR_FG, g_white, 60 + pct * 1160 / 1000 / 2, SH - 135, 100, a, -9);
        spr_sizex[S_BAR_FG] = pct * 1160 / 1000 * 100 / 8 + 1; spr_sizey[S_BAR_FG] = 100;
        put(S_KNOB, g_knob, 60 + pct * 1160 / 1000, SH - 135, 100, a, -10);

        if (pos / 1000 != last_sec || dur != last_dur)
            if (dur > 0) s_time = fmt_time(pos) + " / " + fmt_time(dur); else s_time = fmt_time(pos) + "  (en directo)"; end
            last_sec = pos / 1000; last_dur = dur;
        end
        txt_want[txt_time] = 8589934336 + (a);
        txt_want[txt_title] = 8589934336 + (a);
    end
    if (toast_t > 0) txt_want[txt_toast] = 8589934336 + (toast_t > 30 ? 255 : toast_t * 255 / 30); end

    // subtitulos (por encima de los iconos cuando estos se ven)
    if (sub_sel >= 0 && vh)
        t = video_subtitle_text(vh);
        if (t != last_sub_raw)               // solo se reparte en lineas cuando cambia el subtitulo
            last_sub_raw = t;
            k = script_of(t);
            if (k != sf_cur) create_sub_texts(sub_font_id(k)); end
            sub_lines = 0;
            for (k = 0; k < 3; k++) s_sub[k] = ""; end
            while (t != "" && sub_lines < 3)
                p1 = find(t, chr(10));
                if (p1 < 0) s_sub[sub_lines] = t; t = ""; else s_sub[sub_lines] = substr(t, 0, p1); t = substr(t, p1 + 1); end
                sub_lines++;
            end
        end
        lines = sub_lines;
        // la ultima linea queda en la base; las anteriores encima
        by = SH - 40 - (a > 0 ? 110 : 0);
        for (k = 0; k < lines; k++)
            // linea k (de arriba a abajo) -> posicion
            write_move(txt_sub[k * 2],     ur(SW / 2 + 2), ur(by - (lines - 1 - k) * 56 + 2));
            write_move(txt_sub[k * 2 + 1], ur(SW / 2), ur(by - (lines - 1 - k) * 56));
            txt_want[txt_sub[k * 2]] = 4294967296 + 230;
            txt_want[txt_sub[k * 2 + 1]] = 8589934336 + 255;
        end
    end
end
