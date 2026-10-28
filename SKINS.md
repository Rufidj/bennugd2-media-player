# Creating skins

A skin is a **folder** with a `skin.cfg` and its images. No programming is needed: you make it on a PC with any image and text editor and add it to the app (PC, PS5, Android).

The 6 built-in skins (`res/skins/*`) use exactly this format, so they are good examples to copy from.

## Getting started

1. Copy the `skin_template` folder under another name (e.g. `my-skin`).
2. Edit `skin.cfg` and replace the images.
3. Put it in the skins folder and it will show up in **Settings → Appearance**:
   - **PC:** `skins/my-skin/` next to the player, or `<data folder>/skins/my-skin/`.
   - **PS5:** `/data/mediaplayer/skins/my-skin/` (over FTP).
   - **Android:** the app's data folder (`skins/my-skin/`).
4. On PC, **F5** re-reads the skin without restarting: edit, press F5, look.

Skins can also be installed from a web address: upload the folder to any web server and use **Settings → Install a skin from a URL** with the address of the folder (the one that contains `skin.cfg`).

## skin.cfg

`key=value` lines. Lines starting with `#` are comments (`# comment` at the end of a line works too).

| Key | What it does |
|---|---|
| `name` | Name shown in Settings. |
| `font` | A `.ttf`/`.otf` font in the folder. Only used for Latin-script languages (Russian, Japanese, Chinese and Korean keep their own font). If it cannot be opened the normal font is used. Check that it has accented letters. |
| `text` | Text colour, `RRGGBB` (e.g. `FFE3D3`). |
| `select` | Colour of the selected row, tab or option. |
| `background` | Background image, drawn at 1920×1080 (one image pixel = one real pixel). |
| `pill` | Highlight of the selected row, 1056×72 with transparency; it is stretched to each row's width. |
| `layer` | An animated layer (up to 12 per skin, 64 pieces in total). See below. |

File names may only contain letters, digits, `.`, `_` and `-`, and must be in the skin's own folder.

## Layers

```
layer=image.png effect=EFFECT param=value param=value ...
```

Positions use **1280×720** coordinates (the centre is `640 360`). Layers are drawn in order: the last one is on top. `front=1` draws a layer in front of the interface.

Common parameters: `count` (copies), `x`, `y`, `size` (%), `alpha` (0–255), `add=1` (adds light: perfect for glows, sparks and stars), `front=1`. Many accept a **range** (`size=20-60`): each copy takes a different value.

| Effect | What it does | Own parameters |
|---|---|---|
| `static` | Fixed. | |
| `bob` | Gently moves up and down (a sun). | `amp` (px), `period` (s), `pulse` (% size pulse) |
| `sway` | Sways, breathes and tilts (light curtains). | `count`, `x`, `dx` (spacing), `amp`, `period`, `pulse`, `breathe` (alpha variation), `tilt` (degrees) |
| `drift` | Crosses the screen in a loop (clouds). | `count`, `x0` (start), `dx`, `dy`, `speed` (px/s), `dspeed` (extra speed per copy), `loop` (length of the path) |
| `rise` | Particles that rise or fall, flickering (sparks, snow). | `count`, `size=a-b`, `amp`, `period=a-b` (s), `y0` (start), `y1` (end; if greater than `y0` they fall) |
| `twinkle` | Fixed copies whose brightness rises and falls (stars). | `count`, `size=a-b`, `alpha=a-b`, `period=a-b`, `y=a-b` (vertical band) |
| `scroll` | A wide image that scrolls in a loop (waves). Make the image twice as wide as the loop. | `speed` (real px/s), `loop` (real px) |
| `perspective` | Lines coming towards you (a grid). | `count`, `horizon` (y of the horizon), `period` |
| `shoot` | A shooting star every so often. | `period` (s), `vx`, `vy` (px per frame), `angle`, `length` (frames) |

## Tips

- Use **PNG with transparency**. For glows use `add=1` with a transparent background and light colours.
- The background takes 1920×1080×4 bytes of memory, wide `scroll` layers more: watch the size on PS5.
- Text is drawn in light colours on the background: avoid very bright backgrounds, or tune `text`/`select`.
- A skin with mistakes never closes the app: anything that is not understood is ignored.
