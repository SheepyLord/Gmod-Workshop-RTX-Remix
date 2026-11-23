-- ADR 0261 (queue_check_session.py's stale and stale-net runs): material variables set at ShutDown, as the companion's
-- hooks do for imported characters (SetTexture, SetInt, Recompute), on materials made with CreateMaterial and on
-- file-based ones. In queued rendering each setter waits in the list the main thread records, holding its variable;
-- the RTX fixes' map-exit cleanup then uncaches every material. Without the engine guard's flush (or its target check)
-- the game crashed after this 4 of 4 times (exit 0xC0000409). Client realm; poc_session.py's --lua sends it through
-- the console once the run's second map is up, so it exercises the final disconnect, not the level change.
--
-- Hook order is not guaranteed, so the hazardous order is made certain: this wraps the fixes' own ShutDown hook
-- (RTXTextureCleanup_MapExit, re-added under the same name), so the setters are queued right before that hook's body
-- runs. Without the fixes' hook it adds a ShutDown hook of its own and says so.
local N = 24
local made, disk = {}, {}
local white = Material("models/debug/debugwhite")
local tex = white:GetTexture("$basetexture")
local other = Material("models/shiny"):GetTexture("$basetexture") or tex
for i = 1, N do
    made[i] = CreateMaterial("nlqueue_stale_" .. i, "VertexLitGeneric",
        { ["$basetexture"] = "models/debug/debugwhite", ["$alphatest"] = "1" })
end
-- File-based materials only Lua refers to here (each is on the PoC's disk).
for _, name in ipairs({ "models/props_c17/metalladder001", "models/props_junk/ravenholmsign_sheet",
    "models/props_wasteland/wood_fence01a", "models/props_lab/cornerunit_cloud", "models/gibs/metalgibs/metal_gibs" }) do
    local m = Material(name)
    if m and not m:IsError() then disk[#disk + 1] = m end
end

local function queueRestores()
    local count = 0
    local function touch(m)
        if not other then return end
        m:SetTexture("$basetexture", other)
        local flags = m:GetInt("$flags") or 0
        m:SetInt("$flags", bit.bor(flags, 256))
        m:SetInt("$allowalphatocoverage", 1)
        m:Recompute()
        count = count + 1
    end
    for i = 1, N do touch(made[i]) end
    for _, m in ipairs(disk) do touch(m) end
    print("[nlqueue] stale: queued restores for " .. count .. " materials at ShutDown")
end

local shutdown = hook.GetTable().ShutDown
local fixes = shutdown and shutdown["RTXTextureCleanup_MapExit"]
if isfunction(fixes) then
    hook.Add("ShutDown", "RTXTextureCleanup_MapExit", function(...)
        queueRestores()
        return fixes(...)
    end)
    print("[nlqueue] stale: armed with " .. N .. " made and " .. #disk
        .. " disk materials, right before the RTX fixes' cleanup hook")
else
    hook.Add("ShutDown", "nlqueue_stale", queueRestores)
    print("[nlqueue] stale: armed with " .. N .. " made and " .. #disk
        .. " disk materials; the RTX fixes' cleanup hook is not there, so in a ShutDown hook of its own")
end
