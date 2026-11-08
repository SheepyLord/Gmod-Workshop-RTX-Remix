# notice.lua

The companion's notice at the top right: R22's frame generation notice
([ADR 0129](../../../../docs/decisions/0129-the-upscaling-hint-also-at-the-top-right.md)), shared
since R23 by the hint ([`nativeloader_upscaling_hint.lua`](../autorun/client/nativeloader_upscaling_hint.lua.md)),
the start-up stall notice ([`!!!!nativeloader_engine_guard.lua`](../autorun/!!!!nativeloader_engine_guard.lua.md))
and the imported characters' PBR progress ([ADR 0132](../../../../docs/decisions/0132-progress-while-imported-pbr-converts.md)). Client only; the server sends it with the other shared
rules ([`nativeloader_i18n.lua`](../autorun/nativeloader_i18n.lua.md)).

```lua
local Notice = include("nativeloader/notice.lua")
local panel = Notice.Show(text, { seconds = 15, title = "RTX Remix", progress = 0.4 })
panel:SetNoticeText(text)        -- new body text
panel:SetNoticeProgress(0.75)    -- the bar, 0 to 1 (nil hides it)
panel:FinishNotice(2)            -- fade out and go after 2 seconds (at least 0.6)
```

- `seconds` (default 15): how long it stays; `0` keeps it until it is closed or finished.
- A dark rounded panel 500 px wide (scaled by `ScrH() / 1080`, at least 0.65, as the companion's windows
  are at 4K), the green accent bar, the title, the wrapped body, a close button, and with `progress` a
  bar along the bottom. It fades in over 0.25 s and out over the last 0.6 s.
- It sits 20 px from the right edge, below every other visible notice-sized panel in the top-right
  corner (the Model Hotloader's sits at y = 40, and our own earlier notices), never below a full-screen
  menu.
- Returns `nil` without VGUI. The module is kept in `NATIVELOADER_NOTICE`.
