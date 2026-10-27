// ==========================================================================================================
//  imageviewer.prg - visor de imagenes y presentacion con transiciones.
//  Se entra desde el explorador abriendo una imagen (jpg, png, bmp, gif, tga...). Las imagenes de la carpeta
//  se recorren con izquierda/derecha; L1/R1 acercan y alejan; triangulo gira; START inicia la presentacion.
//  Una imagen se carga entera en una textura (el decodificador es el del motor: en la PS5 stb_image).
// ==========================================================================================================
const
    IMG_TR_FR = 36;                      // fotogramas que dura una transicion
    IMG_ZOOMS = 5;                       // niveles de zoom: 100, 150, 200, 300 y 400 %
end

global
    int    img_n;                        // imagenes de la carpeta
    int    img_ord[MAX_ENTRIES];         // numero de entrada, en el orden en que se recorren
    int    img_pos;                      // posicion de la que se ve dentro de img_ord
    int    img_g, img_w, img_h, img_rot; // la que se ve: textura, medidas y giro (cuartos de vuelta a la derecha)
    int    img_ng, img_pw, img_ph, img_prot, img_npos = -1;      // la siguiente, ya cargada (-1 = ninguna)
    int    img_nw, img_nh, img_nrot;                             // medidas de la ultima que se cargo
    int    img_og, img_ow, img_oh, img_orot, img_osc;            // la que sale durante una transicion y su zoom
    int    img_zoom, img_px, img_py;     // zoom (indice), desplazamiento
    int    img_slide;                    // 1 = presentacion en marcha
    int    img_t, img_tr_t, img_trk, img_dir, img_kb;            // fotogramas que lleva, progreso de la transicion, tipo, sentido, zoom lento activo
    int    img_ovt;                      // fotogramas sin tocar nada (el titulo y la ayuda se ocultan solos)
    int    img_trash[4], img_trash_n;    // texturas por liberar en el siguiente fotograma
    int    set_img_int = 1, set_img_tr = 3, set_img_shuf;        // presentacion: intervalo (indice), transicion y orden
    int    g_black;
    byte   img_hdr[65536]; int img_le;   // cabecera de un jpg (para leer la orientacion)
end

function int img_secs(int k)
begin
    switch (k)
        case 0: return 3; end
        case 1: return 5; end
        case 2: return 10; end
        case 3: return 15; end
        case 4: return 30; end
    end
    return 60;
end

function int img_zoomf(int k)
begin
    switch (k)
        case 1: return 150; end
        case 2: return 200; end
        case 3: return 300; end
        case 4: return 400; end
    end
    return 100;
end

function int is_image(string f)
private string e;
begin
    e = lcase(ext_of(f));
    return e == "jpg" || e == "jpeg" || e == "png" || e == "bmp" || e == "gif" || e == "tga" || e == "webp";
end

// ---------------------------------------------------------------- orientacion (EXIF): las fotos del movil se guardan "de lado" con una nota
function int img_rd16(int p)
begin
    if (img_le) return img_hdr[p] + img_hdr[p + 1] * 256; end
    return img_hdr[p] * 256 + img_hdr[p + 1];
end

function int img_rd32(int p)
begin
    if (img_le) return img_rd16(p) + img_rd16(p + 2) * 65536; end
    return img_rd16(p) * 65536 + img_rd16(p + 2);
end

