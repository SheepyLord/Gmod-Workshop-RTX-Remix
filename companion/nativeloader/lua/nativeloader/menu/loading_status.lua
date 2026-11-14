-- What the game is doing while a map loads (R24, ADR 0134). The RTX client module runs this companion menu script
-- once in the menu realm of an RTX start (as multiplayer_notice.lua). It loads the engine guard module there (its
-- gmsv_ copy: the guard against material fallback loops is then in place before any map) and drives the guard's
-- load overlay from the menu's loading screen: the menu's Think sees IsInLoading() become true (the overlay starts),
-- passes the stock status line (GetLoadStatus()) on, and sees it end. GameDetails names the map. The overlay's own
-- thread adds the Lua file running and the game file being read.
-- ADR 0214: after the engine's load ("Ready to play!") the overlay stays until the game runs steadily (the menu's
-- Think sees two seconds of frames without a freeze), saying what the main thread is doing. ADR 0215: it counts down
-- to the end of the wait expected from the loads before, kept in data/nativeloader/load_times.txt through the module
-- (the menu realm cannot write files). Documented in loading_status.lua.md.
if not MENU_DLL or NativeLoaderLoadStatus then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

local TEXT = {
    loading = N"Loading…",
    loadingMap = N"Loading %s",
    joining = N"Joining %s",
    file = N"File",
    answered = N"%s file lookups answered from memory",
    -- After the engine's load, and what the main thread is doing (ADR 0214).
    settling = N"The map has loaded; the game is starting",
    remix = N"RTX Remix is preparing the scene",
    scripts = N"Running add-on scripts",
    spawnmenu = N"Building the spawn menu",
    files = N"Loading game files",
    workshopBusy = N"Workshop: updating add-ons",
    workshopFetch = N"Workshop: fetching subscriptions (%s of %s)",
    workshopDownload = N"Workshop: downloading add-ons (%s of %s)",
    workshopExtract = N"Workshop: extracting %s",
    -- The estimate (ADR 0215).
    secondsLeft = N"about %s s left",
    minutesLeft = N"about %s min left",
    secondsRough = N"about %s s left (rough estimate)",
    minutesRough = N"about %s min left (rough estimate)",
    longer = N"Taking longer than usual",
    learning = N"No estimate yet: this load is timed for the next one",
}

local enabled
do
    local ok, convar = pcall(CreateConVar, "nativeloader_load_overlay", "1", FCVAR_ARCHIVE,
        "Show what the game is doing while a map loads (RTX sessions)")
    enabled = ok and convar or nil
end
local function on()
    return not enabled or enabled:GetBool()
end

local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
local catalog
-- The companion's language setting is a client convar the menu realm cannot see: the companion keeps a copy for the
-- menu in data/nativeloader_companion/language.txt (nativeloader/i18n.lua).
local function chosenLanguage()
    local chosen = GetConVar("nativeloader_language")
    if chosen then return chosen:GetString() end
    local saved = file and isfunction(file.Read) and file.Read("nativeloader_companion/language.txt", "DATA")
    return isstring(saved) and #saved <= 16 and saved:match("^[%w%-]+$") and saved or ""
end
local function L(text)
    local code = chosenLanguage()
    if code == "" then
        local gmod = GetConVar("gmod_language")
        code = gmod and gmod:GetString() or "en"
    end
    code = ALIASES[string.lower(code)] or code
    if code == "en" or code == "" then return text end
    if catalog == nil then
        catalog = false
        local source = read and read("nativeloader/nativeloader/i18n_data.lua")
        if isstring(source) then
            -- The menu realm has no CompileString (PoC, R24), only RunString: through a global taken at once.
            if isfunction(CompileString) then
                local chunk = CompileString(source, "nativeloader/i18n_data.lua", false)
                local ok, data = false, nil
                if isfunction(chunk) then ok, data = pcall(chunk) end
                catalog = ok and istable(data) and data or false
            elseif isfunction(RunString) then
                local key = "__NATIVELOADER_I18N_DATA"
                rawset(_G, key, nil)
                pcall(RunString, key .. " = (function()\n" .. source .. "\nend)()", "nativeloader/i18n_data.lua", false)
                local data = rawget(_G, key)
                rawset(_G, key, nil)
                catalog = istable(data) and data or false
            end
        end
    end
    local phrases = catalog and catalog[code]
    local translated = istable(phrases) and phrases[text]
    return isstring(translated) and translated ~= "" and translated or text
