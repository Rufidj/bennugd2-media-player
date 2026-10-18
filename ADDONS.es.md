# Crear addons para el BennuGD2 Media Player

Un addon es un archivo de texto llamado `main.addon`, escrito en un pequeño lenguaje en inglés sencillo que entiende el propio reproductor: **sin compilador, sin librerías, sin herramientas de programación**. Lo editas con cualquier editor de texto, lo copias a la consola y listo.

Los addons permiten mostrar contenido de otros sitios: un servidor Plex, radios de internet, un archivo de vídeos... El addon descarga datos (normalmente JSON) de una API web y le dice al reproductor qué carpetas y elementos reproducibles mostrar.

## Instalación

Cada addon va en su propia carpeta:

```
/data/mediaplayer/addons/mi-addon/main.addon      (consola, escribible)
<carpeta del reproductor>/addons/mi-addon/main.addon   (incluidos con el reproductor)
```

Opcional: un `logo.png` (por ejemplo 480x270) junto a `main.addon` se muestra como vista previa al seleccionar el addon.

Abre **Addons** en la pantalla de inicio. Selecciona un addon para explorarlo. Pulsa **CUADRADO** sobre un addon para sus **ajustes**. **CÍRCULO** vuelve atrás o cancela una descarga en curso.

## Primer addon

```
addon "Hola radio"
id hola-radio
version 1.0
author "Yo"
description "Una emisora."

page home:
    show radio "SomaFM Groove Salad" playing "https://ice1.somafm.com/groovesalad-128-mp3" info "Ritmos suaves"
```

La primera página de todo addon es `home`.

## Estructura

La sangría (4 espacios) define los bloques, como en Python. `#` inicia un comentario.

| Línea | Significado |
|---|---|
| `addon "Nombre"` | nombre visible (obligatorio) |
| `id nombre` | id único, usado para el archivo de ajustes |
| `version`, `author`, `description` | se muestran en la lista de Addons |
| `setting ...` | un ajuste del usuario (ver abajo) |
| `page NOMBRE:` / `page NOMBRE with a, b:` | una pantalla de elementos; `with` lista los argumentos que recibe |
| `define f(a, b):` | función reutilizable (hasta 6 argumentos) |

## Ajustes (y secretos)

```
setting server is text, label "Dirección del servidor", default "http://192.168.1.50:32400"
setting token  is secret text, label "Token de Plex"
setting hd     is yes or no, label "Preferir HD", default yes
setting count  is number, label "Elementos", default 50
setting mode   is choice, label "Calidad", choices "128 mp3", "64 aac"
```

Cada ajuste es una variable con ese nombre dentro del addon. **Los secretos nunca van en el script**: cada usuario escribe los suyos en el menú de ajustes (CUADRADO). Se guardan en `<store>/addons_data/<id>.cfg` y se muestran como `*****`.

## Páginas y elementos

Una página se ejecuta de arriba abajo y cada `show` añade un elemento.

```
show folder TÍTULO opening PÁGINA [with nombre is valor ...]
show video  TÍTULO playing URL
show audio  TÍTULO playing URL
show radio  TÍTULO playing URL
```

Cláusulas opcionales en cualquier `show`: `logo URL`, `info TEXTO`, `year N`, `duration SEGUNDOS`, `subtitles URL`.

```
page home:
    show folder "Películas" opening movies with genre is "all" with title is "Películas"

page movies with genre, title:
    show video "Big Buck Bunny" playing "http://example.com/bbb.mp4" year 2008 duration 596
```

Los argumentos viajan como JSON: números, texto, listas y registros se conservan.

## Valores

Números `3`, `2.5`; texto `"hola {nombre}"` (lo que va entre `{}` se evalúa; también valen comillas simples, útiles dentro de `{}`); listas `[1, 2, 3]` (**numeradas desde 1**); registros `{title: "x", year: 2000}`; `true`/`false`; `nothing`. Campos: `item.title`, `lista[1]`, `item["cualquier clave"]`.

## Instrucciones

```
set x to 5                     add 1 to x          add item to mi_lista
clear mi_lista
if x is greater than 3:        otherwise if x is 3:        otherwise:
for each item in lista [limit 20]:     (define index; en registros también key)
while x is less than 10:
repeat 5 times:                (define counter)
stop                           (termina la página)   skip (siguiente vuelta)   exit loop
give back VALOR                (devuelve valor en una función)
fail "mensaje"                 (muestra un error y termina)
try:  ...   on error:  ...     (el texto del error está en `error`)
message "Cargando..."          clear message        wait 2 seconds
ask "Pregunta" into respuesta [default "x"] [secret]
save NOMBRE as VALOR           (guarda un valor en el archivo de ajustes)
log "texto"                    (salida de depuración)
```

## Condiciones

`is`, `is not`, `is greater than`, `is less than`, `is at least`, `is at most`, `is empty`, `is nothing`, `contains`, `starts with`, `ends with`, combinadas con `and`, `or`, `not`. Aritmética: `+ - * / %`.

## Descargar datos

```
fetch json from URL                     # el resultado queda en `result`
fetch json from URL into datos
fetch text from URL
fetch json from URL with header "Accept" is "application/json"
fetch json from URL with method "POST" with body json({a: 1})
```

Si el servidor falla (o responde 401/403/404) el reproductor muestra un error claro con la línea del addon. Usa `try`/`on error` para gestionarlo tú.

## Funciones incluidas

Texto: `length upper lower trim replace shorten slice split join text number url_encode base64 index_of`
Mates: `round floor ceil abs min max random`
Listas: `first last reverse range keys has sort filter pick join`
Otras: `json parse_json default now uuid format_time join_url`

`default(valor, alternativa)` sirve para campos que pueden faltar. `sort(lista, "campo")` ordena registros.

## Login por código (ejemplo)

Mira `addons/demo/main.addon` en el código fuente: usa `ask`, `message`, `wait` y `save` para mostrar un código, consultar un servidor y guardar el token que devuelve.

## Límites y seguridad

- `fetch` funciona con `http://` y `https://` (se siguen las redirecciones; el HTTPS lo hace el motor, el addon no gestiona certificados).
- Cabeceras al reproducir: añade `with header "Nombre" is valor` a un `show video/audio/radio`. El reproductor descarga la lista `.m3u8` con esas cabeceras y la reproduce desde un archivo local, así que sirve para listas HLS cuyos segmentos no piden cabeceras (como el catálogo gratuito de Plex). Para archivos normales, pon la clave en la URL.
- Sin XML (solo JSON y texto). Funciones de hasta 6 argumentos. Máximo 3000 elementos por página y 4.000.000 de pasos (corta bucles infinitos).
- Una IP inalcanzable (sin ninguna respuesta) puede bloquear hasta 15 s (http) o el timeout del sistema; revisa la dirección.
- Un addon puede contactar con cualquier servidor HTTP. **Instala solo addons de confianza.** No se admite contenido con DRM.

## Depuración

Los errores muestran el archivo y la línea. Usa `log "x vale {x}"` para imprimir valores en el log del reproductor.
