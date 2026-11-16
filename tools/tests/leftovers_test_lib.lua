-- Shared by leftovers_harness.lua and leftovers_popup_harness.lua (ADR 0235): JSON as util.TableToJSON and
-- util.JSONToTable read and write it (enough for the companion's tables), and a VGUI stand-in that records the panels a
-- window makes, their text and their click handlers. Load with dofile; see the adjacent .md.
local M = {}

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local named = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return named[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

function M.encode(value)
    local kind = type(value)
    if value == nil then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then return string.format("%.14g", value) end
    if kind == "string" then return encodeString(value) end
    assert(kind == "table", "cannot encode a " .. kind)
    local n = #value
    if n > 0 then
        local parts = {}
        for i = 1, n do parts[i] = M.encode(value[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = encodeString(k) .. ":" .. M.encode(value[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.decode(text)
    if type(text) ~= "string" then return nil end
    local pos = 1
    local function space() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
    local value
    local function utf8(code)
        if code < 0x80 then return string.char(code) end
        if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    local function str()
        pos = pos + 1
        local out = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then error("unterminated string") end
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local e = text:sub(pos + 1, pos + 1)
                local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                if e == "u" then
                    out[#out + 1] = utf8(tonumber(text:sub(pos + 2, pos + 5), 16))
                    pos = pos + 6
                else
                    out[#out + 1] = assert(map[e], "bad escape")
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    function value()
        space()
        local c = text:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            space()
            if text:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                space()
                local k = str()
                space()
                assert(text:sub(pos, pos) == ":", "expected :")
                pos = pos + 1
                t[k] = value()
                space()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return t end
                assert(d == ",", "expected , or }")
            end
        elseif c == "[" then
            pos = pos + 1
            local t = {}
            space()
            if text:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value()
                space()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return t end
                assert(d == ",", "expected , or ]")
            end
        elseif c == '"' then
            return str()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        end
        local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        assert(number and number ~= "", "bad value at " .. pos)
        pos = pos + #number
        return tonumber(number)
    end
    local ok, result = pcall(value)
    if not ok then return nil end
    return result
end

-- A VGUI stand-in: vgui.Create and panel:Add give panels that keep what is set on them. `record.frames` lists the top
-- panels, `record.panels` every panel; a panel's `text`, `font`, `dock`, `children` and `DoClick` can be checked.
function M.fakeVgui()
    local record = { frames = {}, panels = {} }
    local Panel = {}
    Panel.__index = function(self, key)
        if Panel[key] then return Panel[key] end
        return function() end -- any other method: accepted, nothing kept
    end
    local function new(class, parent)
        local panel = setmetatable({ class = class, children = {}, parent = parent, valid = true }, Panel)
        record.panels[#record.panels + 1] = panel
        if parent then parent.children[#parent.children + 1] = panel end
        return panel
    end
    function Panel:Add(class) return new(class, self) end
    function Panel:SetTall(tall) self.tall = tall end
    function Panel:GetTall() return rawget(self, "tall") or 0 end
    function Panel:SetSize(wide, tall) self.wide, self.tall = wide, tall end
    function Panel:GetCanvas() return self end
    function Panel:SetText(text) self.text = text end
    function Panel:GetText() return self.text end
    function Panel:SetFont(font) self.font = font end
    function Panel:Dock(where) self.dock = where end
    function Panel:Remove() self.valid = false end
    function Panel:IsValid() return self.valid end
    function Panel:MakePopup() self.popup = true end
    local vgui = { Create = function(class)
        local frame = new(class)
        record.frames[#record.frames + 1] = frame
        return frame
    end }
    -- Every label's text under a panel, top to bottom.
    function record.texts(panel)
        local out = {}
        local function walk(p)
            local text = rawget(p, "text")
            if p.class == "DLabel" and text then out[#out + 1] = text end
            for _, child in ipairs(p.children) do walk(child) end
        end
        walk(panel)
        return out
    end
    function record.buttons(panel)
        local out = {}
        local function walk(p)
            if p.class == "DButton" then out[#out + 1] = p end
            for _, child in ipairs(p.children) do walk(child) end
        end
        walk(panel)
        return out
    end
    return vgui, record
end

return M
