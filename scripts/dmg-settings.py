# dmgbuild settings for the Hush installer window: a clean, toolbar-free window with the
# Hush icon on the left, the Applications folder on the right and an arrow between them.
# Used by scripts/build-app.sh:  dmgbuild -s scripts/dmg-settings.py -D app=... -D background=... "Hush Browser" out.dmg
import os.path

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")  # the mounted disk's icon

# Window: matches the 640×420 background drawn by scripts/make-dmg-background.swift.
background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (640, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

# Icons: centres must match appCenter / applicationsCenter in make-dmg-background.swift.
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 220),
    "Applications": (470, 220),
}
