-- QA probe (release QA's map-glass session): shoot a map window on modern_house the way a player does (real
-- +attack with the 357), then the broken window again, then its pieces on the floor, and count what the player
-- sees of the glass system (G1, glass/addon): the windows it tracks (NLGlass.Client), the window opening, the
-- broken pieces in the client's debris world (NLGlassDebris) and the frames that draw them. G1 keeps no entity
-- for a broken piece, so no entity is counted. Needs sv_cheats 1 (setpos/setang). Prints NL_QA_GLASS lines (one
-- JSON object each) and paces screenshots with NL_SHOT (answered by the session driver with nl_shot_taken <n>).
if NLQAGlassProbe and NLQAGlassProbe.Cancel then NLQAGlassProbe.Cancel() end
local probe = {}
NLQAGlassProbe = probe
local V, D = NLGlass and NLGlass.Client, NLGlassDebris
local F = NLGlass and NLGlass.Fracture
local me = LocalPlayer()
local target, steps, index, finished = nil, {}, 0, false

local function out(step, fields)
    fields = fields or {}
    fields.step = step
    print("NL_QA_GLASS " .. util.TableToJSON(fields))
end
local function round(x) return math.Round(x, 1) end
local function vec(v) return {round(v.x), round(v.y), round(v.z)} end
local function finish(fields)
    if finished then return end
    finished = true
    hook.Remove("PostRender", "nl_qa_glass")
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
probe.Cancel = function() finished = true hook.Remove("PostRender", "nl_qa_glass") end

local function isGlass(ent)
    if not IsValid(ent) or not ent.GetBrushSurfaces then return false end
    local ok, surfaces = pcall(ent.GetBrushSurfaces, ent)
    if not ok or not istable(surfaces) then return false end
    for _, surface in ipairs(surfaces) do
        local material = surface.GetMaterial and surface:GetMaterial()
        local name = material and material.GetName and material:GetName() or ""
        if string.find(string.lower(name), "glass", 1, true) then return true end
    end
    return false
end
local function counters()
    local s = D.Stats()
    return {count = D.Count(), hits = (s.native or {}).ray_hits or 0, splits = s.splits or 0}
end
-- The share of a pane's glass G1 still draws (1 whole, 0 gone); a native window's record goes when it breaks.
local function glassLeft(id)
    local r = V.records[id]
    if not r then return 0 end
    local whole, area = math.abs(F.Area(r.state.def.outline)), 0
    for _, poly in ipairs(F.Remaining(r.state)) do area = area + math.abs(F.Area(poly)) end
    return whole > 0 and area / whole or 0
