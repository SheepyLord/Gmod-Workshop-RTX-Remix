-- A controller-only fallback when SteamVR cannot open its own keyboard.
local Keyboard = {}
local function key(value, shifted, weight, action) return {value = value, shifted = shifted, weight = weight or 1, action = action} end
local function letters(values)
    local row = {} for i = 1, #values do local c = values:sub(i, i) row[#row + 1] = key(c, c:upper()) end return row
end
function Keyboard.Layout(width, height)
    local rows = {{key("`", "~"), key("1", "!"), key("2", "@"), key("3", "#"), key("4", "$"),
        key("5", "%"), key("6", "^"), key("7", "&"), key("8", "*"), key("9", "("), key("0", ")"),
        key("-", "_"), key("=", "+"), key("Backspace", nil, 2, "backspace")}, letters("qwertyuiop"), letters("asdfghjkl"), letters("zxcvbnm"),
        {key("Close", nil, 2, "close"), key("Home", nil, 1.5, "home"), key("Left", nil, 1.5, "left"),
        key("Space", nil, 6, "space"), key("Right", nil, 1.5, "right"), key("End", nil, 1.5, "end"), key("Delete", nil, 2, "delete")}}
    table.insert(rows[2], 1, key("Tab", nil, 1.5, "tab"))
    for _, k in ipairs({key("[", "{"), key("]", "}"), key("\\", "|")}) do rows[2][#rows[2] + 1] = k end
    table.insert(rows[3], 1, key("Shift", nil, 1.75, "shift"))
    for _, k in ipairs({key(";", ":"), key("'", '"'), key("Enter", nil, 2.25, "enter")}) do rows[3][#rows[3] + 1] = k end
    table.insert(rows[4], 1, key("Shift", nil, 2.25, "shift"))
    for _, k in ipairs({key(",", "<"), key(".", ">"), key("/", "?"), key("Enter", nil, 2.75, "enter")}) do rows[4][#rows[4] + 1] = k end
    local cells, rowHeight = {}, (height - 46) / #rows
    for r, row in ipairs(rows) do
        local total = 0 for _, k in ipairs(row) do total = total + k.weight end
        local x = 6
        for _, k in ipairs(row) do
            local w = (width - 12) * k.weight / total
            k.x, k.y, k.w, k.h = x + 2, 42 + (r - 1) * rowHeight + 2, w - 4, rowHeight - 4
            cells[#cells + 1] = k x = x + w
        end
    end
    return cells
end
function Keyboard.New(ctx, text)
    local self, entry, callback, hover, pressed = {}, nil, nil, nil, nil
    function self.Close()
        if entry then entry.overlay:Destroy() end
        entry, callback, hover, pressed = nil, nil, nil, nil
    end
    function self.Open(owner, fn)
        self.Close()
        local size = assert(ctx.Overlay.Sizes.keyboard, "Missing central keyboard overlay size")
        local parent = owner.overlay
        local metres = math.min(parent.metres, 1.05)
        local pos = parent.pos - parent.ang:Up() * (parent.metres * parent.height / parent.width / 2 + metres * size[2] / size[1] / 2 + 0.025)
        entry = {key = "keyboard", owner = owner, cells = Keyboard.Layout(size[1], size[2]), shift = false}
        callback = fn
        entry.overlay = ctx.Overlay.New{key = "keyboard", name = text("Keyboard"), width = size[1], height = size[2],
            device = parent.device, pos = pos, ang = parent.ang, metres = metres, paint = function(_, w, h)
                surface.SetDrawColor(12, 18, 26, 255) surface.DrawRect(0, 0, w, h)
                draw.SimpleText(text("Keyboard"), "NLVRUITitle", 12, 6, color_white)
                for _, k in ipairs(entry.cells) do
                    local on = k == hover or k.action == "shift" and entry.shift
                    surface.SetDrawColor(on and 65 or 35, on and 108 or 58, on and 132 or 75, 255)
                    surface.DrawRect(k.x, k.y, k.w, k.h)
                    local label = k.action and text(k.value) or entry.shift and k.shifted or k.value
                    draw.SimpleText(label, "NLVRUIKeyboard", k.x + k.w / 2, k.y + (k.h - 18) / 2, color_white, TEXT_ALIGN_CENTER)
                end
            end}
        entry.overlay:SortOrder(30)
        entry.overlay:Show(true)
    end
    function self.IsOpen() return entry ~= nil end
    function self.Owner() return entry and entry.owner end
    function self.Hit(origin, direction)
        if not entry then return end
        local u, v, distance = ctx.Overlay.Hit(entry.overlay, origin, direction)
        if not u then return end
        local x, y = u * entry.overlay.width, v * entry.overlay.height
        local cell
        for _, k in ipairs(entry.cells) do if x >= k.x and x <= k.x + k.w and y >= k.y and y <= k.y + k.h then cell = k break end end
        return {panel = entry, keyboard = true, cell = cell, u = u, v = v, distance = distance}
    end
    function self.Hover(hit)
        local nextHover = hit and hit.keyboard and hit.cell or nil
        if nextHover ~= hover then hover = nextHover if entry then entry.overlay:Invalidate() end end
    end
    function self.Press(hit) pressed = hit.cell end
    function self.Release(hit)
        local k = pressed pressed = nil
        if not entry or not k or not hit or hit.cell ~= k then return end
        if k.action == "shift" then entry.shift = not entry.shift entry.overlay:Invalidate()
        elseif k.action == "close" then local fn = callback self.Close() fn("close")
        else callback(k.action or "char", k.action == "space" and " " or entry.shift and k.shifted or k.value) end
    end
    function self.Inventory()
        if not entry then return end
        entry.debug = entry.debug or {key = entry.key, width = entry.overlay.width, height = entry.overlay.height, handle = entry.overlay.handle}
        entry.debug.handle=entry.overlay.handle
        return entry.debug
    end
    self.Stop = self.Close
    return self
end
return Keyboard
