# BennuGD2 Media Player

A media player written entirely in [BennuGD2](https://github.com/SplinterGU/BennuGD2) (`.prg`), for **PC (Linux)** and **PlayStation 5** homebrew.
Interface drawn at 1080p with a PlayStation-style skin, designed to be driven with a gamepad.

*Reproductor multimedia escrito íntegramente en BennuGD2, para PC (Linux) y homebrew de PS5. Interfaz a 1080p con aspecto estilo PlayStation, pensada para mando.* (Spanish notes at the end.)

## Features

- File explorer with **preview** (a random frame, duration, resolution, audio/subtitle tracks), icons and folders
- Video, **music mode with visualizer** (spectrum / waveform), cover art
- **Subtitles** (embedded + external `.srt`), **multiple audio tracks**, seeking, volume
- **Streaming URLs**, `.m3u` / `.m3u8` lists with logos, list editor with an on-screen keyboard
- **6 UI languages** with TrueType fonts: Spanish, English, Russian, Japanese, Chinese, Korean
- **Addons** written in a small English-like language, no compiler needed (see [ADDONS.md](ADDONS.md)):
  Plex (free ad-supported catalogue + your own server, login by code), Radio Browser, SomaFM, Internet Archive
- Credits screen (Options → Settings → About)

## Download

See the [Releases](../../releases) page:

- **PS5**: `UP9000-PPSA00090_00-BENNUMEDIAPLAYER.pkg` (title id PPSA00090)
- **Linux x86-64**: `bennugd2-media-player-linux-x86_64.tar.gz` (needs FFmpeg, SDL2, FreeType and OpenSSL libraries, see its README)
- **Windows x86-64**: `bennugd2-media-player-windows-x86_64.zip` (self-contained; tested under Wine, not yet on a real Windows machine)

## Controls

| Gamepad | Keyboard | Action |
|---|---|---|
| D-pad / stick | arrows | move |
| ✕ | Enter | open / choose |
| ○ | Esc / Backspace | back / cancel |
| □ | M | options (browser) / mute (player) |
| △ | S | subtitles |
| Start | Space | pause |
| L1 / R1 | N / P | -10 s / +10 s |
| Touchpad | A | next audio track |

## Run from source (Linux)

You need BennuGD2 built with the **`libmod_video` changes** in [`engine/libmod_video-mediaplayer.patch`](engine/libmod_video-mediaplayer.patch)
(audio tracks, audio-only/cover/spectrum, network timeouts, `HTTP_FETCH`/`HTTP_READ`/`HTTP_WRITE`… for the addons, HLS fixes).
Then:

```sh
BGD=/path/to/BennuGD2/build/linux-gnu/bin ./run.sh      # compiles mediaplayer.prg and runs it
```

PS5 build (needs the `ps5` branch of the engine): `./build_ps5.sh`.
Windows build: `engine/build_windows.sh` (mingw-w64 cross build; also needs `engine/cmake-skip-modules.patch`).

Useful variables: `MEDIA_DIR=/folder` (start folder), `MP_STORE=/folder` (where lists, settings and addon data are stored).

## Addons

Drop a folder with a `main.addon` file into `<store>/addons/` (on the PS5: `/data/mediaplayer/addons/`). Press □ on an addon for its settings.
Tokens and passwords are entered by each user in the settings, never written in the script.
Tutorial: [ADDONS.md](ADDONS.md) · [ADDONS.es.md](ADDONS.es.md).

## Credits

Created by Rufidj and Claude. Thanks to SplinterGU for BennuGD2, to Panreyes for the TTF implementation, and to FFmpeg, SDL, sdl-gpu,
FreeType, Google Noto fonts, OpenSSL, Plex, SomaFM, Radio Browser, Internet Archive and the PS5 homebrew community.

## License

MIT for the player code (see [LICENSE](LICENSE)). Third-party components keep their own licenses (BennuGD2, FFmpeg, SDL, FreeType, OpenSSL, Noto fonts: SIL OFL).
Plex, SomaFM, Radio Browser and Internet Archive are trademarks/services of their owners; the addons only use their public APIs. DRM-protected content is not supported.

---

### Notas en español

- Descarga el `.pkg` para PS5 o el `.tar.gz` para Linux en *Releases*.
- Para compilar desde el código hace falta BennuGD2 con los cambios de `libmod_video` (parche en `engine/`).
- Tutorial para crear addons en español: [ADDONS.es.md](ADDONS.es.md).
- Los títulos de Plex con DRM no se pueden reproducir (el addon los oculta).
