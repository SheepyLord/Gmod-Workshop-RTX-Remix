-- The Mesh Separator on the server (ADR 0232): a detached piece is placed where it was (the current pose) or where
-- the player aims (the rest pose), as a Model Hotloader static prop, after the same checks as the tool's clicks. The
-- outcome goes back as mmdhl_separator_result (placed or not, and why), not as the Hotloader's notices, which all show
-- as errors.
local S=mmdhl.separator
local P=mmdhl.props
local L=mmdhl.L
local function result(p,ok,text)
 if not IsValid(p) then return end
 net.Start('mmdhl_separator_result') net.WriteBool(ok==true) net.WriteString(tostring(text or '')) net.Send(p)
end
net.Receive('mmdhl_separator_place',function(_,p)
 local id=net.ReadString() local source=net.ReadEntity() local inPlace=net.ReadBool() local pos=net.ReadVector() local frozen=net.ReadBool()
 if (p.MMDHLNextSeparatorPlace or 0)>CurTime() then return end p.MMDHLNextSeparatorPlace=CurTime()+.5
 if not S.Enabled:GetBool() then result(p,false,L'separator.error.disabled') return end
 -- The model it came from, while it exists, is checked as a click on it would be; a piece of a model that is
 -- gone is placed only where the player could have taken it (single-player, administrators).
 if IsValid(source) then
  local ok,why=S.MayUse(p,source) if not ok then result(p,false,why) return end
 elseif not game.SinglePlayer() and not p:IsAdmin() then result(p,false,L'separator.error.source_gone') return end
 if not P.ValidID(id) then result(p,false,L'props.error.select_prop') return end
 if not P.CanUse(p,id) then result(p,false,L'props.error.not_shared_admin') return end
 local settings={collide=p:GetInfo('mmdhl_prop_collide'),gravity=p:GetInfoNum('mmdhl_prop_gravity',1)~=0,physprop=p:GetInfo('mmdhl_prop_physprop'),frozen=frozen,scale=1}
 if not inPlace then
  P.PlaceAt(p,id,p:GetEyeTrace(),settings,function(ent,text)
   if IsValid(ent) then result(p,true,L('separator.placed',{name=text})) else result(p,false,text) end
  end)
  return
 end
 if not P.FiniteVector(pos) or pos:DistToSqr(p:EyePos())>S.Reach^2 then result(p,false,L'separator.error.too_far') return end
 local generation=mmdhl.cleanupGeneration
 P.Load(id,function(info,err)
  if not IsValid(p) then return end
  if mmdhl.cleanupGeneration~=generation then result(p,false,L'server.error.map_cleanup') return end
  if not info then result(p,false,err or L'props.error.load_failed') return end
  local surface=isstring(settings.physprop) and P.SurfaceMaterialIds[settings.physprop] and settings.physprop or nil
  -- The piece's vertices are kept around its centre: unrotated at the centre, it is where it was.
  local ent,e=P.CreateProp(p,id,pos,angle_zero,1,{frozen=frozen,surface=surface})
  if not IsValid(ent) then result(p,false,e) return end
  P.SetCollision(ent,P.CollisionModeIds[settings.collide] and settings.collide or P.DefaultCollision,settings.gravity)
  undo.Create('mmdhl.undo.static_prop') undo.AddEntity(ent) undo.SetPlayer(p)
  if info.name then undo.SetCustomUndoText('Undone '..tostring(info.name)) end
  undo.Finish()
  result(p,true,L('separator.placed',{name=P.Name(info)}))
 end)
end)