// devuelve los cuartos de vuelta a la derecha que hay que girarla (0 si no hay nota o no es un jpg)
function int exif_rot(string path)
private int fh, n, i, m, sl, tiff, ifd, cnt, e, p, v;
begin
    if (lcase(ext_of(path)) != "jpg" && lcase(ext_of(path)) != "jpeg") return 0; end
    fh = fopen(path, O_READ);
    if (!fh) return 0; end
    n = fread(&img_hdr, 65536, fh);
    fclose(fh);
    if (n < 16 || img_hdr[0] != 255 || img_hdr[1] != 216) return 0; end
    i = 2;
    while (i + 12 < n)
        if (img_hdr[i] != 255) return 0; end
        m = img_hdr[i + 1];
        sl = img_hdr[i + 2] * 256 + img_hdr[i + 3];
        if (m == 218) return 0; end                                  // empiezan los datos de la imagen: ya no hay mas notas
        if (m == 225 && img_hdr[i + 4] == 69 && img_hdr[i + 5] == 120 && img_hdr[i + 6] == 105 && img_hdr[i + 7] == 102)       // "Exif"
            tiff = i + 10;
            img_le = img_hdr[tiff] == 73;                            // "II" = little endian
            ifd = tiff + img_rd32(tiff + 4);
            if (ifd + 2 >= n) return 0; end
            cnt = img_rd16(ifd);
            for (e = 0; e < cnt; e++)
                p = ifd + 2 + e * 12;
                if (p + 12 > n) return 0; end
                if (img_rd16(p) == 274)                              // etiqueta Orientation
                    v = img_rd16(p + 8);
                    if (v == 3) return 2; end
                    if (v == 6) return 1; end
                    if (v == 8) return 3; end
                    return 0;
                end
            end
            return 0;
        end
        i += 2 + sl;
    end
    return 0;
end

// ---------------------------------------------------------------- carga
function img_free(int g)
begin
    if (g > 0 && img_trash_n < 4) img_trash[img_trash_n] = g; img_trash_n++; end
end

function img_empty_trash()
private int i;
begin
    for (i = 0; i < img_trash_n; i++) map_unload(0, img_trash[i]); end
    img_trash_n = 0;
end

// textura de la imagen que esta en la posicion pos (0 si no se puede abrir)
function int img_load(int pos)
private string path; int g;
begin
    path = join_path(cur_dir, entries[img_ord[pos]]);
    g = map_load(path);
    if (g <= 0) return 0; end
    img_nw = graphic_info(0, g, G_WIDTH); img_nh = graphic_info(0, g, G_HEIGHT);
    img_nrot = exif_rot(path);
    return g;
end

// llena img_ord con las imagenes de la carpeta (y las baraja si toca) y devuelve en que posicion esta la entrada first
function int img_collect(int first)
private int i, j, k, t, at;
begin
    img_n = 0; at = 0;
    for (i = 0; i < n_entries; i++)
        if (entry_dir[i] == K_FILE && is_image(entries[i])) img_ord[img_n] = i; if (i == first) at = img_n; end img_n++; end
    end
    if (set_img_shuf && img_n > 1)                                     // se baraja dejando la que se abrio la primera
        for (i = img_n - 1; i > 0; i--)
            j = rand(0, i); t = img_ord[i]; img_ord[i] = img_ord[j]; img_ord[j] = t;
        end
        for (i = 0; i < img_n; i++) if (img_ord[i] == first) k = i; end end
        t = img_ord[0]; img_ord[0] = img_ord[k]; img_ord[k] = t;
        at = 0;
    end
    return at;
end

function open_image(int first)
begin
    close_preview();
    img_pos = img_collect(first);
    img_g = img_load(img_pos);
    if (!img_g) toast(tr("t_img_fail")); return 0; end
    img_w = img_nw; img_h = img_nh; img_rot = img_nrot;
    img_npos = -1; img_ng = 0; img_og = 0; img_tr_t = 0; img_slide = 0; img_zoom = 0; img_px = 0; img_py = 0; img_t = 0; img_ovt = 0; img_kb = 0;
    s_title = utf8_to_latin1(entries[img_ord[img_pos]]);
    state = ST_IMAGE;
end

function close_image()
private int sel_back;
begin
    if (img_tr_t > 0) img_free(img_og); img_og = 0; img_tr_t = 0; end
    if (img_ng > 0) img_free(img_ng); img_ng = 0; end
    img_free(img_g); img_g = 0; img_npos = -1;
    sel_back = img_ord[img_pos];
    img_slide = 0;
    state = ST_BROWSE; lbl_ver = -1; pv_idx = -1;
    sel = sel_back; if (sel >= ROWS) top_row = sel - ROWS + 1; else top_row = 0; end
end

