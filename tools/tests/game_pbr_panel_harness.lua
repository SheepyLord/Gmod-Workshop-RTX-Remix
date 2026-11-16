-- Player-facing glue: identity states, candidate/file actions, source-less choices, pictures for drawn materials only,
-- what Remix draws for each material (a Remix mod with its maps, game maps, no PBR, not drawn yet), and the characters
-- followed while the page stays built.
SERVER=false CLIENT=true BRANCH="x86-64" TOP=1 LEFT=2 FILL=3
local hooks,commands,buttons,images={},{},{},0
local now=100
function isstring(v) return type(v)=="string" end
function istable(v) return type(v)=="table" end
function IsValid(v) return type(v)=="table" and v.valid~=false end
function RealTime() return now end
function ScrW() return 1280 end
function ScrH() return 720 end
function GetConVar() return nil end
file={Exists=function() return false end}
hook={Add=function(_,key,fn) hooks[key]=fn end}
concommand={Add=function(key,fn) commands[key]=fn end}
spawnmenu={AddToolMenuOption=function(_,_,_,_,_,_,build) assert(type(build)=="function") end}
local ent,ent2={},{}
local present={ent}
function LocalPlayer() return {GetEyeTrace=function() return {Entity={}} end,
    GetEyeTraceNoCursor=function() return {Entity=ent} end} end
mmdhl={GetAsset=function(e) assert(e==ent or e==ent2) return "asset" end,
    Entities=function() return present end,
    assets={asset={materials={{path="first"},{path="second"},{path="unseen"}}}},
    library={entries={asset={source="E:/model.pmx",info={materials={{base="衣服.png"},{base="copy.png"},{base="unseen.png"}}}}}}}
