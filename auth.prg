// ==========================================================================================================
//  auth.prg - cuentas de usuario de las listas.
//  Una lista de TV/radio puede pedir usuario y contraseña (las de pago). Los datos se guardan junto a la
//  lista, en <almacen>/listas/<lista>.auth, y se usan al bajarla y al reproducir sus canales.
//  Dos modos:
//    basic -> el usuario y la clave van en la URL (http://user:clave@servidor/...)
//    form  -> se hace un POST a la dirección de login y el token que devuelve se usa como cabecera o
//             como parámetro de la URL.
//  AVISO: el usuario y la clave se guardan en texto plano en el almacén del reproductor.
// ==========================================================================================================
global
    string au_user = "", au_pass = "";
    string au_mode = "";              // "basic", "form" o "xtream"
    string au_server = "";            // servidor del panel (modo xtream)
    string au_login_url = "";         // dirección del endpoint de login
    string au_ufield = "username", au_pfield = "password";
    string au_tfield = "token", au_hdr = "Authorization", au_token = "";
    int    au_json = 0, au_query = 0; // json = login en JSON; query = el token va en la URL
    string au_list = "";              // fichero de la lista a la que pertenecen estos datos
    int    au_has = 0;                // 1 = hay credenciales cargadas
    int    au_ask_row = 0;            // fila de la tienda pendiente de pedir la cuenta
    string au_ask_file = "";          // fichero de lista donde se guardan las credenciales
    string au_ask_spec = "";          // especificación de la cuenta de esa lista
    string au_ask_name = "";          // nombre de la lista (para abrir una cuenta Xtream)
    int    au_ask_next = 0;           // 1 = al terminar, seguir con la instalación de la tienda
    string acc_name[16]; int acc_n = 0, acc_sel = 0;   // menú de cuentas

// el fichero de credenciales va junto a la lista: "TV España.m3u" -> "TV España.auth"
function string au_sidecar(string listfile)
private int p;
begin
    p = len(listfile);
    if (p > 4 && lcase(substr(listfile, p - 4, 4)) == ".m3u") return substr(listfile, 0, p - 4) + ".auth"; end
    if (p > 5 && lcase(substr(listfile, p - 5, 5)) == ".m3u8") return substr(listfile, 0, p - 5) + ".auth"; end
    return listfile + ".auth";
end

// valor de "clave=valor" dentro de una especificación "a=1;b=2"
function string au_spec_get(string spec, string key)
private int p, q; string part, k, v;
begin
    while (spec != "")
        p = find(spec, ";");
        if (p < 0) part = spec; spec = ""; else part = substr(spec, 0, p); spec = substr(spec, p + 1); end
        q = find(part, "=");
        if (q > 0)
            k = lcase(substr(part, 0, q)); v = substr(part, q + 1);
            if (k == key) return v; end
        end
    end
    return "";
end

// un valor de la especificación, o el valor por defecto si no está
function string au_ask_value(string spec, string key, string def)
private string v;
begin
    v = au_spec_get(spec, key);
    if (v == "") return def; end
    return v;
end

// deja lista la cuenta a partir de la especificación del catálogo
//   mode=basic|form  login=<dirección>  u=<campo>  p=<campo>  t=<campo del token>  h=<cabecera>
//   json=1  query=1
function int au_set_spec(string spec)
begin
    au_mode = lcase(au_ask_value(spec, "mode", "basic"));
    au_login_url = au_ask_value(spec, "login", "");
    au_server = au_ask_value(spec, "server", "");
    au_ufield = au_ask_value(spec, "u", "username");
    au_pfield = au_ask_value(spec, "p", "password");
    au_tfield = au_ask_value(spec, "t", "token");
    au_hdr = au_ask_value(spec, "h", "Authorization");
    au_json = (au_ask_value(spec, "json", "") != "") ? 1 : 0;
    au_query = (au_ask_value(spec, "query", "") != "") ? 1 : 0;
    return 1;
end

// escapa un texto para poder ponerlo en una URL
function string au_esc(string s)
private int i, c; string r, h;
begin
    h = "0123456789ABCDEF";
    for (i = 0; i < len(s); i++)
        c = asc(substr(s, i, 1));
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 46 || c == 95 || c == 126)
            r += substr(s, i, 1);
        else
            r += "%" + substr(h, c >> 4, 1) + substr(h, c & 15, 1);
        end
    end
    return r;
end

// mete el token en la URL (login con formulario); la cuenta basic va en la cabecera
function string au_apply(string url)
private int p;
begin
    if (au_mode == "form" && au_query && au_token != "")
        p = find(url, "?");
        if (p < 0) return url + "?" + au_tfield + "=" + au_esc(au_token); end
        return substr(url, 0, p) + "&" + au_tfield + "=" + au_esc(au_token);
    end
    return url;
