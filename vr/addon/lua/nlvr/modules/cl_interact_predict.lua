-- Held props drawn where the hands hold them now (V8, ADR 0203). The server's physics state reaches the
-- client a few ticks after the hand moved; a one-body prop that follows its hold is drawn at the hold's pose
-- from this frame's hands. Ragdolls, bodies held back by something and released bodies are drawn where the
-- physics has them. Every switch between the two blends over BLEND seconds, so a throw never jumps back.
local G = include("nlvr/modules/sh_grab_math.lua")
local Predict = {BLEND = 0.12, STALE = 0.4}
function Predict.New(ctx)
    local self, records = {}, {}
    local function anchor(hand)
        local state = ctx.Hand[hand]
        local shown = state and state.shown
        if not shown or not shown.valid or not shown.pos or not shown.ang then return end
        return {pos = shown.pos, ang = shown.ang}
    end
    local function held(record)
        if record.two then
            local a, b = anchor("left"), anchor("right")
            if a and b then return G.TwoHand(record.two, a, b) end
            return
        end
        local a = record.rel and anchor(record.hand)
        if a then return G.OneHand(record.rel, a) end
    end
    local function restore(ent, record)
        if IsValid(ent) and ent.RenderOverride == record.override then ent.RenderOverride = record.own end
        records[ent] = nil
    end
    -- The pose to draw this frame, or nil to leave the entity alone.
    function self.Pose(ent, now)
        local record = records[ent]
        if not record then return end
        local follow = record.follow and now - record.received <= Predict.STALE
        local mode, pos, ang = "physics"
        if follow then
            pos, ang = held(record)
            if pos then mode = "held" end
        end
        if not pos then pos, ang = ent:GetPos(), ent:GetAngles() end
        if record.mode ~= mode and record.last then
            record.offset = {pos = record.last.pos - pos, turn = G.RotationError(ang, record.last.ang), at = now}
        end
        record.mode = mode
        local offset = record.offset
        local k = offset and math.max(0, 1 - (now - offset.at) / Predict.BLEND) or 0
        if offset and k > 0 then pos, ang = G.Blend(pos, ang, offset.pos, offset.turn, k) else record.offset = nil end
        record.last = {pos = pos, ang = ang}
        return pos, ang, mode, record
    end
    local function attach(ent)
        local record = {own = rawget(ent:GetTable(), "RenderOverride"), original = ent.RenderOverride, received = RealTime()}
        record.override = function(target, flags)
            local pos, ang, mode, current = self.Pose(target, RealTime())
            if pos then
                target:SetRenderOrigin(pos) target:SetRenderAngles(ang) target:SetupBones()
            end
            if record.original then record.original(target, flags) else target:DrawModel(flags) end
            if pos then target:SetRenderOrigin() target:SetRenderAngles() end
            -- A released body that has blended back to its physics pose is left to the engine again.
            if current and not current.holding and mode == "physics" and not current.offset then restore(target, current) end
        end
        ent.RenderOverride = record.override
        records[ent] = record
        return record
    end
    -- states: the interact module's per-hand server states (cl_interact.lua); pair: the two-hand frame or nil.
    function self.Update(states, pair, now)
        local holds = {}
        for _, hand in ipairs({"left", "right"}) do
            local s = states[hand]
            if s and s.holding and s.single and IsValid(s.ent) and s.ent:GetClass() ~= "prop_ragdoll" then
                local entry = holds[s.ent] or {}
                entry[hand] = s holds[s.ent] = entry
            end
        end
        for ent, entry in pairs(holds) do
            local record = records[ent] or attach(ent)
            record.holding, record.received = true, now
            if entry.left and entry.right and pair then
                record.two, record.hand, record.rel = pair, nil, nil
                record.follow = entry.left.tracking == true
            else
                local hand = entry.left and "left" or "right"
                record.two, record.hand, record.rel = nil, hand, entry[hand].rel
                record.follow = entry[hand].tracking == true
            end
        end
        for ent, record in pairs(records) do
            if not holds[ent] then
                record.holding, record.follow = false, false
                if not IsValid(ent) then records[ent] = nil end
            end
        end
    end
    function self.Debug(ent)
        local record = records[ent]
        return record and {mode = record.mode, follow = record.follow == true, blending = record.offset ~= nil,
            drawn = record.last and record.last.pos} or nil
    end
    function self.Stop()
        for ent, record in pairs(records) do restore(ent, record) end
    end
    return self
end
return Predict
