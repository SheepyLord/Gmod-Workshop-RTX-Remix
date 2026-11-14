-- Offline cases for V6's quality ladder and Auto controller (no engine, no native module).
local root, scenario = ...
local function eq(a, b, what) assert(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function close(a, b, what, tolerance) assert(math.abs(a - b) <= (tolerance or 1e-6), (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
math.Clamp = function(n, low, high) return math.max(low, math.min(high, n)) end
local function load(path) return assert(loadfile(root .. "/vr/addon/lua/" .. path))() end
local Ladder = load("nlvr/modules/cl_perf_ladder.lua")
local Control = load("nlvr/modules/cl_perf_control.lua")
local cases = {}

-- A controller fed a steady rate for `seconds`, sampled every 0.25 s like the module.
local function run(control, from, seconds, rate, gpuMs, budgetMs, target)
    local steps = {}
    local now = from
    while now < from + seconds - 1e-9 do
        now = now + 0.25
        local index, reason = control.Sample(now, rate * 0.25, target or 45, gpuMs, budgetMs or 22.2)
        if reason then steps[#steps + 1] = {now = now, index = index, reason = reason} end
    end
    return steps, now
end

function cases.frame_generation_rates()
    -- V8: with frame generation Auto holds half the refresh (Motion Smoothing makes the rest), without it all of it.
    include = function(path) return load(path) end
    local Perf = load("nlvr/modules/cl_perf.lua")
    local target, budget = Perf.Rates(90, 1) close(target, 45, "half rate") close(budget, 1000 / 45, "half-rate budget")
    target, budget = Perf.Rates(90, 0) close(target, 90, "full rate") close(budget, 1000 / 90, "full-rate budget")
    close(Perf.Rates(120, 1), 60, "120 Hz") close(Perf.Rates(90, nil), 45, "frame generation is on by default")
    close(Perf.Rates(0 / 0, 1), 45, "a broken refresh reads as 90 Hz") close(Perf.Rates(-5, 0), 90) close(Perf.Rates(math.huge, 0), 90)
    -- Compositor_FrameTiming.m_nReprojectionFlags bit 0x08 marks a frame Motion Smoothing made.
    for _, flags in ipairs({8, 9, 12, 0x108, 0x30F}) do eq(Perf.Smoothed(flags), true, "flags " .. flags) end
    for _, flags in ipairs({0, 4, 7, 0x100, 0x200, 0x400, -8}) do eq(Perf.Smoothed(flags), false, "flags " .. flags) end
    eq(Perf.Smoothed(nil), false, "no timing")
end

function cases.ladder_order()
    local n = Ladder.Count()
    assert(n >= 5, "a ladder needs room to move")
    local top = Ladder.Step(1)
    -- The top step is V1's fixed preset, so an untouched session renders as V1 to V4 did.
    eq(top.render_scale, 1) eq(top.dlss, 1) eq(top.min_bounces, 1) eq(top.max_bounces, 4)
    eq(top.volumetrics, true) eq(top.fine_clouds, true)
    for i = 2, n do
        local a, b = Ladder.Step(i - 1), Ladder.Step(i)
        assert(b.render_scale <= a.render_scale, "scale never rises going down, step " .. i)
        assert(b.dlss <= a.dlss, "DLSS quality never rises going down, step " .. i)
        assert(b.max_bounces <= a.max_bounces, "bounces never rise going down, step " .. i)
        assert(not b.volumetrics or a.volumetrics, "volumetrics never come back going down, step " .. i)
        assert(b.render_scale < a.render_scale or b.dlss < a.dlss or b.max_bounces < a.max_bounces or
            b.volumetrics ~= a.volumetrics or b.fine_clouds ~= a.fine_clouds, "every step costs less, step " .. i)
        assert(b.min_bounces <= b.max_bounces, "bounces stay ordered, step " .. i)
        assert(b.render_scale >= 0.25 and b.render_scale <= 1.5, "the runtime accepts step " .. i)
        assert(b.dlss >= 0 and b.dlss <= 3, "the runtime accepts step " .. i .. "'s DLSS mode")
    end
    -- Out-of-range indices clamp to the ends.
    eq(Ladder.Step(0).index, 1) eq(Ladder.Step(99).index, n) eq(Ladder.Step(-3).index, 1)
end

function cases.ladder_ceiling()
    -- The slider is a ceiling only: it lowers a step's scale but never raises it.
    close(Ladder.Step(1, 0.6).render_scale, 0.6, "ceiling lowers the top step")
    close(Ladder.Step(Ladder.Count(), 1.5).render_scale, Ladder.Step(Ladder.Count()).render_scale, "ceiling never raises")
    close(Ladder.Step(1, 0.1).render_scale, 0.25, "the ceiling itself is clamped to the runtime's floor")
    close(Ladder.Step(1, 0 / 0).render_scale, 1, "a broken slider value is ignored")
end

function cases.ladder_start()
    local n = Ladder.Count()
    -- V1 capped low-tier and sub-12 GB cards at a 0.5 scale; Auto starts them at the floor.
    eq(Ladder.Start("low", 24576), n) eq(Ladder.Start("high", 8192), n) eq(Ladder.Start("high", 12287), n)
    close(Ladder.Step(Ladder.Start("low", nil)).render_scale, 0.5, "the floor keeps V1's 0.5 cap")
    eq(Ladder.Start("medium", 24576), 3) eq(Ladder.Start("high", 12288), 3) eq(Ladder.Start("high", 16383), 3)
    eq(Ladder.Start("high", 16384), 1) eq(Ladder.Start("high", 32768), 1)
    -- Nothing known: the top step, as V1.
    eq(Ladder.Start(nil, nil), 1) eq(Ladder.Start(nil, 0), 1)
end

function cases.control_down()
    local c = Control.New{steps = 7}
    c.Begin(1, 0)
    -- 30 frames a second against a 45 target: down after two missed windows, past the cool-down.
    local steps = run(c, 0, 2.75, 30)
    eq(#steps, 0, "no step inside the cool-down, though two windows missed")
    steps = run(c, 2.75, 2.0, 30)
    eq(#steps, 1, "one step once the cool-down ends") eq(steps[1].index, 2) eq(steps[1].reason, "down")
    close(steps[1].now, 3.0, "the step lands as the cool-down ends")
end

function cases.control_cooldown()
    -- A sustained miss steps once per cool-down, never twice in a row.
    local c = Control.New{steps = 7}
    c.Begin(1, 0)
    local steps = run(c, 0, 12, 20)
    assert(#steps >= 2, "keeps stepping while frames are missed")
    for i = 2, #steps do
        assert(steps[i].now - steps[i - 1].now >= c.cooldown - 1e-9, "steps closer than the cool-down")
        eq(steps[i].index, steps[i - 1].index + 1, "one rung per step")
    end
    -- The mutant without a cool-down steps every second window: the check above would catch it.
    local mutant = Control.New{steps = 7, cooldown = 0}
    mutant.Begin(1, 0)
    local fast = run(mutant, 0, 12, 20)
    local caught = false
    for i = 2, #fast do if fast[i].now - fast[i - 1].now < c.cooldown then caught = true end end
    assert(caught, "a controller without a cool-down must fail the cool-down check")
end

function cases.control_up()
    local c = Control.New{steps = 7}
    c.Begin(4, 0)
    -- On target with GPU headroom: up one rung after eight settled windows and the cool-down.
    local steps = run(c, 0, 12, 45, 10)
    assert(#steps >= 1, "climbs with headroom") eq(steps[1].index, 3) eq(steps[1].reason, "up")
    assert(steps[1].now >= 8 - 1e-9, "only after eight settled windows")
    -- On target but the GPU near its budget: never up, never down.
    local tight = Control.New{steps = 7}
    tight.Begin(4, 0)
    eq(#run(tight, 0, 30, 45, 20), 0, "no climb without headroom")
end

function cases.control_bounds()
    local c = Control.New{steps = 7}
    c.Begin(7, 0)
    eq(#run(c, 0, 20, 10), 0, "no step below the floor")
    local top = Control.New{steps = 7}
    top.Begin(1, 0)
    eq(#run(top, 0, 40, 45, 5), 0, "no step above the top")
    eq(c.Begin(99, 0), 7, "Begin clamps high") eq(c.Begin(-1, 0), 1, "Begin clamps low")
end

function cases.control_no_oscillation()
    -- A rate that wavers across the target, missing every other window with the GPU busy, must not walk the
    -- ladder up and down: no two misses and no eight settled windows in a row.
    local c = Control.New{steps = 7}
    c.Begin(3, 0)
    local now, moves = 0, 0
    for window = 1, 60 do
        local rate = (window % 2 == 0) and 42 or 46
        local steps
        steps, now = run(c, now, 1.0, rate, 16)
        moves = moves + #steps
    end
    eq(moves, 0, "a rate wavering across the target stays put")
end

function cases.control_half_rate()
    -- SteamVR's half-rate lock on the Index reads 44.1 to 45.1 frames a second against 45: with the GPU's work
    -- at 12 ms of 22.2 that is settled, and Auto climbs. At a 0.99 keep ratio it never would.
    local c = Control.New{steps = 7}
    c.Begin(3, 0)
    local rates, now, steps = {44.1, 45.0, 44.2, 45.1}, 0, {}
    for window = 1, 12 do
        local s
        s, now = run(c, now, 1.0, rates[(window - 1) % #rates + 1], 12)
        for _, step in ipairs(s) do steps[#steps + 1] = step end
    end
    assert(#steps >= 1 and steps[1].reason == "up" and steps[1].index == 2, "the half-rate lock settles and Auto climbs")
    local strict = Control.New{steps = 7, keepRatio = 0.99}
    strict.Begin(3, 0)
    now = 0
    local moved = 0
    for window = 1, 12 do
        local s
        s, now = run(strict, now, 1.0, rates[(window - 1) % #rates + 1], 12)
        moved = moved + #s
    end
    eq(moved, 0, "a 0.99 keep ratio never settles at the lock, which is why it is 0.97")
end

function cases.control_cpu_bound()
    -- Frames missed while the GPU has room: the game lost them, so a cheaper step would not help.
    local c = Control.New{steps = 7}
    c.Begin(1, 0)
    eq(#run(c, 0, 20, 30, 8), 0, "no step down while the GPU is not the cause")
    eq(c.cpuLimited, true, "the controller says why it holds")
    -- The same misses with the GPU over its share of the budget step down.
    local g = Control.New{steps = 7}
    g.Begin(1, 0)
    local steps = run(g, 0, 5, 30, 20)
    eq(#steps, 1, "a GPU-bound miss steps down") eq(steps[1].reason, "down")
    eq(g.cpuLimited, false, "a GPU-bound miss is not reported as the game's")
    -- A mutant that ignores the GPU walks down: the hold check above must catch it.
    local mutant = Control.New{steps = 7, gpuBound = 0}
    mutant.Begin(1, 0)
    assert(#run(mutant, 0, 20, 30, 8) > 0, "a controller that ignores the GPU must fail the hold check")
end

function cases.control_window()
    -- Frames are counted over the whole window: a burst then nothing averages, it does not trigger.
    local c = Control.New{steps = 7}
    c.Begin(1, 0)
    local index, reason = c.Sample(0.25, 45, 45, nil, 22.2)
    eq(reason, nil) eq(index, 1)
    for t = 0.5, 1.0, 0.25 do index, reason = c.Sample(t, 0, 45, nil, 22.2) end
    close(c.rate, 45, "a one-second window averages its frames")
end

local fn = cases[scenario]
assert(fn, "unknown scenario " .. tostring(scenario))
fn()
print("PASS " .. scenario)
