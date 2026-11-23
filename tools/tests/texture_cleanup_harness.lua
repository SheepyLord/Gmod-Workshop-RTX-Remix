-- ADR 0261: the RTX fixes' map-exit cleanup hook (RTXTextureCleanup_MapExit in the packaged cl_rtx.lua) under LuaJIT.
-- The hook's own text is cut from the file and run with stand-ins for hook.Add, print, ErrorNoHalt, GetConVar
-- ("mat_queue_mode"), the engine guard's RunQueuedRenderCalls and the binary module's RTX_CleanupMapTextures, one
-- scenario per run.
-- Usage: luajit texture_cleanup_harness.lua <cl_rtx.lua> <scenario>
local path, scenario = arg[1], arg[2]
assert(path and scenario, "usage: texture_cleanup_harness.lua <cl_rtx.lua> <scenario>")

local input = assert(io.open(path, "rb"))
local source = input:read("*a"):gsub("\r\n", "\n")
input:close()
local start = assert(source:find('hook.Add("ShutDown", "RTXTextureCleanup_MapExit", function()', 1, true),
    "the cleanup hook was not found in cl_rtx.lua")
local finish = assert(source:find("\nend)\n", start, true), "the cleanup hook's end was not found")
local chunk = source:sub(start, finish + 4)

local calls, lines, errors = {}, {}, {}
-- mat_queue_mode: 0 (single-threaded) only in the scenarios that say so; 2 (queued) otherwise.
local queueMode = (scenario == "no-guard-single" or scenario == "no-function-single") and 0 or 2
local hooks = {}
local env = {
    hook = { Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end },
    print = function(text) lines[#lines + 1] = text end,
    ErrorNoHalt = function(text) errors[#errors + 1] = text end,
    istable = function(value) return type(value) == "table" end,
    isfunction = function(value) return type(value) == "function" end,
    tostring = tostring, tonumber = tonumber, pcall = pcall, rawget = rawget, type = type,
    GetConVar = function(name)
        assert(name == "mat_queue_mode", name)
        return { GetInt = function() return queueMode end, GetString = function() return tostring(queueMode) end }
    end,
    RTX_CleanupMapTextures = function()
        calls[#calls + 1] = "cleanup"
        return true
    end,
}
env._G = env

local guards = {
    ["no-guard"] = nil,
    ["no-guard-single"] = nil,
    ["no-function"] = {},
    ["no-function-single"] = {},
    ["nothing-queued"] = { RunQueuedRenderCalls = function()
        calls[#calls + 1] = "flush"
        return true, 0, "nothing queued: this thread does not record into a queued context"
    end },
    ["flushed"] = { RunQueuedRenderCalls = function()
        calls[#calls + 1] = "flush"
        return true, 12, "ran 12 queued render call(s) through the queued context's flush"
    end },
    ["refused"] = { RunQueuedRenderCalls = function()
        calls[#calls + 1] = "flush"
        return false, 0, "the queue flush is off: test"
    end },
    ["refused-silent"] = { RunQueuedRenderCalls = function()
        calls[#calls + 1] = "flush"
        return false
    end },
    ["error"] = { RunQueuedRenderCalls = function()
        calls[#calls + 1] = "flush"
        error("boom")
    end },
}
assert(guards[scenario] ~= nil or scenario == "no-guard" or scenario == "no-guard-single",
    "unknown scenario " .. scenario)
env.nlengineguard = guards[scenario]

setfenv(assert(loadstring(chunk, "@cl_rtx-cleanup-hook")), env)()
local hook = assert(hooks["ShutDown/RTXTextureCleanup_MapExit"], "the hook was not added")
hook()

local function joined(list) return table.concat(list, ",") end
local function has(pattern)
    for _, line in ipairs(lines) do
        if line:find(pattern) then return true end
    end
    return false
end

if scenario == "no-guard" or scenario == "no-function" then
    -- Fails closed: queued rendering on and no way to run the queued calls first.
    assert(joined(calls) == "", "the cleanup is skipped: " .. joined(calls))
    assert(has("^%[RTX Texture Cleanup%] Map%-exit purge skipped: the engine guard cannot run the queued render "
        .. "calls first and queued rendering is on %(mat_queue_mode 2%)$"), joined(lines))
elseif scenario == "no-guard-single" or scenario == "no-function-single" then
    assert(joined(calls) == "cleanup", joined(calls))
    assert(not has("skipped"), "nothing is queued with mat_queue_mode 0")
elseif scenario == "nothing-queued" then
    assert(joined(calls) == "flush,cleanup", joined(calls))
    assert(not has("^%[RTX Texture Cleanup%] Ran"), "no count line when nothing ran")
elseif scenario == "flushed" then
    assert(joined(calls) == "flush,cleanup", joined(calls))
    assert(has("^%[RTX Texture Cleanup%] Ran 12 queued render calls before the purge$"), joined(lines))
elseif scenario == "refused" then
    assert(joined(calls) == "flush", "the cleanup is skipped: " .. joined(calls))
    assert(has("^%[RTX Texture Cleanup%] Map%-exit purge skipped: .*%(the queue flush is off: test%)$"), joined(lines))
elseif scenario == "refused-silent" then
    assert(joined(calls) == "flush", "the cleanup is skipped: " .. joined(calls))
    assert(has("^%[RTX Texture Cleanup%] Map%-exit purge skipped: .*%(no reason given%)$"), joined(lines))
elseif scenario == "error" then
    assert(joined(calls) == "flush", "the cleanup is skipped: " .. joined(calls))
    assert(has("^%[RTX Texture Cleanup%] Map%-exit purge skipped: .*boom"), joined(lines))
end
assert(#errors == 0, joined(errors))
print("PASS " .. scenario)