// ---------------------------------------------------------------- cambiar de imagen
// dir = +1 siguiente, -1 anterior. auto = 1 cuando lo hace la presentacion
function int img_go(int dir, int auto)
private int pos, g, w, h, r, tries, k;
begin
    if (img_n < 2) return 0; end
    if (img_tr_t > 0) img_free(img_og); img_og = 0; img_tr_t = 0; end          // si habia una transicion en marcha se da por terminada
    pos = img_pos; g = 0;
    for (tries = 0; tries < img_n; tries++)
        pos = (pos + dir + img_n) % img_n;
        if (img_npos == pos && img_ng > 0)                                      // ya estaba cargada
            g = img_ng; w = img_pw; h = img_ph; r = img_prot; img_ng = 0; img_npos = -1;
            break;
        end
        if (img_ng > 0) img_free(img_ng); img_ng = 0; img_npos = -1; end
        g = img_load(pos);
        if (g > 0) w = img_nw; h = img_nh; r = img_nrot; break; end
        if (!auto) toast(tr("t_img_fail")); return 0; end                       // (en la presentacion se salta la que no se puede abrir)
    end
    if (g <= 0) return 0; end
    k = set_img_tr;
    if (k == 4) k = rand(1, 3); end
    if (k > 0)                                                                  // la que se veia pasa a ser la que sale
        img_og = img_g; img_ow = img_w; img_oh = img_h; img_orot = img_rot;
        img_osc = 100 + (img_kb ? img_ken(img_t) : 0);
        img_trk = k; img_tr_t = 1; img_dir = dir;
    else
        img_free(img_g);
    end
    img_g = g; img_w = w; img_h = h; img_rot = r; img_pos = pos;
    img_zoom = 0; img_px = 0; img_py = 0; img_t = 0;
    img_kb = img_slide && (k == 3);
    s_title = utf8_to_latin1(entries[img_ord[img_pos]]);
    return 1;
end

// zoom lento de la presentacion: de 100 a 110 % durante el tiempo que se ve la imagen
function int img_ken(int t)
private int total;
begin
    total = img_secs(set_img_int) * 60;
    if (t > total) t = total; end
    return 10 * t / total;
end

// ---------------------------------------------------------------- dibujar
// pone una imagen (en la casilla slot) ajustada a la pantalla; sc = zoom en %, cx/cy el centro
function img_put(int slot, int g, int w, int h, int rot, int cx, int cy, int sc, int a, int zz)
private int fw, fh, k;
begin
    fw = (rot % 2) ? h : w; fh = (rot % 2) ? w : h;
    k = SW * 100 / fw; if (SH * 100 / fh < k) k = SH * 100 / fh; end
    k = k * sc / 100;
    put(slot, g, cx, cy, k, a, zz);
    spr_angle[slot] = ((4 - rot) % 4) * 90000;
end

