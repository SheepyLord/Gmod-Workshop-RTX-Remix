-- Controls consumed by a tool remain consumed until the physical control rearms.
local Controls = {}
local hands = {"left", "right"}
function Controls.New(ctx)
    local self, sticks, triggers = {}, {}, {}
    local function pushed(hand)
        local s = ctx.Input[hand].stick
        return s.x * s.x + s.y * s.y > 0.2 * 0.2
    end
    function self.Stick(hand)
        if pushed(hand) then sticks[hand] = true end
        ctx.Input.Claim(hand, "stick", ctx.name)
    end
    function self.Trigger(hand)
        if ctx.Input[hand].trigger then
            triggers[hand] = true
            ctx.Input.Claim(hand, "trigger", ctx.name)
        end
    end
    function self.Frame()
        for _, hand in ipairs(hands) do
            if sticks[hand] and not pushed(hand) then sticks[hand] = nil end
            if triggers[hand] and not ctx.Input[hand].trigger then triggers[hand] = nil end
            if sticks[hand] then ctx.Input.Claim(hand, "stick", ctx.name) end
            if triggers[hand] then ctx.Input.Claim(hand, "trigger", ctx.name) end
        end
    end
    function self.Move(cmd)
        local mask = 0
        if triggers[ctx.Input.mainHand] then mask = bit.bor(mask, IN_ATTACK) end
        if triggers[ctx.Input.offHand] then mask = bit.bor(mask, IN_ATTACK2) end
        if mask ~= 0 then cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(mask))) end
    end
    function self.Stop() sticks, triggers = {}, {} end
    return self
end
return Controls
