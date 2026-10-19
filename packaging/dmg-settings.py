"""Finder layout for the WAMELINK Menu Stats disk image."""

from pathlib import Path

application = defines["app"]
asset_dir = Path(defines["project"]) / "packaging" / "dmg"

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
files = [(application, "Menu Stats.app")]
symlinks = {"Applications": "/Applications"}
# Hiding the app extension with SetFile adds FinderInfo that fails strict code-signature checks.

# dmgbuild combines this image and background@2x.png into a HiDPI TIFF.
background = str(asset_dir / "background.png")
# Hide only the generated support image; the signed app must remain untouched.
hide = [".background.tiff"]
# Include Finder's title bar above the 680 x 440 point artwork.
window_rect = ((200, 140), (680, 472))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 80
icon_locations = {
    "Menu Stats.app": (180, 250),
    "Applications": (500, 250),
    # Keep the artwork clear even when Finder exposes hidden files.
    ".background.tiff": (1000, 1000),
}
icon_size = 96
text_size = 13
label_pos = "bottom"
