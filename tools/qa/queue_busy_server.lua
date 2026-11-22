-- queue_busy_server.lua: a busy single-player map for the engine guard's PoC series (ADR 0247, ADR 0254). Run in the
-- server realm by queue_check_session.py's busy runs (copied to garrysmod/data/nlqueue/busy.txt and run with lua_run):
-- props, ragdolls and fighting NPCs around the player, explosions and bullets for decals on the world and on models,
-- and more props every second, so the level change and the disconnect that follow end a long, crowded session.
-- See queue_busy_server.lua.md.
local ply = Entity(1)
if not IsValid(ply) then
	print("[nlqueue] busy: no player")
	return
end
ply:GodEnable()
local origin = ply:GetPos()

local props = {
	"models/props_c17/oildrum001.mdl", "models/props_junk/wood_crate001a.mdl",
	"models/props_c17/FurnitureChair001a.mdl", "models/props_junk/watermelon01.mdl",
	"models/props_c17/doll01.mdl", "models/props_interiors/BathTub01a.mdl",
	"models/props_c17/FurnitureCouch001a.mdl", "models/props_junk/TrafficCone001a.mdl",
}
local bodies = {
	"models/Humans/Group01/male_07.mdl", "models/Humans/Group01/Female_01.mdl",
	"models/Combine_Soldier.mdl", "models/Police.mdl",
}
local spawned = { props = 0, ragdolls = 0, npcs = 0, explosions = 0 }

local function around(spread, height)
	return origin + Vector(math.random(-spread, spread), math.random(-spread, spread), height)
end

local function prop(i)
	local e = ents.Create("prop_physics")
	if not IsValid(e) then return end
	e:SetModel(props[(i % #props) + 1])
	e:SetPos(around(900, 150 + (i % 8) * 40))
	e:Spawn()
	spawned.props = spawned.props + 1
end

for i = 1, 250 do prop(i) end
for i = 1, 40 do
	local r = ents.Create("prop_ragdoll")
	if IsValid(r) then
		r:SetModel(bodies[(i % #bodies) + 1])
		r:SetPos(around(700, 120))
		r:Spawn()
		spawned.ragdolls = spawned.ragdolls + 1
	end
end
for i = 1, 12 do
	for _, kind in ipairs({ { "npc_citizen", "weapon_smg1", -1 }, { "npc_combine_s", "weapon_ar2", 1 } }) do
		local npc = ents.Create(kind[1])
		if IsValid(npc) then
			npc:SetPos(origin + Vector(kind[3] * math.random(300, 800), math.random(-800, 800), 24))
			npc:SetKeyValue("additionalequipment", kind[2])
			npc:Spawn()
			npc:Activate()
			spawned.npcs = spawned.npcs + 1
		end
	end
end

timer.Create("nlqueue_busy", 1, 0, function()
	if not IsValid(ply) then return end
	for _ = 1, 3 do
		local blast = ents.Create("env_explosion")
		if IsValid(blast) then
			blast:SetPos(around(800, 30))
			blast:SetKeyValue("iMagnitude", "60")
			blast:Spawn()
			blast:Fire("Explode")
			spawned.explosions = spawned.explosions + 1
		end
	end
	-- Bullets from the player's eyes in every direction: impact decals on the world, the props and the bodies.
	ply:FireBullets({ Src = ply:EyePos(), Dir = VectorRand(), Num = 12, Spread = Vector(0.4, 0.4, 0.4), Damage = 4,
		Tracer = 1 })
	for _, body in ipairs(ents.FindByClass("prop_ragdoll")) do
		local at = body:GetPos()
		util.Decal("Blood", at + Vector(0, 0, 30), at - Vector(0, 0, 30), ply)
	end
	for _ = 1, 5 do prop(math.random(1, 1000)) end
	if math.random(1, 3) == 1 then
		local r = ents.Create("prop_ragdoll")
		if IsValid(r) then
			r:SetModel(bodies[math.random(1, #bodies)])
			r:SetPos(around(700, 120))
			r:Spawn()
			spawned.ragdolls = spawned.ragdolls + 1
		end
	end
end)

timer.Create("nlqueue_busy_report", 30, 0, function()
	print(string.format("[nlqueue] busy: %d props, %d ragdolls, %d NPCs, %d explosions, %d entities", spawned.props,
		spawned.ragdolls, spawned.npcs, spawned.explosions, #ents.GetAll()))
end)
print("[nlqueue] busy: started")
