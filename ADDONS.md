# Creating addons for the BennuGD2 Media Player

An addon is a plain text file called `main.addon`. It is written in a small English-like language that the player itself understands: **no compiler, no libraries, no programming tools**. Edit the file with any text editor, copy it to the console, done.

Addons let the player show content from other places: a Plex server, internet radios, a video archive... The addon downloads data (usually JSON) from a web API and tells the player which folders and playable items to show.

## Installing

Put each addon in its own folder:

```
/data/mediaplayer/addons/my-addon/main.addon      (console, writable)
<player folder>/addons/my-addon/main.addon        (shipped with the player)
```

Optional: a `logo.png` (for example 480x270) next to `main.addon` is shown as the preview when the addon is selected.

Open **Addons** on the home screen. Select an addon to browse it. Press **SQUARE** on an addon to open its **settings**. Press **CIRCLE** to go back, or to cancel a download in progress.

## A first addon

```
addon "Hello radio"
id hello-radio
version 1.0
author "Me"
description "One radio station."

page home:
    show radio "SomaFM Groove Salad" playing "https://ice1.somafm.com/groovesalad-128-mp3" info "Chilled beats"
```

The first page of every addon is `home`.

## Structure

Indentation (4 spaces) defines blocks, as in Python. `#` starts a comment.

| Line | Meaning |
|---|---|
| `addon "Name"` | display name (required) |
| `id name` | unique id, used for the saved settings file |
| `version`, `author`, `description` | shown in the Addons list |
| `setting ...` | a user setting (see below) |
| `page NAME:` / `page NAME with a, b:` | a screen of items; `with` lists the arguments it receives |
| `define f(a, b):` | a reusable function (up to 6 arguments) |

## Settings (and secrets)

```
setting server is text, label "Server address", default "http://192.168.1.50:32400"
setting token  is secret text, label "Plex token"
setting hd     is yes or no, label "Prefer HD", default yes
setting count  is number, label "Items", default 50
setting mode   is choice, label "Quality", choices "128 mp3", "64 aac"
```

Each setting becomes a variable with that name inside the addon. **Secrets are never written in the script**: every user types their own in the settings menu (SQUARE). They are saved in `<store>/addons_data/<id>.cfg` and shown as `*****`.

## Pages and items

A page runs from top to bottom and every `show` adds an item to the list.

```
show folder TITLE opening PAGE [with name is value ...]
show video  TITLE playing URL
show audio  TITLE playing URL
show radio  TITLE playing URL
```

Optional clauses on any `show`: `logo URL`, `info TEXT`, `year N`, `duration SECONDS`, `subtitles URL`.

```
page home:
    show folder "Movies" opening movies with genre is "all" with title is "Movies"

page movies with genre, title:
    show video "Big Buck Bunny" playing "http://example.com/bbb.mp4" year 2008 duration 596
```

Arguments pass as JSON, so numbers, text, lists and records all survive.

## Values

Numbers `3`, `2.5`; text `"hi {name}"` (anything in `{}` is evaluated; single quotes work too, handy inside `{}`); lists `[1, 2, 3]` (**numbered from 1**); records `{title: "x", year: 2000}`; `true`/`false`; `nothing`. Fields: `item.title`, `list[1]`, `item["any key"]`.

## Statements

```
set x to 5                     add 1 to x          add item to my_list
clear my_list
if x is greater than 3:        otherwise if x is 3:        otherwise:
for each item in list [limit 20]:     (sets index; for records also key)
while x is less than 10:
repeat 5 times:                (sets counter)
stop                           (end the page)      skip   (next loop turn)     exit loop
give back VALUE                (return from a function)
fail "message"                 (show an error dialog and stop)
try:  ...   on error:  ...     (error text is in `error`)
message "Loading..."           clear message        wait 2 seconds
ask "Question" into answer [default "x"] [secret]
save NAME as VALUE             (store a value in the settings file)
log "text"                     (debug output)
```

## Conditions

`is`, `is not`, `is greater than`, `is less than`, `is at least`, `is at most`, `is empty`, `is nothing`, `contains`, `starts with`, `ends with`, combined with `and`, `or`, `not`. Arithmetic: `+ - * / %`.

## Downloading data

```
fetch json from URL                     # result is in `result`
fetch json from URL into data
fetch text from URL
fetch json from URL with header "Accept" is "application/json"
fetch json from URL with method "POST" with body json({a: 1})
```

If the server fails (or answers 401/403/404) the player shows a clear error with the addon line number. Wrap in `try`/`on error` to handle it yourself.

## Built-in functions

Text: `length upper lower trim replace shorten slice split join text number url_encode base64 index_of`
Math: `round floor ceil abs min max random`
Lists: `first last reverse range keys has sort filter pick join`
Other: `json parse_json default now uuid format_time join_url`

`default(value, fallback)` is the way to deal with missing fields. `sort(list, "field")` sorts records.

## Login by code (example)

See `addons/demo/main.addon` in the source: it uses `ask`, `message`, `wait` and `save` to show a code, poll a server and store the token the server returns.

## Limits and safety

- Both `http://` and `https://` work for `fetch` (redirects are followed; HTTPS is done by the engine, no certificates to manage in the addon).
- Playback headers: add `with header "Name" is value` to a `show video/audio/radio`. The player downloads the stream's `.m3u8` playlist with those headers and plays it from a local file, so it works for HLS playlists whose segments do not need headers (as Plex's free catalogue). For plain files, put the key in the URL.
- Some Plex titles are DRM-protected and cannot be played (the Plex addon hides them); no DRM content is supported by the player.
- No XML (JSON and text only). Functions take at most 6 arguments. A page has at most 3000 items and 4,000,000 steps (stops endless loops).
- An unreachable IP (no answer at all) can block for up to 15 s (http) or the system timeout; check the address.
- Addons can contact any HTTP server you let them. **Install only addons you trust.** No DRM content is supported.

## Debugging

Errors show the addon file and line. Use `log "x is {x}"` to print values to the player's log.

## Publishing an addon in the Store

The player's Store reads `addons/index.txt` from the repository: one line per addon with `id | name | version | files | description`
(the `id` is the addon folder). `tools/make_addon_index.py` writes that file from the `addon`, `version` and `description` lines of
every `addons/*/main.addon`, so an addon that is added, changed or version-bumped appears in the Store as soon as the index is
regenerated and pushed:

```sh
python3 tools/make_addon_index.py && git add addons/index.txt && git commit -m "Update the addon index" && git push
```

The Store only downloads the files listed in the `files` field (`main.addon,logo.png` by default) and refuses to install anything
that is not a parsable addon.

## Publishing a TV/radio list in the Store

The Store also offers free lists of channels, taken from `addons/lists.txt`: one line per list with `name | url | description`.
`name` is the file name it gets in "My lists" (the player adds `.m3u`) and `url` is where it is downloaded from, so any public
M3U of channels works (TDTChannels, iptv-org...). Edit the file, check it and push:

```sh
python3 tools/check_store_lists.py && git add addons/lists.txt && git commit -m "Update the store lists" && git push
```

A list is downloaded whole and refuses to install anything that does not look like an M3U; the player shows up to 2047 entries
of each list, so the checker warns about longer ones.
