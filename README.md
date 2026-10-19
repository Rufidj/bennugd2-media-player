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
  Plex (free ad-supported catalogue + your own server, login by code), Radio Browser, SomaFM, Internet Archive,
  PeerTube (federated video network), YouTube (popular videos, search of videos, channels and playlists)
- **Store**: installs and updates the addons, and downloads free TV/radio lists (TDTChannels, iptv-org...), from the official repository in the app itself (no FTP, no PC)
- Credits screen (Options → Settings → About)

## Download

See the [Releases](../../releases) page:

- **PS5 (title folder for ShadowMount+)**: `BennuGD2-Media-Player-PPSA00090-ShadowMount.zip` — copy the `PPSA00090` folder to `/data/homebrew/`, `eboot.bin` last
- **PS5 (package)**: `UP9000-PPSA00090_00-BENNUMEDIAPLAYER.pkg` (title id PPSA00090)
- **Linux x86-64**: `bennugd2-media-player-linux-x86_64.tar.gz` (needs FFmpeg, SDL2, FreeType and OpenSSL libraries, see its README)
- **Windows x86-64**: `bennugd2-media-player-windows-x86_64.zip` (self-contained; tested under Wine, not yet on a real Windows machine)

## PS5 requirements

Tested on firmware 9.00 with etaHEN and ShadowMount+ v1.7-beta5fix1 (kstuff active). The payloads used are in [`payloads.zip`](payloads.zip) (`kstuff.elf`, `a53_ppr_install_fast.elf`). With etaHEN running, the app asks it to leave the sandbox
(it writes its PID to `/download0/etahen_jailbreak`) so it can browse the whole system; without etaHEN it still runs, sandboxed (own folder and `/data/mediaplayer` only).
If the app does not open: check the firmware, that kstuff is loaded before ShadowMount+, copy `eboot.bin` last, and change the title id if a failed launch left it registered with error `0x80020008`.

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

An addon installed by hand (or downloaded from the **Store** in the main menu) is listed while the one that comes with the
player keeps its own folder: if both have the same folder name, the one in `<store>/addons/` wins, so installing from the
Store also updates the addons that ship with the player.

## Store

The **Store** row of the main menu downloads the addons from the [official repository](https://github.com/Rufidj/bennugd2-media-player)
(`addons/index.txt` + each addon folder). ✕ installs or updates the selected addon, ○ goes back and □ opens a small menu
(refresh the list). Every addon is shown with its state (`Installed`, `Update available`, `Not installed`). Addons are
plain text files, so nothing is executed while downloading; the list is left cached to show it when there is no connection.
Set `MP_STORE_URL` to another URL to use a mirror or a fork.

Besides the addons, the Store offers **free TV and radio lists** (TDTChannels, iptv-org...) taken from `addons/lists.txt`
(one line per list: `name | url | description`): ✕ downloads the list to "My lists" (`<store>/listas/`), where it can be
played at once, and pressing ✕ again downloads it again to refresh it. `tools/check_store_lists.py` checks that file
(and that every source still answers).

A list can also ask for an **account**: with a fourth field in the catalogue (`mode=basic` or `mode=form;login=...`) the
player asks for the user and the password when the list is installed, keeps them next to the list (`<store>/listas/<list>.auth`)
and uses them to download it and to play its channels. Any list can have an account too (options of a list: *Account for this
list*), and they are all listed in *Settings > Accounts*. The credentials are kept in plain text in the player's storage folder.

With `mode=xtream` the player talks to an IPTV panel that uses the **Xtream Codes API**: it asks for the server, the user and
the password, and shows the panel's own tree (live TV, movies and series by category). The channels are played with the URLs
the panel expects (`<server>/live/<user>/<pass>/<id>.ts`).

Addons go to the first folder the player can really write to: `/data/mediaplayer` on the PS5 and
`mediaplayer_data` next to the player on the PC (it is created the first time). `MP_STORE=/folder` forces another one.

## Credits

Created by Rufidj and Claude. Thanks to SplinterGU for BennuGD2, to Panreyes for the TTF implementation, and to FFmpeg, SDL, sdl-gpu,
FreeType, Google Noto fonts, OpenSSL, Plex, SomaFM, Radio Browser, Internet Archive, PeerTube/Framasoft, YouTube, TDTChannels,
iptv-org and the PS5 homebrew community.

## License

MIT for the player code (see [LICENSE](LICENSE)). Third-party components keep their own licenses (BennuGD2, FFmpeg, SDL, FreeType, OpenSSL, Noto fonts: SIL OFL).
Plex, SomaFM, Radio Browser, Internet Archive, PeerTube and YouTube are trademarks/services of their owners; the addons only use their public APIs. The TV/radio lists of the Store belong to their authors (TDTChannels, iptv-org) and each channel is streamed from its own source. DRM-protected content is not supported.

---

### Notas en español

- Descarga el `.pkg` para PS5 o el `.tar.gz` para Linux en *Releases*.
- La **Tienda** (menú principal) instala y actualiza los addons y descarga listas de TV/radio gratis (TDTChannels, iptv-org...) a "Mis listas": X instala, ○ vuelve y cuadrado abre el menú (actualizar la lista).
- Las listas de pago se pueden usar: al instalarlas el reproductor pide el usuario y la contraseña, los guarda junto a la lista (`<almacen>/listas/<lista>.auth`) y los usa para bajarla y reproducir sus canales. También se pueden poner a mano (opciones de una lista: *Cuenta de esta lista*) y se ven en *Ajustes > Cuentas*. Ojo: se guardan en texto plano en el almacén del reproductor.
- Para compilar desde el código hace falta BennuGD2 con los cambios de `libmod_video` (parche en `engine/`).
- Tutorial para crear addons en español: [ADDONS.es.md](ADDONS.es.md).
- Los títulos de Plex con DRM no se pueden reproducir (el addon los oculta).
