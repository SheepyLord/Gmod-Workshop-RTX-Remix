-- shadow_copies_probe.lua: Local player shadow (the RTX fixes' body and weapon copies, rtx_pseudoplayer and
-- rtx_pseudoweapon) switched on and off in a PoC RTX session, with a screenshot and frame times before and after each
-- switch. shadow_copies_session.py puts its NLSH settings in front and runs it through poc_session.py --lua-shots.
-- See shadow_copies_probe.lua.md.
local SETTINGS = NLSH or {}
local results = { settings = SETTINGS, steps = {} }
local clock = SysTime
local co

local function wait(seconds)
    local untilTime = clock() + seconds
    while clock() < untilTime do coroutine.yield() end
end

-- Screenshots: "NL_SHOT <label>", answered by the run with nl_shot_taken <n>.
local shotsTaken, shotsAsked = 0, 0
concommand.Add("nl_shot_taken", function(_, _, args) shotsTaken = tonumber(args and args[1]) or (shotsTaken + 1) end)

-- A fresh PoC's first RTX map opens the RTX Remix guide and may show the loader's update reminder: windows over the
-- shot, removed as vr_session.lua does.
local function clear_windows()
    for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
        local title = IsValid(panel) and isfunction(panel.GetTitle) and string.lower(tostring(panel:GetTitle())) or ""
        if string.find(title, "remix guide", 1, true) or string.find(title, "loader update", 1, true) then panel:Remove() end
    end
end

local function shot(label)
    clear_windows()
    wait(0.3)
    shotsAsked = shotsAsked + 1
    print("NL_SHOT " .. label)
    local deadline = clock() + 90
    while shotsTaken < shotsAsked and clock() < deadline do coroutine.yield() end
    wait(0.3)
    return shotsTaken >= shotsAsked
end

local function cvar(name)
    local value = GetConVar(name)
    return value and value:GetString() or nil
end

-- Frame times over a few seconds: a path-traced frame costs far more than a raster one.
local function frames(seconds)
    local list, last, began = {}, clock(), clock()
    while clock() - began < seconds do
        coroutine.yield()
        local now = clock()
        list[#list + 1] = (now - last) * 1000
        last = now
    end
    table.sort(list)
    local n = #list
    return { frames = n, median_ms = n > 0 and math.Round(list[math.ceil(n / 2)], 2) or nil,
             p90_ms = n > 0 and math.Round(list[math.ceil(n * 0.9)], 2) or nil }
end

local function state(label)
    local ply = LocalPlayer()
    local entry = { label = label, time = math.Round(CurTime(), 1),
        rtx_pseudoplayer = cvar("rtx_pseudoplayer"), rtx_pseudoweapon = cvar("rtx_pseudoweapon"),
        body_copies = #ents.FindByClass("rtx_pseudoplayer"), weapon_copies = #ents.FindByClass("rtx_pseudoweapon"),
        third_person = IsValid(ply) and ply:ShouldDrawLocalPlayer() or nil,
        weapon = IsValid(ply) and IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or nil,
        frame = frames(SETTINGS.measure or 3) }
    results.steps[#results.steps + 1] = entry
    print("NLSH_STATE " .. util.TableToJSON(entry))
    return entry
end

-- A third-person view as the motion importer's camera makes one: a CalcView that draws the player (drawviewer), here
-- 120 units behind them.
local thirdPerson = false
hook.Add("CalcView", "NLShadowProbeView", function(_, pos, angles, fov)
    if not thirdPerson then return end
    return { origin = pos - angles:Forward() * 120 + Vector(0, 0, 16), angles = angles, fov = fov, drawviewer = true }
end)

-- One step: the view, console commands (the switches, or the server's character commands), a wait, its state and
-- screenshot.
local function step(entry)
    if entry.view then thirdPerson = entry.view == "third" end
    for _, change in ipairs(entry.set or {}) do RunConsoleCommand(change[1], change[2]) end
    for _, command in ipairs(entry.run or {}) do RunConsoleCommand(command) end
    -- A diagnostic change in client Lua (the session's own code, never the player's input).
    if entry.lua then
        local err = RunString(entry.lua, "nlshadow_step", false)
        if err then print("NLSH_LUA_ERROR " .. entry.label .. " " .. tostring(err)) end
    end
    wait(entry.wait or SETTINGS.wait or 12)
    state(entry.label)
    shot(entry.label)
end

-- Settings the run changes and puts back: the copies' switches and the sky's clock.
local KEPT = { "rtx_pseudoplayer", "rtx_pseudoweapon", "rtx_pseudoweapon_unique_hashes", "dts_enabled",
    "nativeloader_sky_time_passes", "nativeloader_sky_hour" }

co = coroutine.create(function()
    wait(SETTINGS.settle or 15)
    results.original = {}
    for _, name in ipairs(KEPT) do results.original[name] = cvar(name) end
    print("NLSH_ORIGINAL " .. util.TableToJSON(results.original))
    -- The same light in every shot: the time of day held.
    if SETTINGS.hour then
        RunConsoleCommand("nativeloader_sky_time_passes", "0")
        RunConsoleCommand("nativeloader_sky_time", tostring(SETTINGS.hour))
    end
    -- A weapon in your hand (the tool gun draws a screen of its own).
    if SETTINGS.weapon then
        RunConsoleCommand("nlshadow_weapon", SETTINGS.weapon)
        wait(2)
    end
    if SETTINGS.character then
        RunConsoleCommand("nlshadow_character")
        wait(10)
    end
    state("01_before")
    shot("01_before")
    for _, entry in ipairs(SETTINGS.steps or {}) do step(entry) end
    -- The view and the settings go back as the session found them.
    thirdPerson = false
    for _, name in ipairs(KEPT) do
        if results.original[name] ~= nil then RunConsoleCommand(name, results.original[name]) end
    end
    RunConsoleCommand("nlshadow_server_report")
    wait(2)
    file.CreateDir("nlshadow")
    file.Write("nlshadow/client.json", util.TableToJSON(results, true))
    print("NL_SHOT_DONE")
end)

hook.Add("Think", "NLShadowProbe", function()
    if not co then return end
    local ok, err = coroutine.resume(co)
    if not ok then
        print("NLSH_ERROR " .. tostring(err))
        co = nil
        print("NL_SHOT_DONE")
    elseif coroutine.status(co) == "dead" then
        co = nil
    end
end)
print("NLSH_PROBE_READY")