end

// cabeceras para las peticiones (la cuenta de la lista)
function string au_headers()
begin
    if (au_mode == "basic" && au_user != "")
        return "Authorization: Basic " + ad_b64(au_user + ":" + au_pass) + chr(13) + chr(10);
    end
    if (au_mode == "form" && !au_query && au_token != "") return au_hdr + ": " + au_token + chr(13) + chr(10); end
    return "";
end

// carga las credenciales guardadas de una lista
function int au_load(string listfile)
private int fh, p; string ln, k, v;
begin
    au_list = listfile;
    au_user = ""; au_pass = ""; au_token = ""; au_mode = ""; au_login_url = ""; au_server = "";
    au_ufield = "username"; au_pfield = "password"; au_tfield = "token"; au_hdr = "Authorization";
    au_json = 0; au_query = 0; au_has = 0;
    fh = fopen(au_sidecar(listfile), O_READ);
    if (!fh) return 0; end
    while (!feof(fh))
        ln = fgets(fh);
        p = find(ln, "=");
        if (p > 0)
            k = lcase(substr(ln, 0, p)); v = substr(ln, p + 1);
            if (k == "user") au_user = v; end
            if (k == "pass") au_pass = v; end
            if (k == "token") au_token = v; end
            if (k == "mode") au_mode = lcase(v); end
            if (k == "server") au_server = v; end
            if (k == "login") au_login_url = v; end
            if (k == "ufield") au_ufield = v; end
            if (k == "pfield") au_pfield = v; end
            if (k == "tfield") au_tfield = v; end
            if (k == "hdr") au_hdr = v; end
            if (k == "json") au_json = atoi(v); end
            if (k == "query") au_query = atoi(v); end
        end
    end
    fclose(fh);
    if (au_user != "" || au_token != "") au_has = 1; end
    return au_has;
end

// guarda las credenciales de una lista
function int au_store(string listfile)
private int fh;
begin
    fh = fopen(au_sidecar(listfile), O_WRITE);
    if (!fh) return 0; end
    fputs(fh, "user=" + au_user + chr(10));
    fputs(fh, "pass=" + au_pass + chr(10));
    fputs(fh, "mode=" + au_mode + chr(10));
    if (au_server != "") fputs(fh, "server=" + au_server + chr(10)); end
    if (au_login_url != "") fputs(fh, "login=" + au_login_url + chr(10)); end
    if (au_ufield != "username") fputs(fh, "ufield=" + au_ufield + chr(10)); end
    if (au_pfield != "password") fputs(fh, "pfield=" + au_pfield + chr(10)); end
    if (au_tfield != "token") fputs(fh, "tfield=" + au_tfield + chr(10)); end
    if (au_hdr != "Authorization") fputs(fh, "hdr=" + au_hdr + chr(10)); end
    if (au_json) fputs(fh, "json=1" + chr(10)); end
    if (au_query) fputs(fh, "query=1" + chr(10)); end
    if (au_token != "") fputs(fh, "token=" + au_token + chr(10)); end
    fclose(fh);
    au_has = 1;
    return 1;
end

// borra las credenciales de una lista
function int au_clear(string listfile)
begin
    if (fexists(au_sidecar(listfile))) fremove(au_sidecar(listfile)); end
    au_user = ""; au_pass = ""; au_token = ""; au_has = 0;
    return 1;
end

// busca un texto en un JSON: {"token":"abc"} -> "abc"
// Quita las barras de escape de un texto JSON (\" \/ \\ \n ...)
function string json_unescape(string s)
private string r = "", ch; int i;
begin
    for (i = 0; i < len(s); i++)
        ch = substr(s, i, 1);
        if (ch == "\\" && i + 1 < len(s))
            i++;
            ch = substr(s, i, 1);
            if (ch == "n") r += chr(10);
            elseif (ch == "t") r += chr(9);
            elseif (ch == "r") r += chr(13);
            elseif (ch == "u") i += 4; r += "?";
            else r += ch; end
        else
            r += ch;
        end
    end
    return r;
end

