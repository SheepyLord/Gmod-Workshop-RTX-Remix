-- Runs the companion's real nativeloader_pbr_progress.lua (R23, the user's item 3) against a mocked
-- RTXGamePBRProgress, the shared notice, timers and RealTime. See the adjacent .md.
local root, scenario = ...
local lua = root .. "/companion/nativeloader/lua/"
local now, timers, notices, logs = 0, {}, {}, {}
local pending, total = 0, 0

function RealTime() return now end
function MsgN(text) logs[#logs + 1] = text end
function IsValid(panel) return type(panel) == "table" and not panel.removed end
timer = {
    Create = function(id, delay, reps, fn) timers[id] = { delay = delay, fn = fn, at = now + delay } end,
    Remove = function(id) timers[id] = nil end,
}
local function advance(seconds)
    local target = now + seconds
    while true do
        local due
        for _, t in pairs(timers) do if t.at <= target and (not due or t.at < due.at) then due = t end end
        if not due then break end
        now = due.at
        due.at = now + due.delay
        due.fn()
    end
    now = target
end
function include(path)
    if path == "nativeloader/i18n.lua" then return { L = function(s) return "T:" .. s end } end
    if path == "nativeloader/notice.lua" then
        return { Show = function(text, options)
            local panel = { text = text, progress = options.progress, seconds = options.seconds }
            function panel:SetNoticeText(value) self.text = value end
            function panel:SetNoticeProgress(value) self.progress = value end
            function panel:FinishNotice(after) self.finish = after end
            notices[#notices + 1] = panel
            return panel
        end }
    end
    error("unexpected include " .. path)
end
function RTXGamePBRProgress() return pending, total end
dofile(lua .. "autorun/client/nativeloader_pbr_progress.lua")

if scenario == "quick" then
    -- Restoring saved maps: done within the delay, nothing shown.
    pending, total = 3, 3
    advance(1.0)
    pending, total = 0, 0
    advance(1.0)
    assert(#notices == 0, "no notice for a quick batch")
elseif scenario == "progress" then
    pending, total = 5, 5
    advance(1.6) -- the batch is first seen at the first poll (0.25 s)
    assert(#notices == 0, "not before 1.5 seconds")
    advance(0.25)
    assert(#notices == 1 and notices[1].seconds == 0, "one lasting notice")
    assert(notices[1].text == "T:Preparing PBR materials for imported characters: 0 of 5.", notices[1].text)
    assert(notices[1].progress == 0)
    pending = 2
    advance(0.25)
    assert(notices[1].text:find("3 of 5", 1, true) and math.abs(notices[1].progress - 0.6) < 1e-9)
    pending, total = 0, 0
    advance(0.25)
    assert(notices[1].text == "T:PBR materials for imported characters are ready." and notices[1].progress == 1)
    assert(notices[1].finish == 4, "it goes four seconds later")
    -- A later character: a new batch, a new notice.
    pending, total = 4, 4
    advance(2)
    assert(#notices == 2 and notices[2].text:find("0 of 4", 1, true))
elseif scenario == "closed" then
    pending, total = 6, 6
    advance(2)
    assert(#notices == 1)
    notices[1].removed = true -- the close button
    pending = 4
    advance(3)
    assert(#notices == 1, "a closed notice stays closed for its batch")
    pending, total = 0, 0
    advance(0.5)
    pending, total = 2, 2
    advance(2)
    assert(#notices == 2, "the next batch shows again")
elseif scenario == "absent" then
    RTXGamePBRProgress = nil -- no RTX fixes: nothing
    advance(5)
    RTXGamePBRProgress = function() error("native view failed") end -- a failing count shows nothing
    advance(1)
    assert(#notices == 0 and timers.nativeloader_pbr_progress ~= nil)
    -- A failure of the notice itself stops the poll for good, with one console line.
    RTXGamePBRProgress = function() return 3, 3 end
    include = function() error("no notice module") end
    advance(3)
    assert(#notices == 0 and timers.nativeloader_pbr_progress == nil, "an error stops the poll")
    assert(#logs == 1 and logs[1]:find("PBR progress notice stopped", 1, true))
else
    error("Unknown scenario " .. scenario)
end
print("PASS " .. scenario)
