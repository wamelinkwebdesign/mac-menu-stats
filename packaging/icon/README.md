# Menu Stats app icon

An original, flat statistics mark on a light rounded macOS tile. Three solid grey-to-black columns represent CPU, memory, and storage. A small WAMELINK red segment in the top strip refers to the app's menu-bar home. Dennis requested a flat black, white, grey, and red variation on 19 October 2026.

The artwork uses solid fills throughout, with no gradients, glossy shading, or drop shadow. A fine neutral outline keeps the tile visible against white Finder backgrounds. The palette is light `#FAFAFA`, grey `#969BA3`, charcoal `#52565E`, ink `#0E0F11`, and red `#D6221C`.

Regenerate the artwork on macOS from the repository root:

```sh
swift packaging/icon/render-icon.swift
```

The editable renderer uses AppKit and Core Graphics, then Apple's `iconutil` to create:

- `AppIcon.png`: a transparent 1024 x 1024 master.
- `AppIcon.icns`: all ten standard macOS iconset representations, from 16 x 16 through 512 x 512 at 2x.

Every representation is drawn directly from vector geometry. The 16 and 32 point versions use wider columns and a thicker top strip to preserve both the statistics and the red accent at small sizes. The renderer creates its intermediate iconset in a temporary directory and removes it after conversion. No additional tools, fonts, or network access are needed.

The artwork belongs to this project and uses no stock symbol, external image, or third-party font.