function draw_image()
private int p, cx, cy, sc, fw, fh, k, mx, my, a;
begin
    put(S_IBG, g_black, SW / 2, SH / 2, 100, 255, 14);
    spr_sizex[S_IBG] = SW / 8 * 100; spr_sizey[S_IBG] = SH / 8 * 100;
    sc = img_zoomf(img_zoom) * (100 + (img_kb ? img_ken(img_t) : 0)) / 100;
    cx = SW / 2 - img_px; cy = SH / 2 - img_py;
    if (img_tr_t > 0 && img_og > 0)
        p = img_tr_t * 1000 / IMG_TR_FR; if (p > 1000) p = 1000; end
        switch (img_trk)
            case 2:                                                        // deslizar: una sale por un lado y la otra entra por el otro
                img_put(S_IMG2, img_og, img_ow, img_oh, img_orot, SW / 2 - img_dir * SW * p / 1000, SH / 2, img_osc, 255, 12);
                img_put(S_IMG, img_g, img_w, img_h, img_rot, SW / 2 + img_dir * SW * (1000 - p) / 1000, SH / 2, sc, 255, 10);
            end
            default:                                                       // fundido (y zoom: la nueva ademas llega un poco ampliada)
                img_put(S_IMG2, img_og, img_ow, img_oh, img_orot, SW / 2, SH / 2, img_osc + (img_kb ? 10 * img_tr_t / (img_secs(set_img_int) * 60) : 0), 255, 12);
                img_put(S_IMG, img_g, img_w, img_h, img_rot, SW / 2, SH / 2, sc * (img_trk == 3 ? 100 + 6 * (1000 - p) / 1000 : 100) / 100, p * 255 / 1000, 10);
            end
        end
    elseif (img_g > 0)
        img_put(S_IMG, img_g, img_w, img_h, img_rot, cx, cy, sc, 255, 10);
    end

    // titulo, contador y ayuda: se ocultan solos
    a = img_ovt < HIDE_AFTER ? 255 : 0;
    if (img_ovt >= HIDE_AFTER && img_ovt < HIDE_AFTER + 20) a = 255 - (img_ovt - HIDE_AFTER) * 255 / 20; end
    if (a > 0 || modal == M_MENU)
        if (a == 0) a = 255; end
        put(S_SHADE_TOP, g_shade_top, SW / 2, 64, 100, a * 2 / 3, 5);
        spr_sizex[S_SHADE_TOP] = SW / 64 * 100; spr_sizey[S_SHADE_TOP] = 100;
        put(S_SHADE_BOT, g_shade, SW / 2, SH - 128, 100, a, 5);
        spr_sizex[S_SHADE_BOT] = SW / 64 * 100; spr_sizey[S_SHADE_BOT] = 100;
        s_time = (img_pos + 1) + " / " + img_n + (img_slide ? "    " + tr("s_slideshow") + " " + img_secs(set_img_int) + " s" : "") + (img_zoom > 0 ? "    " + img_zoomf(img_zoom) + " %" : "");
        txt_want[txt_title] = 8589934336 + (a);
        txt_want[txt_time] = 8589934336 + (a);
        if (modal != M_MENU)
            if (skin) hint_set(6); else s_hint = tr("h_image"); txt_want[txt_hint] = 8589934336 + (a * 150 / 255); end
            if (skin) for (k = 0; k < hint_n; k++) txt_want[txt_h[k]] = 8589934336 + (a * 210 / 255); end end
        end
    end
    if (toast_t > 0) toast_t--; end
    if (toast_t > 0) txt_want[txt_toast] = 8589934336 + (255); end
end

// ---------------------------------------------------------------- menu y datos
function open_image_menu(int keep)
begin
    menu_clear();
    menu_add(img_slide ? tr("m_img_stop") : tr("m_img_start"), MA_IMG_SLIDE);
    menu_add(tr("m_img_int") + img_secs(set_img_int) + " s", MA_IMG_INT);
    menu_add(tr("m_img_tr") + (set_img_tr == 0 ? tr("s_tr_none") : (set_img_tr == 1 ? tr("s_tr_fade") : (set_img_tr == 2 ? tr("s_tr_slide") : (set_img_tr == 3 ? tr("s_tr_zoom") : tr("s_tr_random"))))), MA_IMG_TR);
    menu_add(tr("m_img_order") + (set_img_shuf ? tr("s_order_random") : tr("s_order_normal")), MA_IMG_SHUF);
    menu_add(tr("m_img_rot"), MA_IMG_ROT);
    menu_add(tr("m_img_info"), MA_IMG_INFO);
    menu_add(tr("m_img_close"), MA_IMG_CLOSE);
    menu_show(tr("mt_image"));
    if (keep >= 0) menu_sel = keep; end
end

function img_info()
private string path; int fh, sz;
begin
    path = join_path(cur_dir, entries[img_ord[img_pos]]);
    fh = fopen(path, O_READ); sz = 0;
    if (fh) sz = flength(fh); fclose(fh); end
    menu_clear();
    fo_line(tr("p_name") + entries[img_ord[img_pos]]);
    menu_add(tail_fit(utf8_to_latin1(tr("p_path") + cur_dir), 780), MA_CANCEL);
    fo_line(tr("s_res") + img_w + "x" + img_h + "  (" + ((img_w * img_h + 500000) / 1000000) + "." + (((img_w * img_h + 50000) / 100000) % 10) + " MP)");
    fo_line(tr("s_size") + fo_bytes(sz));
    fo_line(img_pos + 1 + " / " + img_n);
    if (img_rot != 0) fo_line(tr("p_orient") + (img_rot * 90) + "°"); end
    menu_add(tr("m_back"), MA_CANCEL);
    menu_sel = menu_n - 1;
    menu_show(tr("m_img_info"));
