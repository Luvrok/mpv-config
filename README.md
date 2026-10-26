# mpv config

A fork of [Zabooby/mpv-config](https://github.com/Zabooby/mpv-config) kept at
its September 2024 look (uosc 5.6, line timeline, black menus), cut down to
what is used on Linux.

`mpv.conf` and `input.conf` are not here: the NixOS dotfiles
([Luvrok/dotfiles](https://github.com/Luvrok/dotfiles), `nixos/overlays/mpv`)
pin a commit of this repo and add both files on top of `portable_config`.

## Scripts

- [uosc](https://github.com/tomasklaen/uosc) 5.6 - the UI: timeline, controls, menus. Patched here, see below.
- [thumbfast](https://github.com/po5/thumbfast) - timeline thumbnails.
- [memo](https://github.com/po5/memo) - watch history (`Ctrl+h`).
- [InputEvent](https://github.com/natural-harmonia-gropius/input-event) - click, press and release bindings in `input.conf` (`#@click`).
- [autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua) - the rest of the folder becomes the playlist.
- [autodeint](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autodeint.lua) - picks a deinterlacer on demand (`Ctrl+d`).
- `keys.lua` - the hotkey cheat sheet (`?`), made from the comments in `input.conf`, in uosc's menu look. It opens typing a search, `Enter` keeps the result and lets keys through to try them, `Esc` clears, then closes.
- `find.lua` - a fuzzy finder (`Ctrl+p`) over `~/downloads`, `~/documents/videos` and `/media/outer-1` (`script-opts/find.conf` takes `roots`), newest first, in a uosc palette menu. `Enter` plays, `Shift+Enter` queues.
- `layout.lua` - binds every `input.conf` key once more for the russian layout, at the same physical key (`р` for `h`, `п-п` for `g-g`). Searches also try what was typed as the other layout's keys.
- `resume.lua` - with `save-position-on-quit=yes` every quit resumes, closing the window too. This drops the saved position at the end of a file, so a finished one starts over.

The dotfiles add these from nixpkgs (`mpvScripts`), their settings are in
`script-opts` here:

- [mpris](https://github.com/hoyon/mpv-mpris) - the desktop's media controls see mpv.
- [videoclip](https://github.com/Ajatt-Tools/videoclip) - `c` cuts a clip: `s` start, `e` end, `c` save. 1080p H.264 to the XDG videos folder, visible subtitles burned in.
- [SmartSkip](https://github.com/Eisa01/mpv-scripts) - `>` skips an opening or ending (or to the next silence without chapters). It only prompts, never skips by itself, `Ctrl+.` turns the prompts off.
- [autosubsync](https://github.com/joaquintorres/autosubsync-mpv) - `n` syncs subtitles to the audio with ffsubsync.
- [reload](https://github.com/4e6/mpv-reload) - `r` reopens the file at the same spot, and stuck streams by itself.
- [UndoRedo](https://github.com/Eisa01/mpv-scripts) - `Ctrl+o` / `Ctrl+i` go back and forth between seeks, like vim's jumplist.
- [subtitle-lines](https://github.com/christoph-heinrich/mpv-subtitle-lines) - `/` lists the subtitle lines in a uosc menu, enter jumps to one.

## uosc patches

Marked `Fork:` in the code:

- Menus take vim keys: `j`/`k`, `h` back (a folder up in the file browser),
  `l` open, `gg`/`G`, `Ctrl+u`/`Ctrl+d`, `q` close, and telescope's
  `Ctrl+j`/`Ctrl+k` and `Ctrl+n`/`Ctrl+p`, which also move while a search is
  typed. The same keys on the russian layout too. `menu_type_to_search=no`
  frees the letters, `/` searches.
- `script-message-to uosc open-file <directory>` opens the file browser in a
  directory, `g l` in `input.conf` uses it for the library.

## input.conf

The cheat sheet and the right click menu both come from `input.conf`:

```
## Playback                                       a cheat sheet section
SPACE  cycle pause  # play / pause                 a row of it
f      cycle fullscreen  # fullscreen  #! Video > Fullscreen
#      cycle deband                    #! Video > Deband
#? j / k   down / up                   a row for keys bound elsewhere
```

A binding without a comment isn't on the sheet. Bindings of a section with the
same comment share a row (`h / l / ← / →  back / forward 5 s`), `g-g` is the
sequence `g g`. The `#!` part is uosc's menu entry, a line starting with `#`
is a menu entry without a key.

## Profiles

`profiles.conf` downmixes 5.1 and 7.1 to stereo with the dialogue kept up,
evens out loud and quiet parts of surround audio, and debands harder in any
folder named `Anime`.
