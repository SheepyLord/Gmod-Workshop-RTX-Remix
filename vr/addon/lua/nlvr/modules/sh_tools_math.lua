-- Pure geometry and bounded selection rules, shared with the offline probe.
local M = {PAGE_SIZE = 12, DEAD_ZONE = 0.03, PAGE_EDGE = 0.24}
function M.Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function M.Wrap(n) return (n + 180) % 360 - 180 end
function M.AngleError(a, b)
    local trace = a:Forward():Dot(b:Forward()) + a:Right():Dot(b:Right()) + a:Up():Dot(b:Up())
    return math.deg(math.acos(math.Clamp((trace - 1) / 2, -1, 1)))
end
function M.Relative(prop, hand)
    local _, relative = WorldToLocal(Vector(), prop, Vector(), hand)
    return relative
end
function M.Follow(relative, hand)
    local _, world = LocalToWorld(Vector(), relative, Vector(), hand)
    return world
end
function M.Entries(weapons, describe)
    local result, seen = {}, {}
    for _, weapon in ipairs(weapons) do
        local row = describe(weapon)
        if row and not seen[row.class] then
            seen[row.class] = true result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if a.class == b.class then return false end
        if a.class == "nlvr_hands" or b.class == "nlvr_hands" then return a.class == "nlvr_hands" end
        if a.slot ~= b.slot then return a.slot < b.slot end
        if a.position ~= b.position then return a.position < b.position end
        return a.class < b.class
    end)
    return result
end
function M.Layout(count, page)
    local pages = math.max(1, math.ceil(count / M.PAGE_SIZE))
    page = math.Clamp(page or 1, 1, pages)
    local first = (page - 1) * M.PAGE_SIZE + 1
    local n, rows = math.min(M.PAGE_SIZE, count - first + 1), {}
    for i = 1, n do
        local angle = (i - 1) * math.pi * 2 / n
        rows[i] = {index = first + i - 1, x = math.sin(angle), y = math.cos(angle)}
    end
    return rows, pages, page
end
function M.Pick(count, page, x, y)
    if not M.Finite(x) or not M.Finite(y) or x * x + y * y < M.DEAD_ZONE ^ 2 then return end
    local rows = M.Layout(count, page)
    local best, score
    for _, row in ipairs(rows) do
        local dot = x * row.x + y * row.y
        if not score or dot > score then best, score = row.index, dot end
    end
    return best
end
function M.Page(page, pages, x, y, latched)
    -- Beyond the ring, up/down advances a page once; return to the ring to rearm.
    if math.abs(y) < 0.18 then latched = false end
    if pages > 1 and not latched and math.abs(y) > M.PAGE_EDGE and math.abs(x) < 0.1 then
        return (page - 1 + (y > 0 and 1 or -1)) % pages + 1, true, true
    end
    return page, latched, false
end
function M.DistanceCommand(axis, dt, carry)
    if not M.Finite(axis) or not M.Finite(dt) or dt <= 0 then return 0, carry or 0 end
    if math.abs(axis) <= 0.2 then return 0, 0 end
    axis = (axis > 0 and 1 or -1) * (math.min(1, math.abs(axis)) - 0.2) / 0.8
    dt = math.min(dt, 0.1)
    local value = (carry or 0) + axis * dt
    if value >= dt - 0.000000001 then return 1, value - dt end
    if value <= -dt + 0.000000001 then return -1, value + dt end
    return 0, value
end
function M.ToolInfo(mode, tool, stage, operation, phrase)
    phrase = phrase or function(s) return s end
    local function word(key)
        local text = phrase(key:gsub("^#", ""))
        return text
    end
    local result = {mode = mode, name = word(tool.Name or ("tool." .. mode .. ".name")), lines = {}}
    local grouped = {left = {}, right = {}, reload = {}}
    for _, info in ipairs(tool.Information or {}) do
        if type(info) == "string" then info = {name = info} end
        if info.name and (info.stage == nil or info.stage == stage) and (info.op == nil or info.op == operation) then
            for _, key in ipairs({"left", "right", "reload"}) do
                if info.name:sub(1, #key) == key and not info.name:find("_use", 1, true) then
                    grouped[key][#grouped[key] + 1] = word("tool." .. mode .. "." .. info.name)
                end
            end
        end
    end
    for i, key in ipairs({"left", "right", "reload"}) do
        local fallback = "tool." .. mode .. "." .. key
        local text = #grouped[key] > 0 and table.concat(grouped[key], " / ") or word(fallback)
        if text == fallback then text = "-" end
        result.lines[i] = ({"Trigger", "A", "B"})[i] .. ": " .. text
    end
    return result, mode .. "\n" .. result.name .. "\n" .. table.concat(result.lines, "\n")
end
function M.Snap(angle, step)
    step = M.Finite(step) and math.Clamp(step, 5, 90) or 45
    local function snap(n)
        n = (n + 180) % 360 - 180
        local k = n / step
        return (k >= 0 and math.floor(k + 0.5) or math.ceil(k - 0.5)) * step
    end
    return Angle(snap(angle.p), snap(angle.y), snap(angle.r))
end
return M