function string au_json_str(string body, string field)
private int p, q; string key;
begin
    key = chr(34) + field + chr(34);
    p = find(body, key);
    if (p < 0) return ""; end
    p += len(key);
    while (p < len(body))
        if (substr(body, p, 1) != " " && substr(body, p, 1) != chr(9) && substr(body, p, 1) != chr(10) && substr(body, p, 1) != chr(13)) break; end
        p++;
    end
    if (substr(body, p, 1) != ":") return ""; end
    p++;
    while (p < len(body) && (substr(body, p, 1) == " " || substr(body, p, 1) == chr(9))) p++; end
    if (substr(body, p, 1) != chr(34)) return ""; end
    p++; q = p;
    while (q < len(body) && substr(body, q, 1) != chr(34)) q++; end
    return json_unescape(substr(body, p, q - p));
end

// deja la cuenta guardada y hace el login si la lista lo necesita
//  1 = todo bien, 0 = no se pudo guardar, -1 = el login falló
function int au_finish()
begin
    if (au_ask_file == "") return 0; end
    if (!au_store(au_ask_file)) return 0; end
    if (au_mode == "form")
        if (!au_login()) return -1; end
        au_store(au_ask_file);                      // se guarda también el token
    end
    return 1;
end

// login con formulario: manda el usuario y la clave y guarda el token que devuelva
function int au_login()
private string body, hdr, data; int st, n;
begin
    if (au_login_url == "") return 0; end
    if (au_json)
        data = chr(34) + au_ufield + chr(34) + ":" + chr(34) + au_esc(au_user) + chr(34) + "," + chr(34) + au_pfield + chr(34) + ":" + chr(34) + au_esc(au_pass) + chr(34);
        hdr = "Content-Type: application/json" + chr(13) + chr(10);
    else
        data = au_ufield + "=" + au_esc(au_user) + "&" + au_pfield + "=" + au_esc(au_pass);
        hdr = "Content-Type: application/x-www-form-urlencoded" + chr(13) + chr(10);
    end
    st = http_fetch(au_login_url, hdr, "POST", data);
    if (st != 200) return 0; end
    n = http_length();
    if (n <= 0) return 0; end
    if (n >= HTTP_MAX) n = HTTP_MAX - 1; end
    body = ad_buf_str(0, http_read(&ad_buf[0], n));
    au_token = au_json_str(body, au_tfield);
    if (au_token == "") return 0; end
    return 1;
end

// ---- menú de cuentas ----------------------------------------------------
function open_accounts_menu()
private int dh, i; string nm;
begin
    acc_n = 0;
    dh = diropen(join_path(lists_dir, "*.auth"));
    if (dh)
        nm = dirread(dh);
        while (nm != "" && acc_n < 8)
            if (len(nm) > 5 && substr(nm, len(nm) - 5, 5) == ".auth")
                acc_name[acc_n] = substr(nm, 0, len(nm) - 5); acc_n++;
            end
            nm = dirread(dh);
        end
        dirclose(dh);
    end
    menu_clear();
    if (acc_n == 0)
        menu_add(tr("m_acc_empty"), MA_CANCEL);
    else
        for (i = 0; i < acc_n; i++) menu_add(cut_text(utf8_to_latin1(acc_name[i]), 26), MA_ACC_PICK + i); end
    end
    menu_add(tr("m_acc_new"), MA_ACC_NEW);
    menu_add(tr("m_back"), MA_CANCEL);
    menu_show(tr("mt_accounts"));
end

// menú de una cuenta: cambiarla o borrarla
function open_account_menu(int i)
begin
    if (i < 0 || i >= acc_n) return 0; end
    acc_sel = i;
    menu_clear();
    au_load(join_path(lists_dir, acc_name[i] + ".m3u"));
    if (au_mode == "xtream") menu_add(tr("m_acc_open"), MA_ACC_OPEN); end
    menu_add(tr("m_acc_edit"), MA_ACC_EDIT);
    menu_add(tr("m_acc_del"), MA_ACC_DEL);
    menu_add(tr("m_back"), MA_CANCEL);
    menu_show(cut_text(utf8_to_latin1(acc_name[i]), 26));
end

// valor de prueba (MP_AUTH_USER / MP_AUTH_PASS) o el de verdad
function string au_test_val(string env, string def)
begin
    if (getenv(env) != "") return getenv(env); end
    return def;
end

// olvida la cuenta cargada (al salir de una lista)
function int au_reset()
begin
    au_user = ""; au_pass = ""; au_token = ""; au_mode = ""; au_login_url = "";
    au_has = 0; au_list = "";
    return 1;
end

// prepara el tecleo para cambiar la cuenta de una lista
function au_ask_account(string listfile)
begin
    au_ask_file = listfile; au_ask_next = 0;
    au_load(listfile);
    if (au_mode == "") au_mode = "basic"; end
    kb_open(tr("k_auth_user"), au_test_val("MP_AUTH_USER", au_user), KB_AUTH_USER);
    return 1;
end
