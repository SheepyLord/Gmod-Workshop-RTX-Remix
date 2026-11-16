# Startup message

Edit startup_message.txt for the English top-left launch text. The six suffixed files are its
translations, selected by Remix's rtx.gui.language setting. Keep {hotkey} and {seconds}; the runtime
substitutes the actual key binding and countdown. Text is UTF-8, at most 8192 bytes, and displayed
literally, so percent signs do not act as format commands. The project URL is ordinary text here.

The fixes packager deploys these to rtx-remix/mods/nativeloader_ui with create-only policy, and the
runtime reads them there (StartupMessage::folder, runtime patch 0103). Editing the installed text
there also persists: user-edited files stay theirs. The folder holds no mod file, so Remix's mod
manager passes it by.

Until the repository review of 2026-11-16 (finding 17) the texts went to garrysmod/data/nativeloader_ui,
where any server's client Lua can write .txt files, so a server's text could stay on the splash at
every later start. A copy edited there is no longer read and is not moved to the new folder: a file in
garrysmod/data may as well be a server's, which nothing can tell from the player's. The loader removes
the unedited old copies and leaves an edited one in place, untracked; to keep a customised text, copy
it into rtx-remix/mods/nativeloader_ui once.

Source changes are rebuilt into the Workshop package by the usual main publishing hooks. The runtime
reads each language once per launch (or when its language changes); missing/invalid files fall back
to English and then the compiled project message.

Main-menu layout/project link are in loader/proxy/ui/mainmenu.js and its labels.json catalog.
That panel requires loader 0.8.1's winmm.dll, delivered in the loader bundle, not just a runtime update.
