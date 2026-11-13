-- Appended in the private client's scope; only this test owns these phase commands.
local RID, reviewSeen, reviewLast = "vr_tools_review_client", {}, 0
local function reviewOnce(t, at, key, fn)
    if t >= at and not reviewSeen[key] then reviewSeen[key] = true fn() end
end
local reviewBegin
hook.Add("PreRender", RID, function()
    if attached and not NLVR then hook.Remove("PreRender", RID) hook.Remove("ShutDown", RID) return end
    if not NLVR or not native or not attached then return end
    local test = native.TestState()
    local t = test and test.time or 0
    if CONFIG.tools_linear then
        reviewOnce(t, 8, "zero-linear", function() RunConsoleCommand("nlvr_t_review_linear", "zero") end)
        reviewOnce(t, 14, "com-linear", function() RunConsoleCommand("nlvr_t_review_linear", "com") end)
        reviewOnce(t, 20, "origin-no-use", function() RunConsoleCommand("nlvr_t_review_linear", "origin") end)
        return
    end
    if CONFIG.tools_api then
        reviewOnce(t, 5, "player-api", function() RunConsoleCommand("nlvr_t_review_fault", "player-api") end)
        reviewOnce(t, 10, "entity-api", function() RunConsoleCommand("nlvr_t_review_fault", "entity-api") end)
        return
    end
    if not reviewBegin then
        reviewBegin = native.BeginFrame
        native.BeginFrame = function(...)
            local f, detail = reviewBegin(...)
            local state = native.TestState() local time = state and state.time or 0
            local w = NLVR and NLVR.Debug.tools and NLVR.Debug.tools.wheel
            if f and time > 142.6 and time < 144.15 and w and w.open then
                for i, entry in ipairs(w.entries) do
                    if entry.class == "weapon_crowbar" and i <= 12 then
                        local theta = (i - 1) * math.pi * 2 / math.min(12, #w.entries)
                        f.right.pos = NLVR.ToTracking(w.origin + (w.angle:Right() * math.sin(theta) + w.angle:Up() * math.cos(theta)) * NLVR.Space.scale * 0.14)
                    end
                end
            end
            return f, detail
        end
        local cv = GetConVar("gm_snapangles")
        if cv then saved.gm_snapangles = cv:GetString() RunConsoleCommand("gm_snapangles", "45") end
    end
    reviewOnce(t, 23.7, "button", function() RunConsoleCommand("nlvr_t_review_button", "create") end)
    reviewOnce(t, 25.1, "held-use-check", function() RunConsoleCommand("nlvr_t_review_button", "check") end)
    reviewOnce(t, 25.9, "remove-button", function() RunConsoleCommand("nlvr_t_review_button", "remove") end)
    if t < 60 then return end
    aimWidget, aimProp = nil, false
    for _, phase in ipairs({{60, "snap"}, {70, "freeze-up"}, {80, "release-down"}, {90, "release-diagonal"},
        {100, "tracking"}, {110, "hand"}, {120, "controller"}, {130, "creation"}, {147, "death"}, {152, "stop"}}) do
        reviewOnce(t, phase[1], phase[2], function() RunConsoleCommand("nlvr_t_review_setup", phase[2]) end)
    end
    for _, fault in ipairs({{105, "tracking"}, {125, "controller"}, {131, "creation"}, {149.5, "death"}, {158, "stop"}}) do
        reviewOnce(t, fault[1], fault[2] .. "-fault", function() RunConsoleCommand("nlvr_t_review_fault", fault[2]) end)
    end
    reviewOnce(t, 115, "hand-change", function() NLVR.Net.Send(97, function(n) n.WriteBool(true) end) end)
    reviewOnce(t, 119, "hand-restore", function() NLVR.Net.Send(97, function(n) n.WriteBool(false) end) end)
    reviewOnce(t, 140, "refuse", function() RunConsoleCommand("nlvr_t_review_refuse", "1") end)
    reviewOnce(t, 145.2, "refused-image", function() capture("tools-refused", t) end)
    reviewOnce(t, 146, "refuse-result", function() RunConsoleCommand("nlvr_t_review_refuse", "0") end)
    if RealTime() - reviewLast >= 0.05 then
        reviewLast = RealTime()
        local move = NLVR.Debug.move or {}
        local visibleArc = 0
        for key, object in pairs(NLVR.Overlay.Objects) do
            if object.visible and (key:find("teleport", 1, true) or key:find("move_arc", 1, true)) then visibleArc = visibleArc + 1 end
        end
        emit("review-client", {time = t, stick_owner = NLVR.Input.Owner("right", "stick"),
            trigger_owner = NLVR.Input.Owner("right", "trigger"), arc_visible = visibleArc,
            movement = move, tools = NLVR.Debug.tools})
    end
end)
hook.Add("ShutDown", RID, function() hook.Remove("PreRender", RID) hook.Remove("ShutDown", RID) end)
