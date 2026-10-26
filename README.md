# mpv config

A fork of [Zabooby/mpv-config](https://github.com/Zabooby/mpv-config) kept at
its September 2024 look (uosc 5.6, line timeline, black menus), cut down to
what is used on Linux.

`mpv.conf` and `input.conf` are not here: the NixOS dotfiles
([Luvrok/dotfiles](https://github.com/Luvrok/dotfiles), `nixos/overlays/mpv`)
pin a commit of this repo and add both files on top of `portable_config`.

## Scripts

- [uosc](https://github.com/tomasklaen/uosc) 5.6 - the UI: timeline, controls, menus.
- [thumbfast](https://github.com/po5/thumbfast) - timeline thumbnails.
- [memo](https://github.com/po5/memo) - watch history (`h`).
- [InputEvent](https://github.com/natural-harmonia-gropius/input-event) - click, press and release bindings in `input.conf` (`#@click`).
- [autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua) - the rest of the folder becomes the playlist.
- [autodeint](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autodeint.lua) - picks a deinterlacer on demand (`Ctrl+d`).
- `keys.lua` - the hotkey cheat sheet (`?`), made from the comments in `input.conf`, in uosc's menu look. Type to search, `Esc` to close.

The dotfiles add these from nixpkgs (`mpvScripts`), their settings are in
`script-opts` here:

- [mpris](https://github.com/hoyon/mpv-mpris) - the desktop's media controls see mpv.
- [videoclip](https://github.com/Ajatt-Tools/videoclip) - `c` cuts a clip: `s` start, `e` end, `c` save. 1080p H.264 to the XDG videos folder, visible subtitles burned in.
- [SmartSkip](https://github.com/Eisa01/mpv-scripts) - `>` skips an opening or ending (or to the next silence without chapters). It only prompts, never skips by itself, `Ctrl+.` turns the prompts off.
- [autosubsync](https://github.com/joaquintorres/autosubsync-mpv) - `n` syncs subtitles to the audio with ffsubsync.
- [reload](https://github.com/4e6/mpv-reload) - `Ctrl+r` reopens the file at the same spot, and stuck streams by itself.

## input.conf

The cheat sheet and the right click menu both come from `input.conf`:

```
## Playback                                       a cheat sheet section
SPACE  cycle pause  # play / pause                 a row of it
f      cycle fullscreen  # fullscreen  #! Video > Fullscreen
#      cycle deband                    #! Video > Deband
```

A binding without a comment isn't on the sheet. Bindings of a section with the
same comment share a row (`← / a  back 5 s`). The `#!` part is uosc's menu
entry, a line starting with `#` is a menu entry without a key.

## Profiles

`profiles.conf` downmixes 5.1 and 7.1 to stereo with the dialogue kept up,
evens out loud and quiet parts of surround audio, and debands harder in any
folder named `Anime`.
