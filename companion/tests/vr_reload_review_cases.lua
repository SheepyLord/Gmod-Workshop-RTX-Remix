-- Review regressions exercise observable effects; the small engine oracle is explicit.
return function(cases,e)
local S,R,server,client,down,eq,near,advance=e.S,e.R,e.server,e.client,e.down,e.eq,e.near,e.advance
local function ack(c,w,on)
    c.receive(82,nil,{w,on,false,true,false,0,0,w:Clip1(),30,-1,"ready","none",0,0,7})
end
local function engineStep(w,p,command)
    if p:GetActiveWeapon()~=w then
        if CurTime()-(w.fields.m_flHolsterTime or 0)>3 and w:GetMaxClip1()>0 then
            local n=math.min(w:GetMaxClip1()-w:Clip1(),p:GetAmmoCount(1))
            w:SetClip1(w:Clip1()+n) p:RemoveAmmo(n,1)
        end
    elseif command and command:KeyDown(IN_ATTACK) and w:Clip1()>0 and w:GetNextPrimaryFire()<=CurTime() then w:SetClip1(w:Clip1()-1)
    elseif w:GetMaxClip1()>0 and w:Clip1()==0 and w:GetNextPrimaryFire()<=CurTime() then
        if p:GetAmmoCount(1)>0 then
            local n=math.min(w:GetMaxClip1(),p:GetAmmoCount(1));w:SetClip1(n);p:RemoveAmmo(n,1)
        else p.active=S.Weapon{class="other"} end
    end
end
e.setOracle(engineStep)
function cases.review_holster()
    for _,class in ipairs({"weapon_pistol","weapon_357","weapon_smg1","weapon_ar2","weapon_shotgun","weapon_crossbow"}) do
        local c,w,p,s,cmd,act,take=server(class,0,60);c.engineStep=engineStep
        if R.Guns[class].kind=="clip" then act(0) end
        p.active=S.Weapon{class="nlvr_hands"}
        for i=1,250 do advance(1/66);c.receive(80,p,{true,false});cmd() end
        eq(w:Clip1(),0);eq(p:GetAmmoCount(1),60)
        assert(w:GetInternalVariable("m_flHolsterTime")<=.05,"holster timer was written into the future")
        p.active=w;cmd();local token=take();s.hands.left.pos,s.hands.left.ang=R.Guns[class].port,R.Guns[class].axis
        eq(act(2,token).last_insertion,"inserted");local loaded=w:Clip1();assert(loaded>0)
        cmd(false,true);eq(w:Clip1(),loaded-1)
    end
end
function cases.review_external_fill()
    local c,w,p,s,cmd,act=server("weapon_smg1",3,60);act(0);cmd();w:SetClip1(20);cmd()
    eq(c.Debug.reload[1].ejected,false) eq(c.Debug.reload[1].holding,false)
    assert(w:GetNextPrimaryFire()<=CurTime())
end
function cases.review_prop_zone()
    local c,w,p,f=client("weapon_pistol");local prop=S.Model{}
    c.Hand.left.held={ent=prop};c.resolver=nil
    f(down("left_grip"));eq(c.Input.Owner("off","grip"),nil)
    for _,m in ipairs(c.messages) do assert(m.kind~=81,"ammo taken while P holds a prop") end
end
function cases.review_climb_zone()
    local c,w,p,f=client("weapon_pistol");c.Debug.interact={left={climbing=true}}
    f(down("left_grip"));eq(c.Input.Owner("off","grip"),nil)