end
local function format(template, value)
    local ok, text = pcall(string.format, L(template), value)
    return ok and text or string.format(template, value)
end
local function format2(template, first, second)
    local ok, text = pcall(string.format, L(template), first, second)
    return ok and text or string.format(template, first, second)
end

-- ---------------------------------------------------------------- The estimate (ADR 0215)
-- One record per load the overlay followed to its end: when (t), the map, the server of a joined game, whether it was
-- joined, the first load of this game start, the add-ons mounted, the map's size, the engine's load in seconds
-- (load), the wait after it until the game ran steadily (after) and whether that wait hit the time-out (capped).
-- Pure functions: the harness tests them directly (NativeLoaderLoadStatus.Eta).
local Eta = {
    VERSION = "1",
    MAX_RECORDS = 200, -- the file stays near 20 KB, far below the module's 64 KiB
    PER_KEY = 10,      -- per map (and server)
    SAME_MAP = 5,      -- the newest loads of a map that make its estimate
    OTHER_MAPS = 12,   -- the maps that make the machine's estimate for a map not loaded before
    -- A load's fixed part, in add-ons' worth: with 772 add-ons a load took 17-28 s here and a bare game a few seconds
    -- (RESEARCH, R24 and R26), so a count from 774 to 900 makes a load about an eighth longer.
    ADDON_BASE = 150,
    MB = 1048576,
}

function Eta.median(list)
    local n = #list
    if n == 0 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = list[i] end
    table.sort(sorted)
    if n % 2 == 1 then return sorted[(n + 1) / 2] end
    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

function Eta.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- At most `limit` bytes of UTF-8 text, never cut inside a character.
function Eta.clip(text, limit)
    if #text <= limit then return text end
    local cut = limit
    while cut > 0 do
        local nextByte = text:byte(cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end

-- A map name as the history keeps it ("" for a name it does not keep: no path, no control characters).
function Eta.cleanMap(name)
    if not isstring(name) then return "" end
    name = string.lower(name)
    if #name > 64 or not name:match("^[%w_%-%.%+]+$") or name:find("..", 1, true) then return "" end
    return name
end

-- A server's name as the history keeps it: one line without tabs, at most 64 bytes.
function Eta.cleanServer(name)
    if not isstring(name) then return "" end
    name = name:gsub("[%z\1-\31\127]", " ")
    name = name:match("^%s*(.-)%s*$") or ""
    return Eta.clip(name, 64)
end

local function keyOf(record)
    if record.joined then return "j\t" .. (record.server or "") .. "\t" .. (record.map or "") end
    return "l\t" .. (record.map or "")
end
Eta.keyOf = keyOf

local function newestFirst(a, b)
    if a.t ~= b.t then return a.t > b.t end
    return (a.n or 0) > (b.n or 0)
end

local function fields(line)
    local out = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = field end
    return out
end

-- The history file's text -> records, oldest first. Lines it does not read are left out, and numbers out of any real
-- range (a hand-edited "1e300") are not kept: every kept one prints back with "%d".
local HUGE = 2 ^ 40 -- seconds since 1970 or bytes of a map: far above any real one
function Eta.parse(text)
    local records = {}
    if not isstring(text) then return records end
    for line in text:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local f = fields(line)
            local t, flags, addons, size = tonumber(f[2]), f[3], tonumber(f[4]), tonumber(f[5])
            local load, after, map = tonumber(f[6]), tonumber(f[7]), Eta.cleanMap(f[8])
            if f[1] == Eta.VERSION and t and t >= 0 and t < HUGE and isstring(flags) and load and after and load >= 0
                and after >= 0 and load <= 3600 and after <= 3600 and map ~= "" then
                local joined = flags:find("j", 1, true) ~= nil
                records[#records + 1] = {
                    n = #records + 1, t = t, map = map, server = joined and Eta.cleanServer(f[9]) or "",
                    joined = joined, first = flags:find("f", 1, true) ~= nil, capped = flags:find("c", 1, true) ~= nil,
                    addons = addons and addons >= 0 and addons < 1000000 and math.floor(addons) or nil,
                    size = size and size > 0 and size < HUGE and size or nil, load = load, after = after,
                }
            end
        end
    end
    return records
end

function Eta.serialize(records)
    local lines = {
        "# Map load times of this game (the RTX package's load overlay, ADR 0215); one load a line, newest last.",
        "# version, time, flags (f first load of a game start, j a server joined, c never ran steadily), "
            .. "add-ons mounted, map bytes, load seconds, seconds until the game ran steadily, map, server",
    }
    for _, r in ipairs(records) do
        local flags = (r.first and "f" or "") .. (r.joined and "j" or "") .. (r.capped and "c" or "")
        lines[#lines + 1] = table.concat({
            Eta.VERSION, string.format("%d", math.floor(r.t)), flags ~= "" and flags or "-",
            r.addons and string.format("%d", math.floor(r.addons)) or "-",
            string.format("%d", math.floor(r.size or 0)),
            string.format("%.2f", r.load), string.format("%.2f", r.after), r.map, r.joined and (r.server or "") or "",
        }, "\t")
    end
    return table.concat(lines, "\n") .. "\n"
