---
name: capture-docs-screenshots
description: Use when refreshing README, docs/ or wiki images from the real UI, or when a screenshot must show a specific state (panel open, key overlay, a CLI transcript) without touching the fan.
---

# Capture documentation screenshots

Rules first: a screenshot is **evidence of a real state**, never a mock-up. Do not
compose a picture of output you did not run, do not screenshot an agent's own
transcript window, and do not change fan state to get a nicer image.

Layer surfaces (the panel) do not appear in `hyprctl clients`, and the key overlay
needs a synthetic keypress, so the recipe below finds them instead of guessing.

## Capture the panel and the key overlay

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
omarchy-shell omafan close; sleep 1.5; grim /tmp/closed.png    # baseline
omarchy-shell omafan open;  sleep 3;   grim /tmp/open.png
wtype '?'                                                      # key overlay; the panel must have focus
sleep 1; grim /tmp/keymap.png
```

`grim` writes **physical** pixels: on a 2560×1600 display at scale 2 you get a
2560×1600 file, so multiply logical coordinates by the scale when cropping.

Find the panel's box by differencing the two captures — no guessing, no dead
space in the crop:

```sh
magick /tmp/open.png /tmp/closed.png -compose difference -composite \
  -colorspace gray -threshold 8% -format "%@" info:      # e.g. 696x720+1650+14
magick /tmp/open.png -crop 696x692+1650+48 +repage panel.png   # +48 drops the bar row
```

Keep a little margin and re-check the result: a crop that clips the footer or
keeps the bar strip in frame is the usual first-pass error.

## Capture the bar widget

The widget's columns are measurable, which beats cropping "by eye" — the right
section shifts whenever the label length changes (it grows leftward):

```sh
grim /tmp/bar.png
magick /tmp/bar.png -crop 1000x48+1560+0 +repage -colorspace gray -resize 1000x1! -depth 8 txt:-
# read the runs of non-background columns, then crop those columns and zoom
magick /tmp/bar.png -crop 285x48+1772+0 +repage -resize 400% bar-widget.png
```

The widget is tinted when a hold is active. You cannot show that state without
writing to the fan: document it in prose instead. If you change the label mode for
a shot, put it back — `omarchy bar set io.github.yadav-prakhar.omafan show temp`
is the default, and confirm the write in `~/.config/omarchy/shell.json`.

## Capture a CLI transcript

Use a real terminal in a *known* window, type the commands into it, and prove the
focus before typing:

```sh
setsid foot --app-id=omafan-demo -w 104x24 -f "monospace:size=13" </dev/null >/dev/null 2>&1 &
sleep 3
addr=$(hyprctl clients -j | jq -r '[.[] | select(.class=="foot")][-1].address)
hyprctl dispatch focuswindow "address:$addr"
[ "$(hyprctl activewindow -j | jq -r .address)" = "$addr" ] || exit 1   # abort if focus failed
wtype -s 60 'OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan'; wtype -k Return
wtype -s 60 '"$OMAFAN_DIR/bin/omafan-ctl" doctor --human'; wtype -k Return
sleep 2; grim /tmp/cli.png
```

Then crop to the window (logical geometry × scale) and trim the empty rows by
profiling them, so the image has no dead space:

```sh
magick /tmp/cli.png -crop 2512x1504+24+72 +repage /tmp/win.png
magick /tmp/win.png -colorspace gray -resize 1x1504! -depth 8 txt:-   # row means; last row > background = content end
magick /tmp/win.png -crop 2512x826+0+75 +repage -resize 1800x cli-doctor.png
```

Type only read-only commands (`doctor`, `status`, `presets`). If a write is part
of the story, use `--dry-run` and say so in the caption.

## Diagrams

Prefer inline **Mermaid** over a rendered image: GitHub (including its wikis)
renders it natively, it stays readable at any width, and it is editable as text.
Verify a diagram before shipping it — render the exact block with mermaid and
check both that it parses and how wide it comes out (a wide `flowchart LR` gets
scaled to unreadable in a content column; `flowchart TB` with short node labels
is usually the fix).

## Where the images go

- `preview.png` (repo root) — the hero. Keep it a real capture of the current
  build; a stale one is worse than none, because the labels in it date the UI.
- `docs/images/` — everything referenced from `README.md` or `docs/`.
- The wiki is a separate repository (`omafan.wiki`); copy the same files there and
  keep `images/` and the pages in sync with the repo state you captured.
