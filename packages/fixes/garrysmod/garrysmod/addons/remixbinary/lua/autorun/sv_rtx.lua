-- Note to anyone reading: Try to do things on the client if you can!!!
-- Native loader (ADR 0206): only in this machine's RTX starts, as the companion's first autorun says, or under the
-- verified multiplayer initializer; an off switch, a removed loader or files a loader left behind run none of this.
if not (NATIVELOADER_VERIFIED_MULTIPLAYER or NativeLoaderRTXStart and NativeLoaderRTXStart()) then return end
if (SERVER) then
	-- Initialize NikNaks
	require("niknaks")

	-- Create debug ConVar for server-side debugging
	local cv_debug = CreateConVar("rtx_rt_debug_sv", "0", FCVAR_ARCHIVE, "Enable debug messages for RT States on server")

	-- Helper function for debug printing
	local function DebugPrint(message)
		if cv_debug:GetBool() then
			print("[gmRTX-SV] " .. message)
		end
	end

	local function LoadServerSubAddons()
		-- First, send ALL necessary files to clients (shared AND client files)
		local allowCSLua = GetConVar("sv_allowcslua")
		if allowCSLua and allowCSLua:GetBool() then
			DebugPrint("sv_allowcslua is enabled, sending shared and client files to clients")
			
			-- Send shared files to clients (CRITICAL for multiplayer)
			local sharedFiles, _ = file.Find("remixlua/sh/*.lua", "LUA")
			if sharedFiles then
				DebugPrint("Sending " .. #sharedFiles .. " shared files to clients")
				for _, fileName in ipairs(sharedFiles) do
					local filePath = "remixlua/sh/" .. fileName
					AddCSLuaFile(filePath)
					DebugPrint("Sent shared file: " .. filePath)
				end
			end
			
			-- Send client files to clients
			local clientFolders = {"remixlua/cl/", "remixlua/cl/remixapi/", "remixlua/cl/remixapi/wrappers/", "remixlua/cl/customrender/"}
			for _, folder in ipairs(clientFolders) do
				local files, _ = file.Find(folder .. "*.lua", "LUA")
				if files then
					DebugPrint("Sending " .. #files .. " client files from " .. folder)
					for _, fileName in ipairs(files) do
						local filePath = folder .. fileName
						AddCSLuaFile(filePath)
						DebugPrint("Sent client file: " .. filePath)
					end
				end
			end
		else
			DebugPrint("sv_allowcslua is disabled, not sending files to clients")
		end

		-- Load server-side files on the server
		local foldersToLoad = {}
		
		-- Always load shared files on server
		table.insert(foldersToLoad, "remixlua/sh/")
		
		-- Always load server files 
		table.insert(foldersToLoad, "remixlua/sv/")
		
		for _, folder in ipairs(foldersToLoad) do
			local files, _ = file.Find(folder .. "*.lua", "LUA")
			
			if files then
				DebugPrint("Found " .. #files .. " files in " .. folder)
				
				for _, fileName in ipairs(files) do
					local filePath = folder .. fileName
					local success, err = pcall(include, filePath)
					
					if not success then
						-- Always visible: a feature that failed to load is otherwise silently missing.
						ErrorNoHalt("[gmRTX-SV] Failed to load sub-addon " .. filePath .. ": " .. tostring(err) .. "\n")
					else
						DebugPrint("Successfully loaded sub-addon: " .. filePath)
					end
				end
			else
				DebugPrint("No files found in " .. folder)
			end
		end
	end

	-- Load sub-addons immediately when server starts
	print("[gmRTX] - Initialising Server") 
	LoadServerSubAddons()

	function RTXLoadServer( ply )  
		-- This still runs when players spawn for any per-player initialization
		DebugPrint("Player " .. tostring(ply) .. " spawned")
	end 
	hook.Add( "PlayerInitialSpawn", "RTXReadyServer", RTXLoadServer)  

end

if SERVER then
    -- The light's and the sky editor's limits, and the light's spawn policy, live with the entities
    -- (remix_rt_light/shared.lua and init.lua, remix_sky_editor/shared.lua and init.lua): the tools, dupes
    -- and every client's light and sky use the same ones (review findings 13, 14 and 22).
    local RT_LIGHT_SPAWN_COOLDOWN = 0.25

    -- The client only asks for a light; the server traces from the player's eyes and
    -- applies the spawn menu's policy (permissions, sbox_maxsents, creator, undo, cleanup).
    util.AddNetworkString("remix_spawn_rt_light")
    net.Receive("remix_spawn_rt_light", function(len, ply)
        if not IsValid(ply) then return end
        if (ply.RemixNextRTLightSpawn or 0) > CurTime() then return end
        ply.RemixNextRTLightSpawn = CurTime() + RT_LIGHT_SPAWN_COOLDOWN

        if isfunction(Spawn_SENT) then
            Spawn_SENT(ply, "remix_rt_light")
            return
        end

        -- Gamemodes without sandbox's spawn policy: admins only, and the light is theirs as a tool's light
        -- is (RemixRTLight: the limit where the gamemode has one, creator, owner and cleanup).
        if not ply:IsAdmin() or not RemixRTLight or not RemixRTLight.CanSpawn(ply) then return end
        local start = ply:EyePos()
        local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * 4096, filter = ply })
        local stored = scripted_ents.GetStored("remix_rt_light")
        local spawnFunction = scripted_ents.GetMember("remix_rt_light", "SpawnFunction")
        if not tr.Hit or not stored or not spawnFunction then return end

        local ent = spawnFunction(stored.t, ply, tr, "remix_rt_light")
        if not IsValid(ent) then return end
        RemixRTLight.Claim(ply, ent)
        undo.Create("SENT")
            undo.SetPlayer(ply)
            undo.AddEntity(ent)
        undo.Finish("Remix RT Light")
    end)

    util.AddNetworkString("remix_rt_light_apply")
    net.Receive("remix_rt_light_apply", function(len, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local ent = net.ReadEntity()
        if not IsValid(ent) or ent:GetClass() ~= "remix_rt_light" then return end
        local t = net.ReadTable()
        if not istable(t) or not RemixRTLight then return end

        -- The editor's settings, each within the light's limits; the editor changes the settings it
        -- always could (RemixRTLight.EDITOR_KEYS).
        RemixRTLight.Apply(ent, t, RemixRTLight.EDITOR_KEYS)
    end)

    -- Sky Editor entity net receiver
    util.AddNetworkString("remix_sky_editor_apply")
    net.Receive("remix_sky_editor_apply", function(len, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local ent = net.ReadEntity()
        if not IsValid(ent) or ent:GetClass() ~= "remix_sky_editor" then return end
        local t = net.ReadTable()
        if not istable(t) or not RemixSkyEditor then return end

        -- Each value within the sky's limits.
        RemixSkyEditor.Apply(ent, t)
    end)
end