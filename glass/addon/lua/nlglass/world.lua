-- MIT. Native-world bootstrap. Included by debris.lua; no autorun or server dependency.
local W = { state = "new", api = nil, reason = nil, skipped = 0 }
local notices = NLGlass or {} -- persists across add-on refreshes in the same map realm
local function fail(reason)
    if reason == "expanded BSP collision data limit" then reason = "expanded map collision exceeds 256 MiB" end
    W.state, W.reason = "failed", tostring(reason or ""):match("[^\r\n]+") or "unknown import failure"
    if W.api then pcall(W.api.Shutdown) end
    local map = tostring(game.GetMap())
    if notices.fallbackMap ~= map then
        notices.fallbackMap = map
        MsgN("[NLGlass] Broken glass uses simpler physics on this map (" .. W.reason .. ").")
    end
end
W.Fail = fail
local function must(value, reason)
    if value == nil or value == false then error(reason or "native call failed", 0) end
    return value
end
W.Must = must

local function beginMap(api, path)
    local bsp = file.Open(path, "rb", "GAME")
    if not bsp then error("cannot open the map in GAME", 0) end
    local ok, reason = pcall(function()
        local size = bsp:Size()
        if not size or size < 1036 then error("missing or incomplete BSP header", 0) end
        if api.BeginLoadMapFile then
            must(api.BeginLoadMapFile(size, function(offset, length)
                bsp:Seek(offset)
                if bsp:Tell() == offset then return bsp:Read(length) end
            end))
        else
            -- The updated add-on can arrive one start before its DLL. Honour that DLL's input limit.
            if size > 256 * 1024 * 1024 then error("the glass module for maps over 256 MiB will load when you restart the game", 0) end
            local bytes = bsp:Read(size)
            if type(bytes) ~= "string" or #bytes ~= size then error("cannot read the map in GAME", 0) end
            must(api.BeginLoadMap(bytes))
        end
    end)
    bsp:Close()
    if not ok then error(reason, 0) end
end

local function collision(model)
    local ent = ClientsideModel(model, RENDERGROUP_OTHER)
    if not IsValid(ent) then return nil end
    -- Always remove our temporary model, including after a malformed engine collision mesh.
    local ok, result = pcall(function()
        ent:SetNoDraw(true)
        ent:PhysicsInit(SOLID_VPHYSICS)
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then return nil end
        local mesh = phys:GetMeshConvexes()
        if type(mesh) ~= "table" or #mesh == 0 or #mesh > 128 then return nil end
        local convexes = {}
        for _, convex in ipairs(mesh) do
            local points, seen = {}, {}
            for _, vertex in ipairs(convex) do
                local p = vertex.pos
                if not isvector(p) then return nil end
                local key = string.format("%.5f/%.5f/%.5f", p.x, p.y, p.z)
                if not seen[key] then points[#points + 1], seen[key] = p, true end
                if #points > 256 then return nil end
            end
            if #points < 4 then return nil end
            convexes[#convexes + 1] = points
        end
        return convexes
    end)
    ent:Remove()
    return ok and result or nil
end

function W.Begin(budget, gravity)
    if W.state ~= "new" then return end
    W.state = "loading"
    local ok, reason = pcall(function()
        local module = require("nlglass")
        W.api = type(module) == "table" and module or nlglass
        if type(W.api) ~= "table" or type(W.api.Init) ~= "function" then error("module missing", 0) end
        must(W.api.Init(budget, gravity))
        local map = game.GetMap()
        if type(map) ~= "string" or not map:match("^[%w_/%-]+$") or map:find("..", 1, true) then error("invalid map name", 0) end
        beginMap(W.api, "maps/" .. map .. ".bsp")
        W.task = coroutine.create(function()
            local props, err
            repeat
                props, err = W.api.PollLoadMap()
                if props == nil then error(err or "map import failed", 0) end
                if props == false then coroutine.yield() end
            until props ~= false
            local models = {}
            for _, prop in ipairs(props) do models[prop.model] = false end
            local n = 0
            for model in pairs(models) do
                local convexes = collision(model)
                if convexes then
                    local added = W.api.AddModel(model, convexes)
                    models[model] = added == true
                    if not added then W.skipped = W.skipped + 1 end
                else W.skipped = W.skipped + 1 end
                n = n + 1
                if n % 2 == 0 then coroutine.yield() end
            end
            for i, prop in ipairs(props) do
                if models[prop.model] then W.api.AddProp(prop.model, prop.position, prop.angles, prop.scale) end
                if i % 64 == 0 then coroutine.yield() end
            end
            must(W.api.BeginFinishWorld())
            local done, reason
            repeat
                done, reason = W.api.PollFinishWorld()
                if done == nil then error(reason or "world finish failed", 0) end
                if not done then coroutine.yield() end
            until done
            W.state = "ready"
        end)
    end)
    if not ok then fail(reason) end
end

function W.Tick()
    if W.state == "loading" and W.task then
        local ok, reason = coroutine.resume(W.task)
        if not ok then W.task = nil; fail(reason)
        elseif coroutine.status(W.task) == "dead" then W.task = nil end
    end
end
function W.Shutdown()
    W.task = nil
    if W.api then pcall(W.api.Shutdown) end
    W.state = "new"
end
return W
