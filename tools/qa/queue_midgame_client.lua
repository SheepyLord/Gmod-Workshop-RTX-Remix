-- ADR 0262 (queue_check_session.py's midgame and midgame-console runs): the RTX fixes' texture cleanup in the middle of
-- a game. Variables of file-based materials are set (in queued rendering each setter waits in the list the main thread
-- records, holding its variable), then the cleanup runs in the same frame, before the render thread has run that list.
-- Before ADR 0262 the cleanup uncached every material with the setters still queued and the render thread ran them on
-- freed memory (exit 0xC0000005); now the cleanup has the engine guard run them first. Client realm; poc_session.py's
-- --lua sends it through the console once the run's second map is up.
--
-- NLQ_MODE "lua" (the default): a few seconds after this file is sent, a timer sets the variables and calls the Lua
-- global RTX_CleanupMapTextures() in the same chunk. NLQ_MODE "console": nothing runs by itself; the driver sends
-- `nlqueue_touch;rtx_flush_textures` as one console line, so the setters are queued and the console command's cleanup
-- runs in one pass of the command buffer (lua_run_cl would run its code later, after the cleanup). The Lua console
-- command nlqueue_touch is defined in both modes.
local other = Material("models/shiny"):GetTexture("$basetexture")
local disk = {}
-- File-based materials only Lua refers to here (each is on the PoC's disk).
for _, name in ipairs({ "models/props_c17/metalladder001", "models/props_junk/ravenholmsign_sheet",
    "models/props_wasteland/wood_fence01a", "models/props_lab/cornerunit_cloud", "models/gibs/metalgibs/metal_gibs" }) do
    local m = Material(name)
    if m and not m:IsError() then disk[#disk + 1] = m end
end

-- The line ends with the number of setter calls made: the driver wants the cleanup's "Ran <n> queued render calls"
-- line to count at least that many (each SetTexture queues two calls, the setter and its texture's release).
local function touch()
    local calls = 0
    for _, m in ipairs(disk) do
        if other then
            m:SetTexture("$basetexture", other)
            calls = calls + 1
        end
        m:SetInt("$flags", bit.bor(m:GetInt("$flags") or 0, 256))
        calls = calls + 1
    end
    print("[nlqueue] midgame: queued setters for " .. #disk .. " file-based materials (" .. calls .. " calls)")
end

concommand.Add("nlqueue_touch", touch)

local mode = NLQ_MODE or "lua"
print("[nlqueue] midgame: armed (" .. mode .. ") with " .. #disk .. " disk materials")
if mode == "lua" then
    timer.Simple(3, function()
        touch()
        local ok, result = pcall(RTX_CleanupMapTextures)
        print("[nlqueue] midgame: RTX_CleanupMapTextures returned " .. tostring(ok) .. " " .. tostring(result))
    end)
end