end

-- The history with `record` added, oldest first: at most PER_KEY loads per map (and server) and MAX_RECORDS in all,
-- the newest kept.
function Eta.add(records, record)
    local all, highest = {}, 0
    for _, r in ipairs(records) do
        all[#all + 1] = r
        highest = math.max(highest, r.n or 0)
    end
    record.n = highest + 1
    all[#all + 1] = record
    table.sort(all, newestFirst)
    local kept, perKey = {}, {}
    for _, r in ipairs(all) do
        local key = keyOf(r)
        perKey[key] = (perKey[key] or 0) + 1
        if perKey[key] <= Eta.PER_KEY and #kept < Eta.MAX_RECORDS then kept[#kept + 1] = r end
    end
    local out = {}
    for i = #kept, 1, -1 do out[#out + 1] = kept[i] end
    return out
end

-- How a record's durations scale to another add-on count: the load grows with the add-ons mounted, plus a fixed part.
function Eta.addonScale(from, to)
    if not from or not to then return 1 end
    return Eta.clamp((Eta.ADDON_BASE + to) / (Eta.ADDON_BASE + from), 0.5, 2)
end

-- The machine's own ratio of a game start's first load to a later one: from maps loaded both ways, else from all.
function Eta.firstFactor(pool, addons)
    local byKey, ratios, firsts, laters = {}, {}, {}, {}
    for _, r in ipairs(pool) do
        local total = (r.load + r.after) * Eta.addonScale(r.addons, addons)
        local key = keyOf(r)
        local entry = byKey[key] or { first = {}, later = {} }
        byKey[key] = entry
        local list, all = r.first and entry.first or entry.later, r.first and firsts or laters
        list[#list + 1] = total
        all[#all + 1] = total
    end
    for _, entry in pairs(byKey) do
        local later = Eta.median(entry.later)
        if #entry.first > 0 and later and later > 0 then ratios[#ratios + 1] = Eta.median(entry.first) / later end
    end
    local ratio = Eta.median(ratios)
    local later = Eta.median(laters)
    if not ratio and #firsts >= 2 and #laters >= 2 and later > 0 then ratio = Eta.median(firsts) / later end
    return ratio and Eta.clamp(ratio, 0.75, 3) or nil
end

-- Per-map points -> a value for a map of `size` bytes: their median, or with three maps of known sizes a line through
-- them (Theil-Sen: the median of the pairs' slopes, never negative, at most 0.5 s a megabyte).
function Eta.sizeFit(points, field, size)
    local values = {}
    for _, p in ipairs(points) do values[#values + 1] = p[field] end
    local base = Eta.median(values)
    if not base or not size or size <= 0 then return base end
    local sized = {}
    for _, p in ipairs(points) do if p.size and p.size > 0 then sized[#sized + 1] = p end end
    if #sized < 3 then return base end
    local slopes = {}
    for i = 1, #sized do
        for j = i + 1, #sized do
            local dx = (sized[j].size - sized[i].size) / Eta.MB
            if math.abs(dx) >= 1 then slopes[#slopes + 1] = (sized[j][field] - sized[i][field]) / dx end
        end
    end
    if #slopes < 2 then return base end
    local slope = Eta.clamp(Eta.median(slopes), 0, 0.5)
    local intercepts = {}
    for _, p in ipairs(sized) do intercepts[#intercepts + 1] = p[field] - slope * p.size / Eta.MB end
    return math.max(0, Eta.median(intercepts) + slope * size / Eta.MB)
end

local function result(load, after, confidence, basis, count)
    load, after = Eta.clamp(load, 1, 900), Eta.clamp(after, 0, 600)
    return { load = load, after = after, total = load + after, confidence = confidence, basis = basis, count = count }
end

-- The estimate for a load of `q` ({map, server, joined, first, addons, size}) from `records`:
-- {load, after, total, confidence = "good"|"rough", basis = "map"|"machine", count}, or nil without a load to learn
-- from. Only loads of the same kind count (a server joined, or a game started here). The map's own newest loads
-- decide when it has any (their median, each scaled to today's add-on count and first-load state); "good" takes two
-- of them that agree within 60 % without scaling much. Else the machine's other maps, one point per map, fitted to
-- the map's size when there are enough sizes: "rough".
function Eta.estimate(records, q)
    local pool = {}
    for _, r in ipairs(records or {}) do
        if (r.joined == true) == (q.joined == true) then pool[#pool + 1] = r end
    end
    if #pool == 0 then return nil end
    table.sort(pool, newestFirst)
    local factor = Eta.firstFactor(pool, q.addons)
    -- A record scaled to the query; `far` when that took a guess: the add-on count changed by more than 15 %, or a
    -- first load is told from later ones (or the other way round) without a factor learned here.
    local function scaled(r)
        local addons = Eta.addonScale(r.addons, q.addons)
        local s = addons
        local other = (r.first == true) ~= (q.first == true)
        if factor and other then s = s * (q.first and factor or 1 / factor) end
        return r.load * s, r.after * s, math.abs(addons - 1) > 0.15 or (other and not factor)
    end
    local map = q.map and Eta.cleanMap(q.map) or ""
    if map ~= "" then
        local key = keyOf({ joined = q.joined, server = q.server, map = map })
        local loads, afters, totals, steady = {}, {}, {}, true
        for _, r in ipairs(pool) do
            if #loads < Eta.SAME_MAP and keyOf(r) == key then
                local l, a, far = scaled(r)
                loads[#loads + 1], afters[#afters + 1], totals[#totals + 1] = l, a, l + a
                if far then steady = false end
            end
        end
        if #loads > 0 then
            local low, high = math.huge, 0
            for _, t in ipairs(totals) do low, high = math.min(low, t), math.max(high, t) end
            local good = #loads >= 2 and steady and high <= 1.6 * low
            return result(Eta.median(loads), Eta.median(afters), good and "good" or "rough", "map", #loads)
        end
    end
    local maps, order = {}, {}
    for _, r in ipairs(pool) do
        local key = keyOf(r)
        local m = maps[key]
        if not m and #order < Eta.OTHER_MAPS then
            m = { loads = {}, afters = {}, size = r.size }
            maps[key] = m
            order[#order + 1] = key
        end
        if m and #m.loads < Eta.SAME_MAP then
            local l, a = scaled(r)
            m.loads[#m.loads + 1], m.afters[#m.afters + 1] = l, a
        end
    end
    local points = {}
    for _, key in ipairs(order) do
        local m = maps[key]
        points[#points + 1] = { load = Eta.median(m.loads), after = Eta.median(m.afters), size = m.size }
    end
    return result(Eta.sizeFit(points, "load", q.size), Eta.sizeFit(points, "after", q.size), "rough", "machine", #points)
end

-- ---------------------------------------------------------------- Following a load

-- The engine guard module, loaded now: its guard then covers every map load of this start.
local guard
do
    local ok, err = pcall(require, "nlengineguard")
    local module = rawget(_G, "nlengineguard")
    if ok and istable(module) and isfunction(module.LoadStart) then
        guard = module
    else
        MsgN("[nativeloader] load overlay unavailable: " .. tostring(ok and "no overlay in the engine guard module" or err))
    end
end

NativeLoaderLoadStatus = { loads = 0, Eta = Eta }
local answeredAtStart = 0 -- the load accelerator's count when this load began (R26, load_accel.lua)

-- The history the estimate learns from (ADR 0215), read once: this menu state lives as long as the game.
local history = {}
if guard and isfunction(guard.LoadTimes) then
    local ok, text = pcall(guard.LoadTimes)
    if ok then history = Eta.parse(text) end
end
NativeLoaderLoadStatus.history = history
local function save()
    if not guard or not isfunction(guard.LoadTimesSave) then return end
    local made, text = pcall(Eta.serialize, history)
    local ok, saved = false, false
    if made then ok, saved = pcall(guard.LoadTimesSave, text) end
    if not ok or saved ~= true then MsgN("[nativeloader] load overlay: the load times could not be saved") end
end

-- What the load accelerator has answered: its counters are the process's (every realm adds to them).
local function accelStatus()
    local accel = NativeLoaderLoadAccel
    if not istable(accel) or not isfunction(accel.Status) then return nil end
    local ok, status = pcall(accel.Status)
    return ok and istable(status) and status or nil
end
local function comma(number)
    local text = tostring(math.floor(number))
    return isfunction(string.Comma) and string.Comma(text) or text
end
local heading, headingAt = nil, 0 -- from GameDetails, which may come just before the load is seen
local details = nil -- the map and server GameDetails named, with the heading
local hosted = false -- this load starts its own server here (a single-player game or a listen server)

-- The add-ons mounted and a map's size: what makes a load longer besides the map itself.
local function addonCount()
    if not istable(engine) or not isfunction(engine.GetAddons) then return nil end
    local ok, addons = pcall(engine.GetAddons)
    if not ok or not istable(addons) then return nil end
    local count = 0
    for _, addon in ipairs(addons) do
        if istable(addon) and addon.mounted then count = count + 1 end
    end
    return count
end
local function mapSize(map)
    if not isstring(map) or map == "" or not istable(file) or not isfunction(file.Size) then return nil end
    local ok, size = pcall(file.Size, "maps/" .. map .. ".bsp", "GAME")
    return ok and isnumber(size) and size > 0 and size or nil
end
local function playingDemo()
    return istable(engine) and isfunction(engine.IsPlayingDemo) and engine.IsPlayingDemo() == true
end
local function inGame()
    return not isfunction(IsInGame) or IsInGame() == true
end

local phase = nil  -- nil, "loading" (the engine's load) or "settling" (after it, until the game runs steadily)
local current = nil -- the load followed: {began, first, addons, map, server, joined, size, loaded, forecast}
local settle = nil  -- the frames seen while settling: {began, last, steady, gaps}
local lastStatus = nil
local seen, wasLoading = 0, false -- loads seen in this game start, the overlay on or not
-- A frame gap longer than this is a freeze (three times the usual frame, at least a quarter and at most a whole
-- second); the game runs steadily after STEADY seconds without one; SETTLE_LIMIT ends the wait whatever happens;
-- a load that ends without a game for CONFIRM seconds was cancelled or refused.
local HITCH, HITCH_MAX, STEADY, SETTLE_LIMIT, CONFIRM = 0.25, 1.0, 2, 120, 1

-- The Workshop's own work, from the menu's hooks (lua/menu/mount/mount.lua has GMod's): fetching the subscriptions,
-- downloading, extracting. Named on the status line while the overlay is up (ADR 0214); the overlay does not wait
-- for it, the game plays meanwhile. A word older than ten seconds is dropped (the end may not be announced).
local workshop = nil -- {text, at}
local function workshopText()
    if not workshop or SysTime() - workshop.at > 10 then return nil end
    return workshop.text
end
local function sawWorkshop(text)
    workshop = { text = text, at = SysTime() }
end

-- The status line: `base` and, while the Workshop works, what it does; sent when it changes.
local function sendStatus(base)
    local status = base or ""
    local text = workshopText()
    if text then status = (status ~= "" and (status .. "  ·  ") or "") .. text end
    if status ~= "" and status ~= lastStatus then
        lastStatus = status
        pcall(guard.LoadStatus, status)
    end
end

local function labels()
    return {
        lua = "Lua", file = L(TEXT.file),
        remix = L(TEXT.remix), scripts = L(TEXT.scripts), spawnmenu = L(TEXT.spawnmenu), files = L(TEXT.files),
        secondsLeft = L(TEXT.secondsLeft), minutesLeft = L(TEXT.minutesLeft),
        secondsRough = L(TEXT.secondsRough), minutesRough = L(TEXT.minutesRough),
        longer = L(TEXT.longer), learning = L(TEXT.learning),
    }
end

-- The estimate for the load followed, passed to the overlay as the whole wait's expected length from its start.
local function expectNow()
    if not current or not isfunction(guard.LoadExpect) then return end
    local estimate = Eta.estimate(history, current)
    NativeLoaderLoadStatus.estimate = estimate
    if not estimate then
        pcall(guard.LoadExpect, 0, 0)
        return
    end
    local total = (phase == "settling" and current.loaded or estimate.load) + estimate.after
    if phase ~= "settling" then current.forecast = total end
    pcall(guard.LoadExpect, total, estimate.confidence == "good" and 2 or 1)
end

local function applyDetails(named)
    if not current or not named then return false end
    local server = named.joined and named.server or ""
    if current.map == named.map and current.joined == named.joined and current.server == server then return false end
    current.map, current.joined, current.server = named.map, named.joined, server
    current.size = mapSize(named.map)
    return true
end

-- The console's English line at the end (it goes into bug reports). `ending`: settled (the game ran steadily),
-- capped (SETTLE_LIMIT), left (the game ended while settling), next (another load began), cancelled (the load ended
-- without a game), loaded (a module without the phase after the load: the R24 summary).
local function report(summary, load, after, ending)
    if not istable(summary) or not isnumber(summary.seconds) or summary.seconds < 2 then return end
    local parts = {}
    for _, item in ipairs(istable(summary.lua) and summary.lua or {}) do
        if istable(item) and isstring(item.name) and isnumber(item.seconds) and item.seconds >= 0.5 then
            parts[#parts + 1] = string.format("%s (%.1f s)", item.name, item.seconds)
        end
    end
    local busy = {}
    local activity = istable(summary.activity) and summary.activity or {}
    for _, item in ipairs({ { "scripts", "Lua" }, { "spawnmenu", "the spawn menu" }, { "files", "game files" },
        { "remix", "RTX Remix" } }) do
        local seconds = tonumber(activity[item[1]])
        if seconds and seconds >= 0.5 then busy[#busy + 1] = string.format("%s %.1f s", item[2], seconds) end
    end
    local timing
    if (ending == "settled" or ending == "capped") and load and load.loaded then
        timing = string.format("map loaded in %.1f s, then %.1f s %s (%.1f s in all%s)", load.loaded, after,
            ending == "capped" and "without the game running steadily" or "until the game ran steadily",
            load.loaded + after, load.forecast and string.format("; expected about %.0f s", load.forecast) or "")
    elseif ending == "cancelled" then
        timing = string.format("the map load ended without a game after %.1f s",
            load and load.loaded or summary.seconds)
    elseif load and load.loaded then
        timing = string.format("map loaded in %.1f s; %s %.1f s later", load.loaded,
            ending == "next" and "the next load began" or "the game ended", after)
    else
        timing = string.format("map loaded in %.1f s", summary.seconds)
    end
    local accel = accelStatus()
    local answered = accel and tonumber(accel.answered) and (accel.answered - answeredAtStart) or 0
    MsgN("[nativeloader] " .. timing ..
        (#busy > 0 and ("; the main thread: " .. table.concat(busy, ", ")) or "") ..
        (#parts > 0 and ("; Lua files that ran longest: " .. table.concat(parts, ", ")) or "") ..
        (answered > 0 and ("; the load accelerator answered " .. comma(answered) .. " file lookups from memory") or ""))
    NativeLoaderLoadStatus.last = summary
end

-- The overlay ends (see report() for `ending`). A load that reached the game and was timed to its end, steadily or
-- at the time-out, is added to the history.
local function finish(ending, now)
    local load = current
    phase, current, settle, hosted = nil, nil, nil, false
    local ok, summary = pcall(guard.LoadEnd)
    local after = load and load.loaded and math.max(0, now - load.began - load.loaded) or 0
    local timed = ending == "settled" or ending == "capped"
    if timed and load and load.loaded and load.map and load.map ~= "" and not playingDemo() then
        history = Eta.add(history, {
            t = os.time(), map = load.map, server = load.server or "", joined = load.joined == true,
            first = load.first == true, addons = load.addons, size = load.size or mapSize(load.map),
            load = load.loaded, after = after, capped = ending == "capped",
        })
        NativeLoaderLoadStatus.history = history
        save()
    end
    if ok then report(summary, load, after, ending) end
end

local function begin()
    phase, lastStatus, settle = "loading", nil, nil
    local accel = accelStatus()
    answeredAtStart = accel and tonumber(accel.answered) or 0
    NativeLoaderLoadStatus.loads = NativeLoaderLoadStatus.loads + 1
    local fresh = heading ~= nil and SysTime() - headingAt < 10
    if not fresh then hosted, details = false, nil end
    current = { began = SysTime(), first = seen == 1, addons = addonCount(), joined = false, server = "" }
    if fresh then applyDetails(details) end
    pcall(guard.LoadStart, fresh and heading or L(TEXT.loading), labels())
    expectNow()
end

-- The game is there after the engine's load: the overlay says so and waits for steady frames (ADR 0214).
local function confirm(now)
    if settle.confirmed or not inGame() then return false end
    settle.confirmed, settle.steady, settle.text = true, now, L(TEXT.settling)
    pcall(guard.LoadSettling)
    sendStatus(settle.text)
    expectNow()
    return true
end

-- The engine's load ended. With a game to play, the overlay stays until it runs steadily (ADR 0214); a load that ends
-- without a game within CONFIRM seconds (cancelled or refused) ends the overlay, as does a module without that phase.
local function loaded(now)
    if not current then
        phase = nil
        return
    end
    if not isfunction(guard.LoadSettling) then
        finish("loaded", now)
        return
    end
    current.loaded = now - current.began
    phase = "settling"
    settle = { began = now, last = now, steady = now, gaps = {}, confirmed = false }
    confirm(now)
end

-- Each frame while settling: a gap between two of the menu's Thinks longer than the usual frame is a freeze.
local function watch(now)
    local gap = now - settle.last
    settle.last = now
    local gaps = settle.gaps
    gaps[#gaps + 1] = gap
    if #gaps > 16 then table.remove(gaps, 1) end
    local limit = Eta.clamp(3 * (Eta.median(gaps) or 0), HITCH, HITCH_MAX)
    if gap > limit then settle.steady = now end
    if not settle.confirmed then
        if not confirm(now) then
            if now - settle.began >= CONFIRM then finish("cancelled", now) end
            return
        end
    elseif not inGame() then
        finish("left", now)
        return
    end
    sendStatus(settle.text)
    if now - settle.steady >= STEADY then
        finish("settled", now)
    elseif now - settle.began >= SETTLE_LIMIT then
        finish("capped", now)
    end
end

-- The menu's Think runs whenever the engine draws a frame, during a load too (between its blocking phases) and in a
-- game: the overlay's own thread carries the window through the blocking phases.
if guard and isfunction(IsInLoading) then
    hook.Add("Think", "NativeLoaderLoadStatus", function()
        local now = SysTime()
        local inLoading = IsInLoading() == true
        if inLoading and not wasLoading then seen = seen + 1 end
        wasLoading = inLoading
        if phase == "settling" then
            if not inLoading then
                watch(now)
                return
            end
            finish("next", now) -- the next load began before this one settled: not timed
        end
        if inLoading and not phase then
            if not on() then return end
            begin()
        elseif phase == "loading" and not inLoading then
            loaded(now)
            return
        end
        if phase == "loading" and isfunction(GetLoadStatus) then
            local status = GetLoadStatus()
            if isstring(status) then
                status = string.Trim(status)
                -- What the load accelerator answered in this load so far, after the stock status.
                local accel = status ~= "" and accelStatus() or nil
                local answered = accel and tonumber(accel.answered) and (accel.answered - answeredAtStart) or 0
                if answered >= 1 then status = status .. "  ·  " .. format(TEXT.answered, comma(answered)) end
                sendStatus(status)
            end
        end
    end)

    -- The Workshop's work (see workshopText); each of these returns nothing, so GMod's own hooks still run.
    hook.Add("WorkshopStart", "NativeLoaderLoadStatus", function()
        sawWorkshop(L(TEXT.workshopBusy))
    end)
    hook.Add("WorkshopEnd", "NativeLoaderLoadStatus", function()
        workshop = nil
    end)
    hook.Add("WorkshopSubscriptionsProgress", "NativeLoaderLoadStatus", function(current, total)
        current, total = tonumber(current), tonumber(total)
        if current and total then sawWorkshop(format2(TEXT.workshopFetch, comma(current), comma(total))) end
    end)
    hook.Add("WorkshopDownloadTotals", "NativeLoaderLoadStatus", function(remaining, total)
        remaining, total = tonumber(remaining), tonumber(total)
        if remaining and total and remaining < total then
            sawWorkshop(format2(TEXT.workshopDownload, comma(total - remaining), comma(total)))
        end
    end)
    hook.Add("WorkshopExtractProgress", "NativeLoaderLoadStatus", function(_, _, title)
        if isstring(title) and title ~= "" then sawWorkshop(format(TEXT.workshopExtract, Eta.clip(title, 80))) end
    end)
end

if guard and isfunction(GameDetails) then
    local nativeGameDetails = GameDetails
    function GameDetails(servername, serverurl, mapname, maxplayers, ...)
        if isstring(mapname) and mapname ~= "" then
            -- A game started here is loaded, not joined: the engine also names its own server ("My Garry's Mod
            -- Server") later in the load, when IsHostingGame() can read false (the PoC, R24). The loading panel's
            -- call while hosting, and a single-player game's, pass one player.
            if (isfunction(IsHostingGame) and IsHostingGame()) or tonumber(maxplayers) == 1 then hosted = true end
            heading, headingAt = format(TEXT.loadingMap, mapname), SysTime()
            if not hosted and isstring(servername) and servername ~= "" then
                heading = format(TEXT.joining, servername) .. " · " .. mapname
            end
            details = { map = Eta.cleanMap(mapname), server = Eta.cleanServer(servername), joined = not hosted }
            if phase == "loading" then
                pcall(guard.LoadHeading, heading)
                -- The map is known now: the estimate becomes this map's (ADR 0215).
                if applyDetails(details) then expectNow() end
            end
        end
        return nativeGameDetails(servername, serverurl, mapname, maxplayers, ...)
    end
end
