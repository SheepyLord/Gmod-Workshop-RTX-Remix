-- shadow_copies_server.lua: the server half of shadow_copies_session.py, run once from the session's data folder
-- (lua_run RunString). It names every entity that answers GetModelScale with nothing (the Model Hotloader's scene
-- capture compares that answer with a number), spawns the PoC library's first imported character on request, and
-- writes what it saw for the run. See shadow_copies_server.lua.md.
local meta = FindMetaTable("Entity")
local getScale = meta.GetModelScale
local asked, askedKeys, present = {}, {}, {}

-- Every caller asks through the Entity metatable, so this sees the scene capture's question too, with its caller.
meta.GetModelScale = function(self, ...)
    local scale = getScale(self, ...)
    if scale == nil and IsValid(self) then
        local key = self:GetClass() .. " " .. tostring(self:GetModel())
        if not askedKeys[key] then
            askedKeys[key] = true
            asked[#asked + 1] = { class = self:GetClass(), model = tostring(self:GetModel()), index = self:EntIndex(),
                time = math.Round(CurTime(), 1), caller = debug.traceback("", 2) }
            print("NLSH_NILSCALE " .. key)
        end
    end
    return scale
end

-- And every entity with a model and no model scale, whoever asks: its first time and the most at once.
local function scan()
    local counts = {}
    for _, ent in ipairs(ents.GetAll()) do
        local model = ent:GetModel()
        if model and model ~= "" and getScale(ent) == nil then
            local key = ent:GetClass() .. " " .. model
            counts[key] = (counts[key] or 0) + 1
        end
    end
    for key, count in pairs(counts) do
        local entry = present[key]
        if not entry then
            entry = { first = math.Round(CurTime(), 1), most = 0 }
            present[key] = entry
        end
        entry.most = math.max(entry.most, count)
    end
end
scan()
timer.Create("NLShadow.Scan", 2, 0, scan)

local function host(ply)
    return game.SinglePlayer() or (IsValid(ply) and ply:IsListenServerHost())
end

local function first_asset()
    local _, dirs = file.Find("mmd_hotloader/assets/*", "DATA")
    table.sort(dirs or {})
    return dirs and dirs[1] or nil
end

-- An imported character as an NPC in front of the player: the Model Hotloader's scene capture then classifies
-- what is near it every tick.
concommand.Add("nlshadow_character", function(ply)
    if not host(ply) or not IsValid(ply) then return end
    local asset = first_asset()
    if not (asset and mmdhl and mmdhl.SpawnNPC) then print("NLSH_CHARACTER none") return end
    game.ConsoleCommand("ai_disabled 1\n")
    local yaw = ply:EyeAngles().y
    local pos = ply:GetPos() + Angle(0, yaw, 0):Forward() * 140
    mmdhl.SpawnNPC(ply, asset, "citizen", { position = { pos.x, pos.y, pos.z }, weapon = "none" }, function(ent, err)
        if IsValid(ent) then ent:SetAngles(Angle(0, yaw + 180, 0)) end
        print("NLSH_CHARACTER " .. (IsValid(ent) and ent:GetClass() or tostring(err)))
    end)
end)

-- A weapon in the player's hand: given if missing, then selected.
concommand.Add("nlshadow_weapon", function(ply, _, args)
    if not host(ply) or not IsValid(ply) then return end
    local class = args[1]
    if not isstring(class) or not string.match(class, "^[%w_]+$") then return end
    if not ply:HasWeapon(class) then ply:Give(class) end
    ply:SelectWeapon(class)
    print("NLSH_WEAPON " .. class)
end)

-- The same character as the player's own model.
concommand.Add("nlshadow_player_model", function(ply)
    if not host(ply) or not IsValid(ply) then return end
    local asset = first_asset()
    if not (asset and mmdhl and mmdhl.Spawn) then print("NLSH_PLAYER_MODEL none") return end
    local pos = ply:GetPos()
    mmdhl.Spawn(ply, asset, { role = "player", position = { pos.x, pos.y, pos.z }, angles = { 0, ply:EyeAngles().y, 0 },
        backend = "source" }, function(ent, err)
        print("NLSH_PLAYER_MODEL " .. (IsValid(ent) and ent:GetModel() or tostring(err)))
    end)
end)

concommand.Add("nlshadow_server_report", function(ply)
    if not host(ply) then return end
    scan()
    file.CreateDir("nlshadow")
    file.Write("nlshadow/server.json", util.TableToJSON({ asked = asked, present = present }, true))
    print("NLSH_SERVER_REPORT")
end)
print("NLSH_SERVER_READY")
