-- Cheats off in a multiplayer game (the repository review of 2026-11-16, finding 16; ADR 0234). An RTX start's session
-- turns sv_cheats on for its rendering settings. GMod's New Game screen turns it off for the games it starts, from this
-- realm; a multiplayer game started another way (the command line, the console) kept it, so every player who joined a
-- listen server had cheats. GMod lets neither realm of a game run sv_cheats (RunConsoleCommand and game.ConsoleCommand
-- are blocked for it), so the server realm of such a game (the companion's engine guard autorun) leaves a request, the
-- time it was made, in data/nativeloader_companion/cheats_off.txt, and this menu script carries it out once the game is
-- running. A request older than five minutes, or one that cannot be read, is dropped unused. Connected to another
-- machine's server, sv_cheats 0 changes nothing (a client cannot set the server's replicated value).
if not MENU_DLL or NativeLoaderMultiplayerCheats then return end
NativeLoaderMultiplayerCheats = true

local REQUEST = "nativeloader_companion/cheats_off.txt"
local MAX_AGE = 300

timer.Create("NativeLoaderMultiplayerCheats", 1, 0, function()
    if not file.Exists(REQUEST, "DATA") then return end
    local made = tonumber(string.Trim(file.Read(REQUEST, "DATA") or ""))
    local age = made and os.time() - made
    if not age or age < -60 or age > MAX_AGE then
        file.Delete(REQUEST)
        return
    end
    -- The game the request is for is still loading.
    if not IsInGame() then return end
    file.Delete(REQUEST)
    RunConsoleCommand("sv_cheats", "0")
    print("[nativeloader] sv_cheats 0: a game with more than one player slot keeps no cheats on, as the New Game screen does")
end)
