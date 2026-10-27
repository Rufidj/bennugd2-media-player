// ==========================================================================================================
//  receive.prg - recibir archivos desde otro ordenador. El reproductor abre una pagina web (motor: libmod_video) y desde el
//  navegador del PC o del movil se arrastran los archivos; se guardan en la carpeta elegida. En pantalla se ve la direccion
//  y un PIN (sin el PIN no se escribe nada). No se pisa ningun archivo: si ya existe se guarda como "nombre (2).ext".
// ==========================================================================================================
global
    int    ru_job;                       // 1 = esperando / recibiendo archivos
    string ru_folder = "", ru_pin = "", ru_addr = "";
end

function ru_begin(string folder)
private int port; string ip;
begin
    if (ru_job || folder == "") return 0; end
    if (tor_job || tor_playing) toast(tr("t_ru_busy")); return 0; end
    mkdir(folder);
    ru_pin = "" + rand(1000, 9999);
    if (getenv("MP_RU_PIN") != "") ru_pin = getenv("MP_RU_PIN"); end                     // solo pruebas
    port = upload_start(folder, 8080, ru_pin);
    if (port < 0)
        show_error(tr("s_receive"), tr("t_ru_fail") + ": " + upload_error()); return 0;
    end
    ip = upload_ip(); if (ip == "") ip = "?"; end
    ru_addr = "http://" + ip + ":" + port;
    ru_folder = folder; ru_job = 1;
    close_preview();
    prog_start(ru_addr + "    PIN " + ru_pin, 1);
    ov_btn = tr("h_stop"); ov_sub = tr("s_ru_wait");
end

function ru_end()
private int n;
begin
    n = upload_files();
    upload_stop();
    ru_job = 0; ov_sub = ""; ov_btn = "";
    prog_stop();
    toast(n + " " + tr("t_ru_done"));
    if (addon_mode == 0 && store_mode == 0 && cur_list == "" && ru_folder == cur_dir) read_dir(); end
end

// un paso por fotograma: se para con atras / circulo
function ru_step()
private int p, n;
begin
    if (ov_cancel_asked()) ru_end(); return 0; end
    p = upload_percent(); n = upload_files();
    if (p >= 0)
        ov_pct = p;
        ov_sub = fit_text(utf8_to_latin1(upload_current()), 560) + "   " + p + " %";
    else
        ov_pct = 0;
        ov_sub = n == 0 ? tr("s_ru_wait") : n + " " + tr("t_ru_done") + "   (" + fmt_size(upload_bytes()) + ")";
    end
end