local calls={}
local identity="mmd/t/0123456789abcdef"
local p={GetGameMaterial=function(name) return {identity=name=="unseen" and "" or identity,state="cached",choices={},files={}} end,
    GameMaterialAction=function(...) calls[#calls+1]={...} return true end}
MaterialPipeline={ToPBR=p}
-- Live texture hashes: the two drawn materials have one, the unseen one none.
RemixMaterial={GetTextureHash=function(name)
    if name=="first" then return 1,"0x1111" elseif name=="second" then return 2,"0x2222" end
    return 0 end}
-- The Advanced Material Editor's index of rtx-remix/mods: the first hash is a pack's, with a normal and a roughness
-- map (its emptied metallic input names no map).
AdvMat={RTX={Enhance={Lookup=function(hashes)
    if hashes[1]=="0x1111" then return {effective={folder="pack_mod",own=false,automatic=false,material={inputs={
        ["inputs:normalmap_texture"]={asset="./n.dds"},["inputs:reflectionroughness_texture"]={asset="./r.dds"},
        ["inputs:metallic_texture"]={asset=""}}}}} end
    return {entries={}} end}}}
-- A material is loaded for its picture only once it was drawn; its picture is made once.
function Material(name) assert(name~="unseen") images=images+1
    return {IsError=function() return false end,
        GetTexture=function() return {IsError=function() return false end,GetName=function() return "t/"..name end} end} end
local made={}
function CreateMaterial(name,shader,params) made[#made+1]={name=name,shader=shader,base=params["$basetexture"]} return made[#made] end
local helps,created={}, {}
local function widget()
    local w={choices={}}
    for _,key in ipairs({"CheckBox","SetTall","AddItem","Dock","DockMargin","SetWrap","SetDark","SetWide","SetSize","Center","SetTitle","SetName","MakePopup","ScrollToChild"}) do w[key]=function() end end
    function w:Clear() self.choices={} end
    function w:SetMaterial(m) self.material=m end
    function w:SetText(text) self.text=text end
    function w:Help(text) local h=widget() h.text=text helps[#helps+1]=h return h end
    function w:ComboBox() return widget() end
    function w:Button(label) local b=widget() buttons[label]=b return b end
    function w:Add() return widget() end
    function w:AddChoice(label,data) self.choices[#self.choices+1]={label,data} end
    function w:GetSelected() local c=self.choices[self.chosen or 1] return c and c[1],c and c[2] end
    function w:ChooseOptionID(i) self.chosen=i end
    return w
end
vgui={Create=function(class) local w=widget() w.class=class created[#created+1]=w return w end}
local input=assert(io.open(arg[1],"rb")) local script=input:read("*a") input:close()
local begin=assert(script:find("-- BEGIN R12 IMPORTED GAME PBR PANEL",1,true))
local ending=assert(script:find("-- END R12 IMPORTED GAME PBR PANEL",begin,true))
assert(loadstring(script:sub(begin,ending-1),"packaged imported-game panel"))()
local P=RTXGamePBRPanel
local rows=P.Materials(ent)
assert(#rows==3 and rows[1].base=="衣服.png")
assert(P.State(rows[1]).identity==P.State(rows[2]).identity)
assert(P.Action(rows[1],"maps",{normal="maps/n.png",packed="maps/m.png",emission="",layout=2}))
assert(calls[1][1]=="first" and calls[1][2]=="E:/model.pmx" and calls[1][3]=="衣服.png" and calls[1][4]=="maps" and calls[1][5]=="maps/n.png" and calls[1][8]==2)
local originalView=p.GetGameMaterial
p.GetGameMaterial=function() return {identity=identity,state="cached",choices={{normal="MAPS/N.PNG",layout=1}}} end
assert(not P.Action(rows[1],"maps",{normal="maps/n.png",layout=2}))
assert(#calls==1 and P.State(rows[1]).error=="Selected maps use another game layout.")
p.GetGameMaterial=originalView
P.Action(rows[2],"none") assert(calls[2][4]=="none")
-- The user's report of 2026-11-16: what Remix draws for each material, by name: the pack's mod and its maps, game
-- maps, no PBR, not drawn yet, an editor profile, and the automatic layer as game maps.
local first=P.Effective(rows[1])
assert(first.hash=="0x1111" and first.mod=="pack_mod" and #first.maps==2,"the pack's mod and its two maps")
assert(P.Describe(first,{state="none"})=="Remix mod: pack_mod (normal, roughness)","the pack's line")
local second=P.Effective(rows[2])
assert(second.hash=="0x2222" and second.mod==nil,"a drawn material no mod replaces")
assert(P.Describe(second,{state="cached",family="Wuthering Waves"})=="Game maps: Wuthering Waves","game maps by family")
assert(P.Describe(second,{state="none"})=="No PBR","no PBR")
assert(P.Effective(rows[3]).hash==nil and P.Describe({},{state="waiting"})=="Not drawn yet","an undrawn material")
assert(P.Describe({hash="0x3",mod="!advanced_material_editor",own=true,maps={}},{})=="Advanced Material Editor profile (values only)","an editor profile")
assert(P.Describe({hash="0x4",mod="~gmod_topbr",automatic=true},{state="automatic",family="Endfield"})=="Game maps: Endfield","the automatic layer")
mmdhl.library.entries.asset=nil
local absent=P.Materials(ent)[1]
assert(absent.source=="" and absent.base=="")
P.Action(absent,"automatic") assert(calls[3][2]=="" and calls[3][4]=="automatic")
P.Build(widget())
assert(images==2 and #made==2 and made[1].base=="t/first" and made[1].shader=="UnlitGeneric","pictures for the drawn materials only")
assert(buttons["No game maps for this texture"] and buttons["Return to automatic"])
hooks.RTXImportedGamePBR()
assert(commands.rtx_topbr_game_editor)
commands.rtx_topbr_game_editor()
assert(P.Frame and images==2 and #made==2,"a material's picture is made once")
assert(#P.Targets()==1)
-- R13-M: a refused conversion's one-line reason (never "DDS publication failed") reaches the
-- selected material's status, with the native error state.
mmdhl.library.entries.asset={source="E:/model.pmx",info={materials={{base="衣服.png"},{base="copy.png"},{base="unseen.png"}}}}
local refusal="free disk space limit: 3 MiB free in C:\\game\\textures, 69 MiB needed (5592580 bytes for this map plus 64 MiB kept free)"
p.GetGameMaterial=function(name) return {identity=name=="unseen" and "" or identity,state="error",error=refusal,choices={},files={}} end
helps={}
local form=widget()
P.Build(form)
local summary=helps[5]
buttons["List looked-at character"].DoClick()
now=now+1 form:Think()
local shown=false
for _,h in ipairs(helps) do if type(h.text)=="string" and h.text:find(refusal,1,true) then shown=true end end
assert(shown,"refusal line not shown in the panel status")
p.GetGameMaterial=originalView
-- The page's summary counts what supplies the character's PBR; a row names its source, maps and hash.
now=now+1 form:Think()
assert(summary.text=="1 × Remix mod: pack_mod\n2 × Game maps","the summary: "..tostring(summary.text))
local labelled=false
for _,w in ipairs(created) do
    if w.class=="DLabel" and type(w.text)=="string" and w.text:find("Remix mod: pack_mod\nnormal, roughness\n0x1111",1,true) then labelled=true end
end
assert(labelled,"a row does not name its mod, maps and hash")
-- The page stays built while the character goes: the list empties and says so, and a new character fills it.
present={} ent.valid=false now=now+1 form:Think()
assert(summary.text=="No character: spawn one, or look at one and list it.","a removed character stayed: "..tostring(summary.text))
-- helps[6] is the selected material's status (after the four help lines and the summary).
assert(helps[6].text=="Select a material","the status kept a removed character's material: "..tostring(helps[6].text))
-- "List looked-at character" with the eyes on no character keeps what is shown (here nothing) rather than failing.
buttons["List looked-at character"].DoClick()
present={ent2} now=now+1 form:Think()
now=now+1 form:Think()
assert(summary.text=="1 × Remix mod: pack_mod\n2 × Game maps","a new character did not fill the page: "..tostring(summary.text))
print("PASS imported game PBR panel: metadata, shared identities, family/files/none/automatic, missing source, what Remix draws by name, pictures for drawn materials once, refusal reason shown, summary, characters followed")
