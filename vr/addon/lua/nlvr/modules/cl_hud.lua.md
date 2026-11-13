# cl_hud.lua: Wrist HUD module

Descriptor hud/order 10. Starts V1 fonts, text and exact 769x257 RGBA8 canvas through the overlay manager. The off hand is left by default and mirrors with dominant hand. Health/armour/ammo changes invalidate; unchanged pixels are reissued only until the runtime overlay-copy acknowledgement. Thirty consecutive Info errors use V1 session failure handling. wrist_hud visibility and dominant changes apply only while active. Stop destroys the overlay; the registry also cleans it on failure. No file writes or engine convar changes.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

The manager clears to the exact V1 RGBA (12,18,26,235). A real capture found that a translucent DrawRect instead premultiplied the colour and squared its alpha to (11,17,24,217); direct clear restores the original pixels.
