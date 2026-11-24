-- QA probe (release QA's spawned-glass session): spawn the glass system's own pane the way the spawn menu does
-- (gm_spawnsent nlglass_annealed_96x64, G1's Glass Rewrite preset, glass/addon), shoot it with the 357 (real
-- +attack) and count what the player sees: the pane G1 tracks and draws (NLGlass.Client), the hole the round
-- leaves, the broken pieces in the client's debris world (NLGlassDebris) and the frames that draw them. G1 keeps
-- no entity for a broken piece, so no entity is counted. Needs sv_cheats 1 (setang). Prints NL_QA_GLASS lines (one
-- JSON object each) and paces screenshots with NL_SHOT (answered by the session driver with nl_shot_taken <n>).
if NLQAGlassProbe and NLQAGlassProbe.Cancel then NLQAGlassProbe.Cancel() end
local probe = {}
NLQAGlassProbe = probe
local PRESET = "nlglass_annealed_96x64"
local V, D = NLGlass and NLGlass.Client, NLGlassDebris
local F = NLGlass and NLGlass.Fracture
local me = LocalPlayer()
local target, steps, index, finished = nil, {}, 0, false
local drawsOf, observed = {}, nil

local function out(step, fields)
    fields = fields or {}
    fields.step = step
    print("NL_QA_GLASS " .. util.TableToJSON(fields))
end
local function round(x) return math.Round(x, 1) end
local function vec(v) return {round(v.x), round(v.y), round(v.z)} end
local function restore()
    hook.Remove("PostRender", "nl_qa_glass")
    -- Hand NLGlass.Client's observation slot back as the probe found it.
    if V and observed and V.Observe == observed.wrapper then V.Observe = observed.previous end
end
local function finish(fields)
    if finished then return end
    finished = true
    restore()
    if NLQAGlassProbe == probe then NLQAGlassProbe = nil end
    out("done", fields)
    print("NL_SHOT_DONE")
end
-- Every callback runs protected: an error ends the probe with an "error" line instead of a Lua error.
local function guard(fn)
    return function(...)
        if finished then return end
        local ok, err = pcall(fn, ...)
        if not ok then out("error", {error = tostring(err)}) finish() end
    end
end
local function later(seconds, fn) timer.Simple(seconds, guard(fn)) end
probe.Cancel = function() finished = true restore() end

-- The share of the pane's glass G1 still draws: 1 whole, 0 gone.
local function glassLeft(id)
    local r = V.records[id]
    if not r then return 0 end
    local whole, area = math.abs(F.Area(r.state.def.outline)), 0
    for _, poly in ipairs(F.Remaining(r.state)) do area = area + math.abs(F.Area(poly)) end
    return whole > 0 and area / whole or 0
end
-- Samples every frame in PostRender, after the translucent pass where panes and debris draw, for `seconds`:
-- the most broken-glass draw calls in one frame and the frames that drew any.
local function watch(seconds, done)
    local seen = {frames = 0, drawn = 0, draws = 0}
    local began = RealTime()
    hook.Add("PostRender", "nl_qa_glass", guard(function()
        local s = D.Stats()
        local calls = math.max(s.draw_calls_current or 0, s.draw_calls or 0)
        seen.frames = seen.frames + 1
        if calls > 0 then seen.drawn = seen.drawn + 1 end
        seen.draws = math.max(seen.draws, calls)
        if RealTime() >= began + seconds then
            hook.Remove("PostRender", "nl_qa_glass")
            done(seen)
        end
    end))
end

steps[1] = function()
    if not (V and D and D.Stats and F) then out("setup", {g1 = false}) finish() return end
    -- Count each pane's draws: NLGlass.Client reports every pane it draws to its Observe slot (unset in play).
    observed = {previous = V.Observe}
    observed.wrapper = function(kind, id, ...)
        if kind == "pane_draw" then drawsOf[id] = (drawsOf[id] or 0) + 1 end
        if observed.previous then return observed.previous(kind, id, ...) end
    end
    V.Observe = observed.wrapper
    local known = {}
    for _, ent in ipairs(ents.FindByClass("nlglass_*")) do known[ent] = true end
    -- Look down at the ground ahead and spawn the preset there, as the spawn menu does at the eye trace.
    RunConsoleCommand("setang", "25", tostring(me:EyeAngles().y), "0")
    later(0.5, function()
        RunConsoleCommand("gm_spawnsent", PRESET)
        local waited = 0
        local function found()
            for _, ent in ipairs(ents.FindByClass(PRESET)) do
                local r = not known[ent] and V.byIndex[ent:EntIndex()]
                if r and V.Entity(r) == ent then return ent, r end
            end
        end
        local function spawned()
            local ent, r = found()
            if not ent and waited < 10 then waited = waited + 0.25 later(0.25, spawned) return end
            local setup = {g1 = true, preset = PRESET, spawned = IsValid(ent)}
            if not ent then out("setup", setup) finish() return end
            target = {ent = ent, id = r.id, center = r.frame.origin}
            setup.tracked, setup.center = true, vec(target.center)
            local ang = (target.center - me:EyePos()):Angle()
            RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
            RunConsoleCommand("use", "weapon_357")
            -- The debris world imports the map in the background: shoot once it is ready, and after the 357's
            -- draw animation.
            local ready = 0
            local function shoot()
                if D.Backend() ~= "jolt" and ready < 60 then ready = ready + 0.5 later(0.5, shoot) return end
                later(1.5, function()
                    -- The pane G1 draws: its record has a mesh (a pane_draw report alone does not say so).
                    local current = V.records[target.id]
                    setup.mesh = current ~= nil and current.mesh ~= nil
                    setup.pane_draws, setup.glass_left = drawsOf[target.id] or 0, math.Round(glassLeft(target.id), 3)
                    setup.backend, setup.waited, setup.pieces = D.Backend(), ready, D.Count()
                    out("setup", setup)
                    print("NL_SHOT before_shot")
                end)
            end
            shoot()
        end
        spawned()
    end)
end
steps[2] = function()
    local before, drawn = D.Count(), drawsOf[target.id] or 0
    RunConsoleCommand("+attack")
    later(0.15, function()
        RunConsoleCommand("-attack")
        watch(2.5, function(seen)
            local left = glassLeft(target.id)
            out("break", {pane_valid = IsValid(target.ent), glass_left = math.Round(left, 3), open = left < 0.999,
                pieces = D.Count() - before, live = D.Stats().live, backend = D.Backend(), draws = seen.draws,
                drawn_frames = seen.drawn, frames = seen.frames, pane_draws = (drawsOf[target.id] or 0) - drawn})
            print("NL_SHOT after_shot")
        end)
    end)
end
steps[3] = function() finish({pieces = D.Count(), backend = D.Backend()}) end

local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() later(0.5, nextStep) end)
later(1, nextStep)