end
function cases.review_server_inactive()
    local c,w,p,f=client("weapon_pistol");ack(c,w,false)
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD))
end
function cases.review_ack_timeout()
    local c,w,p,f=client("weapon_pistol");advance((R.SHORT_LAPSE or 1.5)+.2)
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD))
end
function cases.review_vehicle_button()
    local c,w,p,f=client("weapon_pistol");p.vehicle=true
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD))
end
function cases.review_packet_ranges()
    local c,w,p,s,cmd=server("weapon_pistol",50000,9999999);cmd()
    local unknown=S.Weapon{class="huge_swep",clip1=90000,primary=1,secondary=2};p.inventory[#p.inventory+1]=unknown;p.active=unknown;cmd()
    assert(c.Registry.entries[1].active,"large ammo stopped K")
end
local function stateRetention(mode)
    local c,w,p,s,cmd,act,take=server("weapon_smg1",3,60);act(0);cmd()
    if mode=="hand" then c.receive(80,p,{true,true});c.receive(80,p,{true,false})
    elseif mode=="setting" then c.receive(80,p,{false,false});c.receive(80,p,{true,false})
    elseif mode=="vehicle" then p.vehicle=true;cmd();p.vehicle=false
    else advance(2);cmd();c.receive(80,p,{true,false}) end
    cmd();assert(c.Debug.reload[1].ejected,"ejected state reset by "..mode)
    local token=take();s.hands.left.pos,s.hands.left.ang=R.Guns[w.class].port,R.Guns[w.class].axis
    eq(act(2,token).last_insertion,"inserted")
end
function cases.review_retain_hand() stateRetention("hand") end
function cases.review_retain_setting() stateRetention("setting") end
function cases.review_retain_vehicle() stateRetention("vehicle") end
function cases.review_retain_gap() stateRetention("gap") end
function cases.review_rpg_unloaded()
    local c,w,p,s,cmd=server("weapon_rpg",-1,3);cmd();eq(c.Debug.reload[1].clip,0)
    for _,v in ipairs({{false,false},{true,false},{true,true},{true,false}}) do c.receive(80,p,v);cmd();eq(c.Debug.reload[1].clip,0) end
end
function cases.review_real_heartbeat()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();advance(.6,8);cmd()
    assert(w:GetNextPrimaryFire()>CurTime()+3000,"game-time lease expired within .6 real seconds")
end
function cases.review_real_rate()
    local c,w,p,s,cmd,act=server("weapon_smg1",2,60)
    advance(.01,.1);act(0,nil,nil,.001);advance(.13,.1)
    c.receive(81,p,{1,w,0});assert(c.Debug.reload[1].held>0,"real-time spaced take refused")
end
function cases.review_rate_refusal()
    local c,w,p,s,cmd,act=server("weapon_smg1",2,60);act(0)
    act(1,nil,nil,.001);eq(c.Debug.reload[1].last_operation,"rate");eq(c.Debug.reload[1].held,0)
end
function cases.review_switch_carry()
    local c,w,p,s,cmd,act,take=server("weapon_smg1",0,60);cmd();take()
    p.active=S.Weapon{class="nlvr_hands"};cmd();eq(c.Debug.reload[1].held,0)
end
function cases.review_drop_release()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();p.inventory={};w.owner=S.NULL
    if e.hooks.PlayerDroppedWeapon then e.hooks.PlayerDroppedWeapon["nlvr.reload"](p,w) end
    cmd();assert(w:GetNextPrimaryFire()<=CurTime(),"dropped gun retains K deadline")
end
function cases.review_removed_prune()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();w.valid=false;p.inventory={}
    if e.hooks.EntityRemoved then e.hooks.EntityRemoved["nlvr.reload"](w) end
    cmd();eq(next(e.state(p).guns),nil)
end
function cases.review_deploy_button()
    local c,w,p,f=client("weapon_pistol");c.Settings.physical_reload=0;p.nextAttack=CurTime()+1
    f(down("right_b"));local early=f();assert(not early:KeyDown(IN_RELOAD),"tap consumed during deploy")
    advance(1);assert(f():KeyDown(IN_RELOAD));assert(not f():KeyDown(IN_RELOAD))
end
function cases.review_counter_failure()
    local c,w,p,f,paint=client("weapon_pistol");c.Settings.physical_reload=0
    c.Overlay.New=function() error("deliberate overlay failure") end
    c.emit("before_overlay_paint")
    assert(c.Registry.entries[1].active,"counter failure stopped reload module")
    assert(c.Debug.reload.counter_error)
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD))
end
function cases.review_idle_cost()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();local debug=c.Debug.reload[1]
    local function reads() local n=0 for _,v in pairs(w.reads) do n=n+v end return n end
    local before,n=reads(),c.packetBuilds
    local holsterWrites=w.writes.m_flHolsterTime or 0
    for i=1,100 do advance(.001);cmd() end
    print("COST commands=100 field_reads="..(reads()-before).." packets="..(c.packetBuilds-n))
    assert((w.writes.m_flHolsterTime or 0)-holsterWrites<5,"unchanged command rewrites holster time")
    assert(reads()-before<5,"unchanged gun repeatedly resolves save-field names")
    assert(c.packetBuilds-n<5,"unchanged packet repeatedly serialized")
    eq(c.Debug.reload[1],debug)
