local Input = {}
-- Logical roles, never physical left/right. SteamVR still owns physical rebinding.
Input.Mapping = {
    off = {grip = {"grab", "gloves"}, trigger = {"use", "laser", "off_action"}, stick = {"move"},
        stick_click = {"sprint"}, a = {"jump"}, b = {"wrist_menu"}},
    main = {grip = {"grab", "gloves"}, trigger = {"fire", "tool_primary", "use", "laser"},
        stick = {"turn", "teleport", "crouch"}, stick_click = {"flashlight"},
        a = {"eject", "tool_secondary", "physgun_freeze"}, b = {"tool_reload", "weapon_wheel"}},
}
Input.Buttons = {"grip", "trigger", "stick_click", "a", "b"}
local function axis(value, low, high)
    return type(value) == "number" and value == value and math.Clamp(value, low, high) or 0
end
function Input.New()
    local self = {left = {}, right = {}, claims = {left = {}, right = {}}, Mapping = Input.Mapping, Buttons = Input.Buttons}
    local since, taps = {left = {}, right = {}}, {left = {}, right = {}}
    function self.Resolve(hand)
        if hand == "main" then return self.mainHand end
        if hand == "off" then return self.offHand end
        if hand == self.left then return "left" end
        if hand == self.right then return "right" end
        assert(hand == "left" or hand == "right", "Unknown VR hand")
        return hand
    end
    function self.Mirror(leftDominant)
        self.mainHand, self.offHand = leftDominant and "left" or "right", leftDominant and "right" or "left"
        self.main, self.off = self[self.mainHand], self[self.offHand]
    end
    function self.Update(actions, now, leftDominant)
        self.claims = {left = {}, right = {}}
        for _, hand in ipairs({"left", "right"}) do
            local state = self[hand]
            state.pressed, state.released, state.held = {}, {}, {}
            taps[hand] = {}
            for _, control in ipairs(Input.Buttons) do
                local a = actions[hand .. "_" .. control] or {}
                local down = a.active == true and a.state == true
                local previous = state[control] == true
                state[control], state.pressed[control], state.released[control] = down, down and not previous, previous and not down
                if down and not previous then since[hand][control] = now end
                local elapsed = since[hand][control] and math.max(0, now - since[hand][control]) or 0
                state.held[control] = elapsed
                taps[hand][control] = previous and not down and elapsed <= 0.3
                if not down then since[hand][control] = nil end
            end
            for _, control in ipairs({"grip_force", "trigger_value"}) do
                local a = actions[hand .. "_" .. control] or {}
                state[control] = a.active and axis(a.x, 0, 1) or 0
            end
            local stick, skeleton = actions[hand .. "_stick"] or {}, actions[hand .. "_skeleton"] or {}
            state.stick = {x = stick.active and axis(stick.x, -1, 1) or 0, y = stick.active and axis(stick.y, -1, 1) or 0}
            state.curls, state.splay = {}, {}
            for i = 1, 5 do state.curls[i] = skeleton.active and axis((skeleton.curls or {})[i], 0, 1) or 0 end
            for i = 1, 4 do state.splay[i] = skeleton.active and axis((skeleton.splay or {})[i], 0, 1) or 0 end
        end
        self.Mirror(leftDominant)
    end
    function self.Owner(hand, control) return self.claims[self.Resolve(hand)][control] end
    function self.Claim(hand, control, owner)
        assert(type(owner) == "string" and owner ~= "", "Input claim needs an owner")
        local claims = self.claims[self.Resolve(hand)]
        if claims[control] and claims[control] ~= owner then return false end
        claims[control] = owner
        return true
    end
    function self.Tapped(hand, control) return taps[self.Resolve(hand)][control] == true end
    function self.Held(hand, control, seconds)
        local state = self[self.Resolve(hand)]
        return state[control] == true and (state.held[control] or 0) >= seconds
    end
    self.Mirror(false)
    return self
end
return Input
