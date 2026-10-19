# Installer artwork

The disk image uses a 680 x 440 point Finder content area. The real app and Applications shortcut have 96 point icons centered at `(180, 250)` and `(500, 250)`. The background leaves these positions and their native labels empty.

Regenerate both PNG resolutions on macOS from the repository root:

```sh
swift packaging/dmg/render-background.swift
```

The renderer uses macOS AppKit, Core Graphics, and Core Text. The bundled variable font is registered only inside the rendering process. It is not installed on the machine or bundled into the application executable.

## Brand sources and licensing

- WAMELINK's open-W polygon geometry is reproduced exactly from `components/design/brand/wamelinkMark.ts` in the WAMELINK website repository. Wordmark proportions follow `WamelinkWordmark.tsx` and `.wm-wordmark-w` / `.wm-wordmark-punt` in `app/design/wm.css`.
- The wordmark combines that open W with Plus Jakarta Sans 800 and the brand's circular red dot. WAMELINK branding belongs to Dennis Wamelink; the font license does not grant rights to the brand.
- `fonts/PlusJakartaSans.ttf` is the unmodified Plus Jakarta Sans variable font, licensed under the SIL Open Font License 1.1. Its copyright notices and complete license are in `fonts/OFL.txt`.
- Colors: white `#FFFFFF`, ink `#0E0F11`, secondary text `#52555C`, and WAMELINK red `#D6221C`.

The PNG files contain background artwork only. The installer uses Finder's real app icon and Applications folder for drag-and-drop installation.
