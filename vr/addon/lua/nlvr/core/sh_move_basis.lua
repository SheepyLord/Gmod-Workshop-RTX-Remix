-- Decouple pitch-sensitive Source movement from the weapon command's aim.
local Basis={}
function Basis.Intent(ply,cmd)
    if not ply.GetMoveType or ply:GetMoveType()~=MOVETYPE_LADDER then return end
    local forward,side,up=cmd:GetForwardMove(),cmd:GetSideMove(),cmd:GetUpMove()
    local a=cmd:GetViewAngles()
    local bits=bit or require("bit")
    local f,b,l,r=IN_FORWARD or 8,IN_BACK or 16,IN_MOVELEFT or 512,IN_MOVERIGHT or 1024
    local buttons=bits.band(cmd:GetButtons(),bits.bnot(bits.bor(f,b,l,r)))
    local sector=math.tan(math.pi/8)
    local edge=math.max(math.abs(forward),math.abs(side))*1e-9
    if math.abs(forward)>.001 and math.abs(forward)>sector*math.abs(side)+edge then buttons=bits.bor(buttons,forward>0 and f or b) end
    if math.abs(side)>.001 and math.abs(side)>sector*math.abs(forward)+edge then buttons=bits.bor(buttons,side>0 and r or l) end
    cmd:SetButtons(buttons)
    return a:Forward()*forward+a:Right()*side+a:Up()*up
end
function Basis.Apply(ply,mv,cmd,head)
    if not cmd or not head or head.valid==false or not ply.GetMoveType then return false end
    if ply:GetMoveType()==MOVETYPE_NOCLIP then return false end
    local ladder=ply:GetMoveType()==MOVETYPE_LADDER
    if not ladder and (not ply.WaterLevel or ply:WaterLevel()<2) then return false end
    local aim=cmd:GetViewAngles()
    local world=aim:Forward()*mv:GetForwardSpeed()+aim:Right()*mv:GetSideSpeed()+aim:Up()*mv:GetUpSpeed()
    local ground=Angle(ladder and head.ang.p or 0,head.ang.y,0)
    local forward,side=world:Dot(ground:Forward()),world:Dot(ground:Right())
    mv:SetMoveAngles(ground)
    mv:SetForwardSpeed(forward) mv:SetSideSpeed(side) mv:SetUpSpeed(ladder and world:Dot(ground:Up()) or world.z)
    -- Direction buttons are command intent, stamped before gun-angle encoding.
    -- Never infer a digital ladder strafe from projection onto a later head sync.
    return true
end
return Basis