end
-- Samples every frame in PostRender, after the translucent pass where the debris draws, for `seconds`: the most
-- broken-glass draw calls in one frame and the frames that drew any. From half time on, until it answers, it asks
-- NLGlassDebris.Diagnostics (its read-only QA accessor) where the pieces are: how many lie within 512 units of
-- `center`, and keeps the positions for aiming.
local function watch(seconds, center, done)
    local seen = {frames = 0, drawn = 0, draws = 0}
    local began = RealTime()
    hook.Add("PostRender", "nl_qa_glass", guard(function()
        local s = D.Stats()
        local calls = math.max(s.draw_calls_current or 0, s.draw_calls or 0)
        seen.frames = seen.frames + 1
        if calls > 0 then seen.drawn = seen.drawn + 1 end
        seen.draws = math.max(seen.draws, calls)
        local now = RealTime()
        if center and not seen.read and now >= began + seconds / 2 then
            local rows = D.Diagnostics(256)
            if rows then
                seen.read, seen.near, seen.positions = #rows, 0, {}
                local nearest = math.huge
                for _, row in ipairs(rows) do
                    local p = Vector(row[2][1], row[2][2], row[2][3])
                    seen.positions[#seen.positions + 1] = p
                    local distance = p:Distance(center)
                    if distance <= 512 then seen.near = seen.near + 1 end
                    nearest = math.min(nearest, distance)
                end
                if nearest < math.huge then seen.nearest = round(nearest) end
            end
        end
        if now >= began + seconds then
            hook.Remove("PostRender", "nl_qa_glass")
            done(seen)
        end
    end))
end
local function fire(rounds, done)
    local n = 0
    local function one()
        n = n + 1
        RunConsoleCommand("+attack")
        later(0.15, function()
            RunConsoleCommand("-attack")
            if n < rounds then later(0.9, one) else done() end
        end)
    end
    one()
end
local function aim(eye, point)
    local ang = (point - eye):Angle()
    RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
end

steps[1] = function()
    if not (V and D and D.Stats and D.Diagnostics and F) then out("setup", {g1 = false}) finish() return end
    -- The map's glass windows as the engine has them (func_breakable with a glass brush material), for the
    -- record, and the windows G1 tracks, of which it breaks the nearest upright one.
    local windows = 0
    for _, ent in ipairs(ents.FindByClass("func_breakable")) do if isGlass(ent) then windows = windows + 1 end end
    local tracked, natives, upright = 0, 0, {}
    for id, r in pairs(V.records) do
        tracked = tracked + 1
        if r.native then natives = natives + 1 end
        local ent, normal = V.Entity(r), r.frame.angles:Up()
        if IsValid(ent) and math.abs(normal.z) < 0.3 then
            upright[#upright + 1] = {id = id, ent = ent, center = r.frame.origin, normal = normal, native = r.native}
        end
    end
    local from = me:GetPos()
    table.sort(upright, function(a, b) return a.center:DistToSqr(from) < b.center:DistToSqr(from) end)
    target = upright[1]
    local setup = {g1 = true, windows = windows, tracked = tracked, natives = natives}
    if not target then out("setup", setup) finish() return end
    -- Stand 90 units in front of the window, on the player's side, eye level with its centre.
    local side = (from - target.center):Dot(target.normal) >= 0 and 1 or -1
    target.eye = target.center + target.normal * (90 * side)
    local stand = target.eye - Vector(0, 0, 64)
    RunConsoleCommand("setpos", tostring(stand.x), tostring(stand.y), tostring(stand.z))
    aim(target.eye, target.center)
    RunConsoleCommand("use", "weapon_357")
    -- The debris world imports the map in the background: shoot once it is ready, as a player who has been on
    -- the map a moment, and after the 357's draw animation.
    local waited = 0
    local function ready()
        if D.Backend() ~= "jolt" and waited < 60 then waited = waited + 0.5 later(0.5, ready) return end
        later(2, function()
            setup.target, setup.native, setup.center = target.id, target.native, vec(target.center)
            setup.backend, setup.waited, setup.pieces = D.Backend(), waited, D.Count()
            out("setup", setup)
            print("NL_SHOT before_shot")
        end)
    end
    ready()
end
steps[2] = function()
    local before = counters()
    fire(1, function()
        watch(2.5, target.center, function(seen)
            local left = glassLeft(target.id)
            target.positions = seen.positions
            out("break", {pane_valid = IsValid(target.ent), glass_left = math.Round(left, 3),
                open = not IsValid(target.ent) or left < 0.999, pieces = D.Count() - before.count,
                live = D.Stats().live, backend = D.Backend(), draws = seen.draws, drawn_frames = seen.drawn,
                frames = seen.frames, read = seen.read, near = seen.near, nearest = seen.nearest})
            print("NL_SHOT after_first_shot")
        end)
    end)
end
-- Shoot the broken window again, through where the pane was.
steps[3] = function()
    local before = counters()
    fire(2, function()
        watch(1.5, nil, function(seen)
            local after = counters()
            out("again", {pieces = after.count, ray_hits = after.hits - before.hits, splits = after.splits - before.splits,
                draws = seen.draws})
            print("NL_SHOT after_more_shots")
        end)
    end)
end
-- And the pieces on the floor below the window: the nearest piece lying below eye level, or the floor there.
steps[4] = function()
    local eye = me:EyePos()
    local point = target.center - Vector(0, 0, 60)
    local best = math.huge
    for _, p in ipairs(target.positions or {}) do
        local distance = p:Distance(eye)
        if p.z < eye.z - 24 and distance > 40 and distance < best then point, best = p, distance end
    end
    aim(eye, point)
    local before = counters()
    later(0.5, function()
        fire(3, function()
            watch(1.5, nil, function(seen)
                local after = counters()
                out("floor", {aimed_at_piece = best < math.huge, pieces = after.count, ray_hits = after.hits - before.hits,
                    splits = after.splits - before.splits, draws = seen.draws})
                print("NL_SHOT after_floor_shots")
            end)
        end)
    end)
end
steps[5] = function() finish({pieces = D.Count(), backend = D.Backend()}) end

local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() later(0.5, nextStep) end)
later(1, nextStep)
