# Crear aspectos (skins)

Un aspecto es una **carpeta** con un `skin.cfg` y sus imágenes. No hace falta programar nada: se hace en un PC con cualquier editor de imágenes y de texto, y se añade a la app (PC, PS5, Android).

Los 6 aspectos de fábrica (`res/skins/*`) usan exactamente este formato: son buenos ejemplos para copiar.

## Empezar

1. Copia la carpeta `skin_template` con otro nombre (por ejemplo `mi-aspecto`).
2. Edita `skin.cfg` y cambia las imágenes.
3. Cópiala a la carpeta de aspectos y aparecerá en **Ajustes → Aspecto**:
   - **PC:** `skins/mi-aspecto/` junto al reproductor, o `<carpeta de datos>/skins/mi-aspecto/`.
   - **PS5:** `/data/mediaplayer/skins/mi-aspecto/` (por FTP).
   - **Android:** la carpeta de datos de la app (`skins/mi-aspecto/`).
4. En PC, **F5** vuelve a leer el aspecto sin reiniciar: edita, pulsa F5 y mira.

También se pueden instalar desde una dirección web: sube la carpeta a cualquier servidor y usa **Ajustes → Instalar aspecto desde una URL** con la dirección de la carpeta (la que contiene `skin.cfg`).

## skin.cfg

Líneas `clave=valor`. Las que empiezan por `#` son comentarios (también se admite `# comentario` al final de una línea).

| Clave | Qué hace |
|---|---|
| `name` | Nombre que se muestra en Ajustes. |
| `font` | Fuente `.ttf`/`.otf` de la carpeta. Solo se usa en idiomas latinos (el ruso, japonés, chino y coreano siguen con su fuente). Si no se puede abrir se usa la normal. Comprueba que tenga ñ, tildes, etc. |
| `text` | Color del texto, `RRGGBB` (por ejemplo `FFE3D3`). |
| `select` | Color de la fila, pestaña u opción elegida. |
| `background` | Imagen de fondo. Se dibuja a 1920×1080 (un píxel de la imagen = un píxel real). |
| `pill` | Marca de la fila elegida, 1056×72 con transparencia. Se estira al ancho de cada fila. |
| `layer` | Una capa animada (hasta 12 por aspecto, 64 piezas entre todas). Ver abajo. |

Los nombres de archivo solo pueden llevar letras, números, `.`, `_` y `-`, y estar en la propia carpeta.

## Capas

```
layer=imagen.png effect=EFECTO parámetro=valor parámetro=valor ...
```

Las posiciones se dan en coordenadas de **1280×720** (el centro es `640 360`). Las capas se dibujan por orden: la última queda encima. Con `front=1` una capa se dibuja delante de la interfaz.

Parámetros comunes: `count` (copias), `x`, `y`, `size` (%), `alpha` (0–255), `add=1` (suma luz, ideal para brillos, chispas y estrellas), `front=1`. Muchos admiten un **rango** (`size=20-60`): cada copia toma un valor distinto.

| Efecto | Qué hace | Parámetros propios |
|---|---|---|
| `static` | Fija. | |
| `bob` | Sube y baja suavemente (un sol). | `amp` (px), `period` (s), `pulse` (% de pulso del tamaño) |
| `sway` | Se mece, respira y se inclina (cortinas de luz). | `count`, `x`, `dx` (separación), `amp`, `period`, `pulse`, `breathe` (variación del alpha), `tilt` (grados) |
| `drift` | Cruza la pantalla en bucle (nubes). | `count`, `x0` (inicio), `dx`, `dy`, `speed` (px/s), `dspeed` (más velocidad por copia), `loop` (anchura del recorrido) |
| `rise` | Partículas que suben o caen, con parpadeo (chispas, nieve). | `count`, `size=a-b`, `amp`, `period=a-b` (s), `y0` (inicio), `y1` (fin; si es mayor que `y0` caen) |
| `twinkle` | Copias fijas cuyo brillo sube y baja (estrellas). | `count`, `size=a-b`, `alpha=a-b`, `period=a-b`, `y=a-b` (franja vertical) |
| `scroll` | Imagen ancha que avanza en bucle (olas). Que la imagen sea el doble de ancha que el recorrido. | `speed` (px/s reales), `loop` (px reales) |
| `perspective` | Líneas que avanzan hacia ti (rejilla). | `count`, `horizon` (y del horizonte), `period` |
| `shoot` | Una estrella fugaz cada cierto tiempo. | `period` (s), `vx`, `vy` (px por fotograma), `angle`, `length` (fotogramas) |

## Consejos

- Imágenes **PNG con transparencia**. Para brillos usa `add=1` con fondo transparente y colores claros.
- El fondo ocupa 1920×1080×4 bytes en memoria y las capas anchas (`scroll`) más: cuida el tamaño en la PS5.
- Los textos son blancos sobre el fondo: elige un fondo no demasiado claro, o ajusta `text`/`select`.
- Un aspecto con errores no cierra la app: lo que no se entiende se ignora.
