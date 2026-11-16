-- Mesh Separator (ADR 0232, ADR 0233): take a piece off a model (a Model Hotloader character, a prop, a ragdoll or an
-- NPC) and make it a prop of its own, with its physics. Left click opens the editor for the model aimed at, where the
-- piece is selected. The server checks every click (mmdhl/separator/shared.lua S.MayUse); the client keeps the
-- selection (mmdhl/separator/client.lua) and the editor (mmdhl/separator/editor.lua).
local L=mmdhl.L
TOOL.Category='Construction'
TOOL.Name='#tool.mmdhl_separator.name'
TOOL.Command=nil
TOOL.ConfigName=''
TOOL.ClientConVar={mode='piece',brush='4',pose='current',collision='auto',freeze='1',place='1',name=''}
TOOL.Information={{name='left'}}
if CLIENT then
 language.Add('tool.mmdhl_separator.name',L'tool.separator.name')
 language.Add('tool.mmdhl_separator.desc',L'tool.separator.desc')
 language.Add('tool.mmdhl_separator.left',L'tool.separator.left')
end
-- The server checks the model aimed at, or keeps the one being worked on when the aim passes its body (a hairpin
-- outside a ragdoll's physics hull), and tells the client to open it in the editor (3; the message keeps the action
-- field of ADR 0232's clicks).
local function send(tool,trace)
 if CLIENT then return true end
 local S=mmdhl and mmdhl.separator local p=tool:GetOwner()
 if not S or not IsValid(p) then return false end
 if (p.MMDHLNextSeparatorClick or 0)>CurTime() then return false end p.MMDHLNextSeparatorClick=CurTime()+.15
 local ent=trace.Entity
 if not IsValid(ent) or ent:IsWorld() or not S.Kind(ent) then ent=p.MMDHLSeparatorTarget end
 if not IsValid(ent) then mmdhl.props.Notice(p,L'separator.error.aim_model') return false end
 local ok,why=S.MayUse(p,ent) if not ok then mmdhl.props.Notice(p,why) return false end
 p.MMDHLSeparatorTarget=ent
 net.Start('mmdhl_separator_target') net.WriteEntity(ent) net.WriteUInt(3,2) net.Send(p)
 return true
end
function TOOL:LeftClick(trace) return send(self,trace) end
if CLIENT then
 function TOOL.BuildCPanel(panel)
  if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
  local S=mmdhl and mmdhl.separator
  panel:Help(L'tool.separator.help')
  local function choices(label,cvar,list)
   local box=panel:ComboBox(label,cvar) local current=GetConVar(cvar) and GetConVar(cvar):GetString()
   for _,c in ipairs(list) do box:AddChoice(c[1],c[2],current==c[2]) end
   return box
  end
  local status=panel:Help('')
  local function update()
   if not IsValid(status) or not S then return end
   local target=S.target
   if not target or not IsValid(target.ent) then status:SetText(L'tool.separator.no_model') return end
   status:SetText(L('tool.separator.selected',{count=string.Comma(target.snap.count),total=string.Comma(target.snap.n)}))
  end
  hook.Add('MMDHL.SeparatorChanged',status,update) update()
  panel:Button(L'tool.separator.open_editor','mmdhl_separator_editor')
  panel:Button(L'tool.separator.clear','mmdhl_separator_clear')
  panel:TextEntry(L'tool.separator.piece_name','mmdhl_separator_name')
  panel:ControlHelp(L'tool.separator.name_help')
  choices(L'tool.separator.pose','mmdhl_separator_pose',{{L'tool.separator.pose_current','current'},{L'tool.separator.pose_rest','rest'}})
  choices(L'tool.separator.physics','mmdhl_separator_collision',{{L'tool.separator.physics_auto','auto'},{L'tool.separator.physics_hull','hull'},{L'tool.separator.physics_detailed','balanced'}})
  panel:CheckBox(L'tool.separator.freeze','mmdhl_separator_freeze')
  panel:CheckBox(L'tool.separator.place','mmdhl_separator_place')
  panel:Button(L'tool.separator.detach','mmdhl_separator_detach')
  panel:ControlHelp(L'tool.separator.detach_help')
 end
end