end
function cases.review_client_debug_reuse()
    local c,w,p,f=client("weapon_pistol");f();local d=c.Debug.reload
    f();eq(c.Debug.reload,d)
end
function cases.review_arithmetic_mutant()
    local original=R.Transfer;R.Transfer=function(d,clip) return clip,0 end
    local ok=pcall(cases.arithmetic);R.Transfer=original
    assert(not ok,"arithmetic assertions accept a zero-transfer mutant")
end
function cases.review_hold_engine_window()
    for _,reserve in ipairs({0,15}) do
        local c,w,p,s,cmd=server("weapon_smg1",0,reserve);c.engineStep=engineStep
        for i=1,340 do advance(1/66);c.receive(80,p,{true,false});cmd();eq(w:Clip1(),0);eq(p:GetActiveWeapon(),w) end
    end
end
function cases.review_hold_oracle()
    local c,w,p,s,cmd=server("weapon_smg1",0,15)
    cmd();engineStep(w,p);eq(w:Clip1(),0)
    w:SetNextPrimaryFire(CurTime());engineStep(w,p);eq(w:Clip1(),15)
    w:SetClip1(0);p:SetAmmo(0,1);w:SetNextPrimaryFire(CurTime());engineStep(w,p)
    assert(p:GetActiveWeapon()~=w,"oracle cannot observe empty switch")
end
function cases.review_retry_eject()
    local c,w,p,f=client("weapon_pistol")
    f(down("right_a"));f()
    local function actions() local n=0 for _,m in ipairs(c.messages) do if m.kind==81 then n=n+1 end end return n end
    eq(actions(),1)
    c.receive(82,nil,{w,true,false,false,false,0,0,2,30,-1,"rate","none",0,0,0})
    f();f();eq(actions(),2)
    c.receive(82,nil,{w,true,true,false,true,CurTime(),0,0,32,-1,"ejected","none",0,1,0})
    f();f();eq(actions(),2)
