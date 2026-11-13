-- Real Source movement on permanent map geometry. Never force MOVETYPE_LADDER.
util.AddNetworkString("q_medium_meta")
local q={index=0,heads={},packet=980000,nextAt=CurTime()}
local id="q_medium_server"
local function emit(kind,data)
    data.kind=kind local text=util.TableToJSON(data)
    if #text<3000 then print("NLVR_Q "..text) return end
    q.packet=q.packet+1 local encoded=util.Base64Encode(text):gsub("%s","") local count=math.ceil(#encoded/1600)
    for n=1,count do print("NLVR_Q_CHUNK "..q.packet.." "..n.."/"..count.." "..encoded:sub((n-1)*1600+1,n*1600)) end
end
local function vector(v) return {v.x,v.y,v.z} end
local function dry(p)
    p:Freeze(false)
    p:SetMoveType(MOVETYPE_WALK) p:SetPos(Vector(-2870,-1000,32)) p:SetLocalVelocity(Vector())
end
net.Receive("q_medium_meta",function(_,p)
    local index,number=net.ReadUInt(8),net.ReadUInt(32)
    local m={head_pitch=net.ReadFloat(),head_yaw=net.ReadFloat(),cmd_pitch=net.ReadFloat(),cmd_yaw=net.ReadFloat(),gun_model_pitch=net.ReadFloat(),off_pitch=net.ReadFloat(),off_yaw=net.ReadFloat(),stick_x=net.ReadFloat(),stick_y=net.ReadFloat(),weapon=net.ReadString(),draws=net.ReadUInt(32)}
    if p==q.player and index==q.index then
        q.heads[number]=m q.heads[number-512]=nil q.lastMeta=m
        for _,r in ipairs(q.probes or {}) do if r.number==number then r.meta=m end end
    end
end)
concommand.Add("nlvr_q_medium_ready",function(p,_,args)
    if p~=q.player or tonumber(args[1])~=q.index or q.go then return end
    local c=QMEDIUM_CASES[q.index]
    p:Freeze(false)
    p:SetMoveType(c.medium:find("noclip_",1,true) and MOVETYPE_NOCLIP or MOVETYPE_WALK)
    p:SetPos(c.medium=="ladder" and Vector(-2920,-1076,c.direction=="down" and -48 or -80) or c.medium=="noclip_land" and Vector(-2870,-1000,64) or c.medium=="noclip_water" and Vector(0,4200,-400) or Vector(0,3000,-400))
    p:SetLocalVelocity(Vector())
    q.go=CurTime()+.2 p:SetNWFloat("q_med_go",q.go)
end)
local function finish(reason)
    local c=QMEDIUM_CASES[q.index]
    emit("medium-trial",{id=c.id,case=c,probes=q.probes,diagnostics=q.diagnostics,failure=reason,last_meta=q.lastMeta,
        target="permanent world BSP ladder803/water330",entity_removals=0})
    dry(q.player) q.player:SetNWInt("q_med_case",0) q.player:SetNWFloat("q_med_go",0)
    q.current,q.go=nil,nil q.nextAt=CurTime()+.5
end
hook.Add("Tick",id,function()
    local p=Entity(1)
    if not IsValid(p) or not NLVR_SV or not NLVR_SV.Players[p] or q.finished then return end
    if q.current then
        if CurTime()-q.started>8 then finish("case did not produce ten verified medium samples") end
        return
    end
    if CurTime()<q.nextAt then return end
    q.index=q.index+1
    local c=QMEDIUM_CASES[q.index]
    if not c then
        q.finished=true p:SetNWInt("q_med_case",-1)
        emit("medium-complete",{cases=#QMEDIUM_CASES,ladder_contents=util.PointContents(Vector(-2920,-1057,-64)),water_contents=util.PointContents(Vector(0,3000,-400))})
        return
    end
    q.player,q.current,q.started=p,c,CurTime() q.probes,q.diagnostics,q.heads={},{},{}
    dry(p)
    if not p:HasWeapon(c.weapon) then p:Give(c.weapon,true) end
    p:SelectWeapon(c.weapon)
    p:SetPos(c.medium=="ladder" and Vector(-2920,-1076,c.direction=="down" and -48 or -80) or c.medium=="noclip_land" and Vector(-2870,-1000,64) or c.medium=="noclip_water" and Vector(0,4200,-400) or Vector(0,3000,-400))
    p:SetMoveType(MOVETYPE_NOCLIP) p:SetLocalVelocity(Vector()) p:Freeze(true) -- setup only; never a measured sample
    p:SetNWInt("q_med_case",c.id) p:SetNWFloat("q_med_go",0)
end)
hook.Add("SetupMove",id,function(p,mv,cmd)
    if p~=q.player or not q.current or not q.go or CurTime()<q.go then q.move=nil return end
    local a=mv:GetMoveAngles();local s=NLVR_SV and NLVR_SV.Players[p]
    q.move={number=cmd:CommandNumber(),time=CurTime()-q.go,
        wish=vector(a:Forward()*mv:GetForwardSpeed()+a:Right()*mv:GetSideSpeed()+a:Up()*mv:GetUpSpeed()),
        side_buttons=bit.band(mv:GetButtons(),bit.bor(IN_MOVELEFT,IN_MOVERIGHT)),
        buttons=mv:GetButtons(),sync_yaw=s and s.head and s.head.ang.y or 0,handled=s and s.moveHandled,
        frozen=p:IsFrozen(),ladder_normal=vector(p:GetInternalVariable("m_vecLadderNormal") or Vector())}
end,HOOK_MONITOR_LOW)
hook.Add("FinishMove",id,function(p,mv)
    local r=q.move if p~=q.player or not r or not q.current then return end q.move=nil
    r.pos,r.vel=vector(mv:GetOrigin()),vector(mv:GetVelocity()) r.move_type=p:GetMoveType() r.water_level=p:WaterLevel()
    r.player_pos,r.player_velocity=vector(p:GetPos()),vector(p:GetVelocity())
    r.meta=q.heads[r.number]
    q.diagnostics[#q.diagnostics+1]=r if #q.diagnostics>8 then table.remove(q.diagnostics,1) end
    local c=q.current
    local valid=c.medium=="ladder" and r.move_type==MOVETYPE_LADDER and math.abs(r.vel[2])<1 and r.time>=.18 or
        c.medium=="water" and r.water_level>=2 and r.move_type==MOVETYPE_WALK and r.time>=1.5 or
        c.medium:find("noclip_",1,true) and r.move_type==MOVETYPE_NOCLIP and r.time>=1.5
    if valid then q.probes[#q.probes+1]=r end
    if #q.probes>=10 then finish() end
end,HOOK_MONITOR_LOW)