end

// ---------------------------------------------------------------- un paso por fotograma
function update_image()
private int mx, my, zf, k, fw, fh, kfit, stp;
begin
    img_empty_trash();
    img_t++;
    if (any_input) img_ovt = 0; else img_ovt++; end

    if (act_press[A_BACK])
        if (img_slide) img_slide = 0; img_kb = 0; toast(tr("t_img_slide_off")); else close_image(); end
        return 0;
    end
    if (ptr_wheel != 0 && img_zoom == 0) img_go(ptr_wheel > 0 ? -1 : 1, 0); return 0; end
    if (act_press[A_OK] || act_press[A_MUTE] || ptr_click)
        if (tap() && touch_x < SW / 4) img_go(-1, 0); return 0; end
        if (tap() && touch_x > SW * 3 / 4) img_go(1, 0); return 0; end
        open_image_menu(0); return 0;
    end
    if (act_press[A_PAUSE])
        img_slide = !img_slide; img_t = 0;
        if (img_slide) toast(tr("t_img_slide_on")); img_ovt = HIDE_AFTER - 80; else toast(tr("t_img_slide_off")); end
        img_kb = img_slide && set_img_tr == 3;
    end
    if (act_press[A_SUBS]) img_rot = (img_rot + 1) % 4; img_px = 0; img_py = 0; end
    if (act_press[A_SEEKF] && img_zoom < IMG_ZOOMS - 1) img_zoom++; end
    if (act_press[A_SEEKB] && img_zoom > 0) img_zoom--; if (img_zoom == 0) img_px = 0; img_py = 0; end end

    if (img_zoom == 0)
        if (act_press[A_RIGHT]) img_go(1, 0); end
        if (act_press[A_LEFT])  img_go(-1, 0); end
    else
        // con zoom la cruceta recorre la imagen
        stp = 16;
        if (act_hold[A_RIGHT]) img_px += stp; end
        if (act_hold[A_LEFT])  img_px -= stp; end
        if (act_hold[A_DOWN])  img_py += stp; end
        if (act_hold[A_UP])    img_py -= stp; end
        fw = (img_rot % 2) ? img_h : img_w; fh = (img_rot % 2) ? img_w : img_h;
        kfit = SW * 100 / fw; if (SH * 100 / fh < kfit) kfit = SH * 100 / fh; end
        zf = img_zoomf(img_zoom);
        mx = fw * kfit / 100 * zf / 100 - SW; if (mx < 0) mx = 0; end
        my = fh * kfit / 100 * zf / 100 - SH; if (my < 0) my = 0; end
        if (img_px > mx / 2) img_px = mx / 2; end  if (img_px < -mx / 2) img_px = -mx / 2; end
        if (img_py > my / 2) img_py = my / 2; end  if (img_py < -my / 2) img_py = -my / 2; end
    end

    // transicion en marcha
    if (img_tr_t > 0)
        img_tr_t++;
        if (img_tr_t >= IMG_TR_FR) img_free(img_og); img_og = 0; img_tr_t = 0; end
    end
    // la presentacion pasa a la siguiente al cumplirse el tiempo
    if (img_slide && img_tr_t == 0 && img_zoom == 0 && img_t >= img_secs(set_img_int) * 60) img_go(1, 1); end
    // mientras se mira una, se va cargando la siguiente para que el cambio sea inmediato
    if (img_t == 45 && img_ng == 0 && img_n > 1 && img_tr_t == 0)
        img_npos = (img_pos + 1) % img_n;
        img_ng = img_load(img_npos);
        if (img_ng > 0) img_pw = img_nw; img_ph = img_nh; img_prot = img_nrot; else img_npos = -1; end
    end
    if (toast_t > 0) toast_t--; end
end