end
function cases.review_server_vehicle_ack()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();p.vehicle=true;cmd()
    local m=c.messages[#c.messages];eq(m.kind,82);eq(m.args[2],false)
end
function cases.review_server_stop_ack()
    local c,w,p,s,cmd=server("weapon_smg1",0,60);cmd();c.Registry:Stop();e.advanceTick();c.flush(p)
    eq(c.messages[#c.messages].args[2],false)
end
function cases.review_new_entity()
    local c,w,p,s,cmd,act=server("weapon_smg1",2,60);act(0);cmd()
    local nextGun=S.Weapon{class="weapon_smg1",clip1=20,maxClip1=45,primary=1,secondary=-1};nextGun.owner=p
    function nextGun:GetSaveTable() return {} end
    p.inventory[#p.inventory+1]=nextGun;p.active=nextGun
    if e.hooks.WeaponEquip then e.hooks.WeaponEquip["nlvr.reload"](nextGun,p) end
    cmd();eq(c.Debug.reload[1].ejected,false);eq(c.Debug.reload[1].holding,false)
end
function cases.review_counter_paint_failure()
    local c,w,p,f,paint=client("weapon_pistol");c.Settings.physical_reload=0
    draw.SimpleText=function() error("deliberate painter failure") end
    paint();paint();assert(c.Registry.entries[1].active);assert(c.Debug.reload.counter_error)
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD))
end
function cases.review_other_claim()
    local c,w,p,f=client("weapon_pistol");local update=c.Input.Update
    c.Input.Update=function(...) update(...) c.Input.Claim("left","grip","ui") end
    f(down("left_grip"));eq(c.Input.Owner("off","grip"),"ui")
end

function cases.review_low_reserve_transfer()
    local c,w,p,s,cmd,act,take=server("weapon_smg1",0,2);cmd();act(0)
    local token=take();s.hands.left.pos,s.hands.left.ang=R.Guns[w.class].port,R.Guns[w.class].axis
    eq(act(2,token).last_insertion,"inserted");eq(w:Clip1(),2);eq(p:GetAmmoCount(1),0)
end
function cases.review_rpg_suspend_cycle()
    local c,w,p,s,cmd,act,take=server("weapon_rpg",-1,3);cmd()
    local token=take();s.hands.left.pos,s.hands.left.ang=R.Guns[w.class].port,R.Guns[w.class].axis
    act(2,token);cmd();eq(c.Debug.reload[1].clip,1)
    p:RemoveAmmo(1,1);cmd();eq(c.Debug.reload[1].clip,0)
    c.receive(80,p,{false,false});c.receive(80,p,{true,true});cmd();eq(c.Debug.reload[1].clip,0)
    p.vehicle=true;cmd();p.vehicle=false;cmd();eq(c.Debug.reload[1].clip,0)
    advance(2);cmd();c.receive(80,p,{true,false});cmd();eq(c.Debug.reload[1].clip,0)
end

function cases.review_deploy_server_fallback()
    local c,w,p,f=client("weapon_pistol");c.Settings.physical_reload=0;p.GetInternalVariable=nil
    c.receive(82,nil,{w,false,false,false,false,0,0,2,30,-1,"ready","none",0,0,7,1,false})
    f(down("right_b"));assert(not f():KeyDown(IN_RELOAD))
    c.receive(82,nil,{w,false,false,false,false,0,0,2,30,-1,"ready","none",0,0,7,2,true})
    assert(f():KeyDown(IN_RELOAD));assert(not f():KeyDown(IN_RELOAD))
end

function cases.review_deploy_server_disagreement()
    local c,w,p,f=client("weapon_pistol");c.Settings.physical_reload=0
    c.receive(82,nil,{w,false,false,false,false,0,0,2,30,-1,"ready","none",0,0,7,1,false})
    f(down("right_b"));assert(not f():KeyDown(IN_RELOAD),"local prediction must not outrun a fresh server lock")
    c.receive(82,nil,{w,false,false,false,false,0,0,2,30,-1,"ready","none",0,0,7,2,true})
    assert(f():KeyDown(IN_RELOAD))
end

function cases.review_client_past_absolute_attack_time()
    local c,w,p,f=client("weapon_pistol");c.Settings.physical_reload=0;p.nextAttack=CurTime()-.1
    f(down("right_b"));assert(f():KeyDown(IN_RELOAD),"past positive client deadline must not block B")
end

local function emulateWeapon(c)
    c.weaponMove=function(cmd)
        cmd:RemoveKey(IN_ATTACK2)
        local owner=c.Input.Owner("main","a")
        if c.Input.main.a and (not owner or owner=="weapons") then cmd:AddKey(IN_ATTACK2) end
    end
end
function cases.verify_hitch_eject()
    local c,w,p,f=client("weapon_smg1");emulateWeapon(c)
    assert(not f(down("right_a")):KeyDown(IN_ATTACK2))
    advance(2);assert(not f(down("right_a")):KeyDown(IN_ATTACK2),"eject intent became a grenade after hitch")
    assert(not f():KeyDown(IN_ATTACK2))
end
function cases.verify_eject_ack_edge()
    local c,w,p,f=client("weapon_ar2");emulateWeapon(c);f(down("right_a"))
    ack(c,w,false);assert(not f(down("right_a")):KeyDown(IN_ATTACK2),"eject changed meaning at ACK edge")
end
function cases.verify_b_hitch_intent()
    local c,w,p,f=client("weapon_pistol");f(down("right_b"),true);advance(2)
    assert(not f():KeyDown(IN_RELOAD),"physical B press changed meaning during lapse")
end
function cases.verify_carry_hitch()
    local c,w,p,f=client("weapon_pistol")
    c.receive(82,nil,{w,true,false,false,false,0,7,0,30,-1,"taken","none",0,0,1})
    f(down("left_grip"));f(down("left_grip"));local model=c.Hand.left.held.ent
    advance(2);f(down("left_grip"));assert(IsValid(model),"short ACK lapse destroyed carried ammo")
end
function cases.verify_server_carry_hitch()
    local c,w,p,s,cmd,act,take=server("weapon_pistol",0,30);cmd();local token=take()
    advance(2);cmd();assert(e.state(p).held and e.state(p).held.token==token,"config lapse discarded carried ammo")
end
function cases.verify_glove_lock()
    local c,w,p,f=client("weapon_pistol");c.Debug.interact={left={gloves_target=42}}
    f(down("left_grip"));eq(c.Input.Owner("off","grip"),nil)
end
function cases.verify_glove_pull()
    local c,w,p,f=client("weapon_pistol");c.Debug.interact={left={pulling=true}}
    f(down("left_grip"));eq(c.Input.Owner("off","grip"),nil)
end
function cases.verify_map_hold()
    local c,w,p,s,cmd,act,take=server("weapon_pistol",0,30);w:SetNextPrimaryFire(CurTime()+3600);cmd();act(0)
    local token=take();s.hands.left.pos,s.hands.left.ang=R.Guns[w.class].port,R.Guns[w.class].axis
    act(2,token);assert(w:GetNextPrimaryFire()<=CurTime(),"map-restored K deadline became prior")
end
function cases.verify_map_loaded_hold()
    local c,w,p,s,cmd=server("weapon_smg1",10,30);w:SetNextPrimaryFire(CurTime()+3600);cmd()
    assert(w:GetNextPrimaryFire()<=CurTime(),"loaded map weapon retained K hold")
end
function cases.verify_counter_buffer()
    local c,w,p,f,paint=client("weapon_pistol");f();paint();f();local values=c.Debug.reload.counter_values
    local concat=table.concat;local calls=0;table.concat=function(...) calls=calls+1 return concat(...) end
    for i=1,20 do table.concat=function(...) calls=calls+1 return concat(...) end c.emit("before_overlay_paint");table.concat=concat;f();eq(c.Debug.reload.counter_values,values) end
    table.concat=concat;eq(calls,0)
end
function cases.verify_heartbeat_coalescing()
    local c,w,p,s,cmd=server("weapon_smg1",10,30);cmd();local n=#c.messages
    for i=1,6 do advance(.55);c.receive(80,p,{true,false});cmd() end
    assert(#c.messages-n>=6,"unchanged idle ACKs were dropped by core coalescing")
end
function cases.verify_retry_coalesced_state()
    local sv,sw,sp,ss,cmd,act=server("weapon_pistol",2,30);cmd();act(3)
    local c,w,p,f=client("weapon_pistol");c.frameScale=.01;c.frameDt=.13
    sv.deliver=function(packet) if packet.kind==82 then local a={} for i,v in ipairs(packet.args) do a[i]=v end a[1]=w;c.receive(82,nil,a) end end
    local cursor=0
    local function send()
        while cursor<#c.messages do cursor=cursor+1;local m=c.messages[cursor]
            if m.kind==81 then local a={} for i,v in ipairs(m.args) do a[i]=v end a[2]=sw;ss.lastSync=CurTime();sv.receive(81,sp,a) end
        end
    end
    f(down("right_a"),false,true);f(nil,false,true);send();cmd(true)
    -- The next tick's slot is occupied; routine state replaces the unsent rate reply.
    e.advanceTick();sv.sentTick[sp]=e.tick();advance(.2,.01,true);cmd(true)
    e.advanceTick();sv.flush(sp)
    for i=1,5 do f(nil,false,true);send();cmd(true) end
    eq(sw:Clip1(),0);eq(sp:GetAmmoCount(1),32)
end

cases.review_retry_eject=cases.verify_retry_coalesced_state

function cases.verify_carry_stale_sync_hitch()
    local c,w,p,s,cmd,act,take=server("weapon_pistol",0,30);cmd();local token=take()
    s.hands.left.valid=false;advance(2);cmd()
    assert(e.state(p).held and e.state(p).held.token==token,"core stale-sync invalidation discarded short-lapse carry")
end

end
