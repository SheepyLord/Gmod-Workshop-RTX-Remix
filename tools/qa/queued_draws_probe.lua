-- QA probe (queued draws, ADR 0192): client Lua for tools/qa/queued_draws_session.py. The driver puts a
-- settings table in front of this file:
--   NLQD = {mode = "stress" | "lighting", seconds = <stress duration>, shots = <checkpoint period>,
--           center = Vector(...), per_frame = <client models per frame>}
-- "stress" removes, every frame, the client models it created the frame before, all in view, and removes
-- client-side gibs a quarter second after they appear (the server script breaks props and churns props
-- and doors at the same spot). Each removal frees an entity whose draw the material system's queued render
-- thread may still be running: the RTX fixes before the queued-draws patch called GetModel() through such a
-- freed entity and crashed the game at instruction pointer 0. A checkpoint screenshot every NLQD.shots
-- seconds; NL_SHOT_DONE after NLQD.seconds, unless the game crashed first.
-- "lighting" draws nothing itself: it waits for the server's still scene to settle, then takes three
-- screenshots of it, for a before/after comparison of prop lighting.
-- Prints NLQD lines and paces screenshots with NL_SHOT (answered by the driver with nl_shot_taken <n>).
local function out(...) print("NLQD " .. table.concat({...}, " ")) end

local settings = NLQD or {}
local mode = settings.mode or "stress"
local center = settings.center or LocalPlayer():EyePos() + LocalPlayer():GetAimVector() * 200
local forward = Vector(-1, 0, 0)
if settings.yaw then forward = Angle(0, settings.yaw, 0):Forward() end
local right = Angle(0, (settings.yaw or 180) - 90, 0):Forward()
-- The ground under the scene's centre, as the server script finds it.
local ground = util.TraceLine({start = center + Vector(0, 0, 300), endpos = center - Vector(0, 0, 4000),
                               mask = MASK_SOLID_BRUSHONLY}).HitPos.z
center = Vector(center.x, center.y, ground)

local MODELS = {
    "models/props_junk/watermelon01.mdl",
    "models/hunter/blocks/cube025x025x025.mdl",
    "models/props_c17/oildrum001.mdl",
    "models/props_junk/wood_crate001a.mdl",
    "models/props_c17/door01_left.mdl",
    "models/props_junk/popcan01a.mdl",
}

local made, freed, gibsFreed, frames, printed = 0, 0, 0, 0, 0
local previous = {}
local seen = setmetatable({}, {__mode = "k"})
local started = RealTime()
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Console text of up to `bytes` characters, as the VR probe's base64 packets were: the engine's console buffers
-- come from the same heap as entities, so freed entity memory is reused as it was in the crashed VR sessions.
local function consoleChurn(bytes)
    local length = math.random(math.floor(bytes / 4), bytes)
    local start = math.random(1, #ALPHABET)
    local text = string.rep(ALPHABET:sub(start) .. ALPHABET:sub(1, start - 1), math.ceil(length / #ALPHABET)):sub(1, length)
    print("NLQD_PAD " .. text)
    printed = printed + length
end

local function churn()
    frames = frames + 1
    if (settings.console_churn or 0) > 0 then consoleChurn(settings.console_churn) end
    for _, ent in ipairs(previous) do
        if IsValid(ent) then
            ent:Remove()
            freed = freed + 1
        end
    end
    previous = {}
    for i = 1, settings.per_frame or 0 do
        local ent = ClientsideModel(MODELS[(i + frames) % #MODELS + 1], RENDERGROUP_OPAQUE)
        if IsValid(ent) then
            ent:SetPos(center + forward * math.Rand(-60, 120) + right * math.Rand(-120, 120) + Vector(0, 0, math.Rand(10, 100)))
            ent:SetAngles(AngleRand())
            previous[#previous + 1] = ent
            made = made + 1
        end
    end
    local now = RealTime()
    for _, ent in ipairs(ents.FindByClass("class C_PhysPropClientside")) do
        local first = seen[ent]
        if not first then
            seen[ent] = now
        elseif now - first > 0.25 then
            ent:Remove()
            gibsFreed = gibsFreed + 1
        end
    end
end

local function status(label)
    out(label, "seconds", string.format("%.0f", RealTime() - started), "frames", frames, "client_models", made,
        "freed", freed, "gibs_freed", gibsFreed, "console_bytes", printed,
        "fps", string.format("%.0f", 1 / math.max(FrameTime(), 1e-4)))
end

local stepIndex = 0
local steps = {}
local function nextStep()
    stepIndex = stepIndex + 1
    local step = steps[stepIndex]
    if step then step() end
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, nextStep) end)

if mode == "stress" then
    local seconds = settings.seconds or 600
    local period = settings.shots or 60
    hook.Add("Think", "nlqd_churn", churn)
    local checkpoints = math.max(1, math.floor(seconds / period))
    for n = 1, checkpoints do
        steps[#steps + 1] = function()
            timer.Simple(period, function()
                status("checkpoint")
                print("NL_SHOT stress-" .. n)
            end)
        end
    end
    steps[#steps + 1] = function()
        hook.Remove("Think", "nlqd_churn")
        for _, ent in ipairs(previous) do if IsValid(ent) then ent:Remove() end end
        status("done")
        timer.Simple(1, function() print("NL_SHOT_DONE") end)
    end
    status("start")
    nextStep()
else
    steps = {
        function() timer.Simple(settings.settle or 20, function() out("lighting", "settled") print("NL_SHOT lighting-1") end) end,
        function() timer.Simple(3, function() print("NL_SHOT lighting-2") end) end,
        function() timer.Simple(3, function() print("NL_SHOT lighting-3") end) end,
        function() out("done") timer.Simple(1, function() print("NL_SHOT_DONE") end) end,
    }
    out("lighting", "start")
    nextStep()
end
