-- Runs inside test_companion_sky.py's production sky session. Exercise actual Derma callbacks,
-- DATA operations and clipboard payloads. Native rendering and the external clipboard are mocked.
local widgets, groups, notes, files, parsed = {}, {}, {}, {}, {}
local lastLabel, stateLabel, lastColour, prompt, confirm, clipboard, failRename
local folder = "nativeloader_companion/sky_looks/"
local function noop() end
IsValid = function(w) return type(w) == "table" end
surface = {SetFont = noop, GetTextSize = function(s) return #s * 6, 16 end}
draw = {GetFontHeight = function() return 16 end}
function SetClipboardText(text) clipboard = text end
function Derma_StringRequest(_, _, _, fn) prompt = fn end
function Derma_Query(_, _, _, fn) confirm = fn end
MsgN = function(text) notes[#notes + 1] = text end

local function encode(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q",v) or tostring(v) end
    local items = {}
    if #v > 0 then
        for i = 1, #v do items[i] = encode(v[i]) end
        return "[" .. table.concat(items,",") .. "]"
    end
    for k, item in pairs(v) do items[#items+1] = encode(k) .. ":" .. encode(item) end
    table.sort(items)
    return "{" .. table.concat(items,",") .. "}"
end
local function duplicate(v)
    if type(v) ~= "table" then return v end
    local result = {}
    for k, item in pairs(v) do result[k] = duplicate(item) end
    return result
end
util.TableToJSON = function(v, pretty)
    assert(not pretty)
    local text = encode(v)
    parsed[text] = duplicate(v)
    return text
end
util.JSONToTable = function(text, _, raw) assert(raw) return duplicate(parsed[text]) end
file.CreateDir = function(path) assert(path.."/" == folder) end
file.Exists = function(path) return files[path] ~= nil end
file.Read = function(path) return files[path] end
file.Write = function(path,text) assert(path:sub(1,#folder)==folder) files[path]=text end
file.Delete = function(path) files[path]=nil end
file.Rename = function(a,b)
    if not files[a] or files[b] or (failRename and a:find(".new.txt",1,true)) then return false end
    files[b],files[a] = files[a],nil
    return true
end
file.Open = function(path, mode, realm)
    assert(mode=="rb" and realm=="DATA")
    if not files[path] then return end
    return {Size=function() return #files[path] end, Read=function(_,n) assert(n<=8192) return files[path]:sub(1,n) end, Close=noop}
end
file.Find = function(pattern)
    local ending = pattern:match("%*(.+)$")
    local names = {}
    for path in pairs(files) do
        if path:sub(1,#folder)==folder and path:sub(-#ending)==ending then names[#names+1]=path:sub(#folder+1) end
    end
    return names,{}
end

local function widget(label)
    local w={text=label, enabled=true, visible=true, InvalidateLayout=noop,
        SetDefaultValue=noop, SetPalette=noop, SetAlphaBar=noop, SetWangs=noop, SetSortItems=noop}
    if label then widgets[label]=w end
    function w:GetParent() return self.parent end
    function w:SetTall(height) self.height=height end
    function w:SetText(v) self.text=v end
    function w:GetText() return self.text end
    function w:SetVisible(v) self.visible=v end
    function w:SetEnabled(v) self.enabled=v end
    function w:SetValue(v) self.val=v if self.OnValueChanged then self:OnValueChanged(v) end end
    function w:GetValue() return self.val end
    function w:SetColor(v) self:ValueChanged(v) end
    function w:Clear() self.choices,self.order={},{} end
    function w:AddChoice(text,id) self.choices[text]=id self.order[#self.order+1]=text end
    function w:AddSpacer() end
    function w:pick(text) self:OnSelect(1,text,assert(self.choices[text],text)) end
    return w
end
local function form()
    local f=widget()
    f.rows={}
    function f:SetName(v) self.name=v groups[v]=self end
    function f:SetExpanded(v) self.expanded=v end
    -- DForm docks its padded wrapper. Hiding the child alone leaves a row above the next control.
    function f:AddItem(child)
        local row=widget()
        child.parent,row.parent,row.child=row,self,child
        self.rows[#self.rows+1]=row
        return child
    end
    function f:InvalidateLayout(immediate)
        if not immediate then return end
        local top=0
        for _,row in ipairs(self.rows) do
            row.top=top
            if row.visible then top=top+1 end
        end
    end
    function f:InvalidateParent(immediate) self.parentLaidOut=immediate end
    function f:Help(label)
        lastLabel=label
        local w=widget(label)
        if not stateLabel then stateLabel=w end
        return self:AddItem(w)
    end
    function f:ControlHelp(text) assert(#text>4) local w=widget() w.text=text return self:AddItem(w) end
    function f:ComboBox(label) local w=widget(label=="" and lastLabel or label) w:Clear() return self:AddItem(w) end
    function f:CheckBox(label) return self:AddItem(widget(label)) end
    function f:NumSlider(label,binding,lo,hi)
        local w=widget(label=="" and lastLabel or label)
        w.Scratch={GetFloatValue=function() return w.val end}
        w.min,w.max=lo,hi
        if binding then
            w.binding=binding
            w.Think=function(self) self.val=convars[binding]:GetFloat() end
            w.OnValueChanged=function(_,v) cmd(binding,tostring(v)) end
            w:Think()
        end
        return self:AddItem(w)
    end
    function f:Button(label) return self:AddItem(widget(label)) end
    return f
end
vgui = {Create=function(kind, parent)
    if kind=="DForm" then return form() end
    if kind=="DPanel" or kind=="DButton" then local w=widget() w.SetPaintBackground=noop return w end
    if kind=="DTextEntry" then return widget(lastColour.." RGB") end
    assert(kind=="DColorMixer")
    lastColour=lastLabel
    return widget(lastLabel)
end}
local panel=form()
local writes=#calls
NATIVELOADER_SKY.buildEnhancedPanel(panel)
assert(groups.Clouds.expanded and not groups.Wind.expanded and not groups["Light and mist"].expanded)
for _,g in pairs(groups) do g:OnToggle(true) end
assert(#calls==writes and not convars.nativeloader_sky_own_look:GetBool()) -- opening and expanding only read
local ctrl=widgets["My own look"]
if MIST_PAGES then
    local editorMist=widgets.Mist
    local styleGroup=groups["Light and mist"]
    assert(editorMist:GetParent()==styleGroup.rows[1] and editorMist.min==0 and editorMist.max==2)
    local mapMist=widgets["Mist on the map"]
    assert(table.concat(mapMist.order,"|")=="Enhanced mist|Remix fog near you|Off")
    mapMist:pick("Off")
    assert(numos("volumetrics")=="0" and numos("aerialPerspective")=="False")
    mapMist:pick("Enhanced mist")
    local sky=form()
    NATIVELOADER_SKY.buildPanel(sky)
    local slider=widgets.Mist
    local row=slider:GetParent()
    local help=sky.rows[row.top+2]
    local status=sky.rows[1].child
    assert(slider~=editorMist and slider.binding=="nativeloader_sky_style_mist_strength")
    assert(row.visible and help.visible and help.child.text==styleGroup.rows[2].child.text)
    assert(help.child.text:find("fog preset",1,true))
    slider:SetValue(0.5) ctrl:Think()
    assert(editorMist:GetValue()==0.5 and numos("fogVisibilityMeters")=="40000")
    editorMist:SetValue(1.5) slider:Think()
    assert(slider:GetValue()==1.5 and not convars.nativeloader_sky_own_look:GetBool())
    widgets["Copy look as text"]:DoClick()
    local look=parsed[clipboard].look
    assert(look.mistStrength==nil and look.aerosolDensity==2 and look.fogVisibilityMeters==20000)
    cmd("nativeloader_sky_enhanced","0") status:Think() assert(not row.visible and not help.visible)
    cmd("nativeloader_sky_enhanced","1") status:Think() assert(row.visible and help.visible)
    NativeLoaderVR={state="running"} tick(1) status:Think() assert(not row.visible and not help.visible)
    assert(volumeWrites()==0)
    return
end
local function header(notice,button)
    assert(stateLabel:GetParent().visible==notice and widgets["Switch to Enhanced"]:GetParent().visible==button)
    assert(ctrl:GetParent().top==(notice and 1 or 0)+(button and 1 or 0) and panel.parentLaidOut)
end
if PAGE_STANDARD then
    header(true,true)
    assert(stateLabel.text:find("Switch to Enhanced",1,true))
    assert(not value("rtx.atmosphere.numos.cloudDensity"))
    cmd("nativeloader_sky_enhanced","1") ctrl:Think()
    header(false,false)
    NativeLoaderVR={state="running"} tick(1) ctrl:Think()
    header(true,false)
    assert(stateLabel.text:find("unavailable in VR",1,true))
    NativeLoaderVR.state="off" tick(1) ctrl:Think() header(false,false)
    cmd("nativeloader_sky_enhanced","0") ctrl:Think() header(true,true)
    return
end
header(false,false)
cmd("nativeloader_remix_fog","heavyFog") ctrl:Think()
header(true,false)
assert(stateLabel.text:find("A Remix fog preset is active",1,true))
cmd("nativeloader_remix_fog","") ctrl:Think() header(false,false)
local start=widgets["Start from"]
local vis=widgets["Visibility (m)"]
assert(vis.min==0 and vis.max==50000)
local a=vis:TranslateSliderValues(0.1,0) assert(vis.val==50 and math.abs(a-0.1)<1e-6)
vis:TranslateSliderValues(0.55,0) assert(vis.val>=1580 and vis.val<=1582)
vis:OnValueChanged(715) assert(numos("fogVisibilityMeters")=="715")
vis:TranslateSliderValues(0,0) assert(numos("fogVisibilityMeters")=="0")
local haze=widgets["Haze density"]
assert(haze.min==0 and haze.max==100)
-- Drag and read the thumb back in both directions, then enter a measured trial density directly.
for _,density in ipairs({0,1,10,50,100}) do
    local x=math.log(1+density)/math.log(101)
    local shown=haze:TranslateSliderValues(x,0)
    assert(math.abs(shown-x)<1e-7 and tonumber(numos("aerosolDensity"))==density)
    assert(math.abs(haze.Scratch:GetFraction()-x)<1e-7)
    if density==10 then assert(shown>0.5) end
end
haze:SetValue(79.25) assert(numos("aerosolDensity")=="79.25")
local darkness=widgets["Haze darkness"]
assert(darkness:GetParent().top==haze:GetParent().top+2 and darkness.min==0 and darkness.max==3)
local tint=widgets["Haze colour RGB"]
tint.val="1,0.8,0.6" tint:OnEnter()
for _,case in ipairs({{0,"0, 0, 0"}, {1,"0.0044, 0.0044, 0.0044"}, {3,"0.0132, 0.0132, 0.0132"},
    {0.1,"0.00044, 0.00044, 0.00044"}}) do
    darkness:SetValue(case[1])
    assert(numos("mieAbsorption")==case[2] and numos("aerosolDensity")=="79.25")
    assert(numos("aerosolTint")=="1, 0.8, 0.6")
end
widgets["Copy look as text"]:DoClick() local hazyLook=clipboard
assert(encode(parsed[hazyLook].look.mieAbsorption)=="[0.00044,0.00044,0.00044]")
haze:SetValue(1) darkness:SetValue(3)
widgets["Paste a look"]:DoClick() prompt(hazyLook) tick(2) ctrl:Think()
assert(numos("aerosolDensity")=="79.25" and math.abs(darkness.val-0.1)<1e-9)
for _,label in ipairs({"Cloud colour","Sheet colour","Haze colour","Air colour"}) do
    assert(widgets[label].height==4*draw.GetFontHeight("DermaDefault"))
    assert(widgets[label.." RGB"])
end
widgets["Cloud colour"]:ValueChanged(Color(51,102,153)) assert(numos("cloudColor")=="0.2, 0.4, 0.6")
local rgb=widgets["Cloud colour RGB"]
rgb.val="0.999,0.997,0.995" rgb:OnEnter() assert(numos("cloudColor")=="0.999, 0.997, 0.995")
rgb.val="1.2,0,0" rgb:OnEnter() assert(numos("cloudColor")=="0.999, 0.997, 0.995")
widgets["Cloud density"]:OnValueChanged(11) assert(numos("cloudDensity")=="11")
widgets["Sun rays"]:OnValueChanged(1.4)
local lamp=widgets["Lamp glow in mist"]
assert(lamp.val==0 and numos("aerialPerspectiveLocalLights")=="False")
lamp:OnChange(true) ctrl:Think()
assert(lamp.val==1 and numos("aerialPerspectiveLocalLights")=="True")
assert(#start.order==21)
local builtinData=include("nativeloader/enhanced_builtin_looks.lua")
local baseline=include("nativeloader/enhanced_weather.lua").defaults
local newNames={"Mackerel sky","Towering cumulus","Humid summer","High cirrus","After the rain"}
for i,name in ipairs(newNames) do
    assert(start.order[16+i]==name)
    local definition=builtinData[4+i]
    assert(definition.name==name)
    start:pick(name) tick(2)
    widgets["Copy look as text"]:DoClick()
    local loaded=parsed[clipboard].look
    for key,base in pairs(baseline) do
        if key=="cloudLayer2CoverageMean" or key=="cloudCirrusCoverageMean" then base=0 end
        local want=definition.values[key]
        if want==nil then want=base end
        assert(encode(loaded[key])==encode(want),name.." / "..key)
        if key~="cloudCoverageMean" and key~="cloudWindDirection" and key~="cloudWindSpeed" then
            assert(numos(key)==M.optionText(want),name.." / "..key)
        end
    end
    assert(loaded.aerialPerspectiveLocalLights==nil and numos("aerialPerspectiveLocalLights")=="True")
end
widgets["Cloud density"]:OnValueChanged(11)
start:pick("Altostratus sheet")
assert(numos("cloudDensity")=="11") tick(1) assert(numos("cloudDensity")=="15.5")
tick(1) assert(numos("cloudDensity")=="20" and numos("cloudLayer2BaseHeightMeters")=="4000")
start:pick("Fair-weather cumulus") tick(2)
assert(numos("cloudBaseHeightMeters")=="1200" and numos("aerosolDensity")=="0.9")
start:pick("Broken cloud") tick(2) assert(numos("cloudDepthMeters")=="2500")
start:pick("Cirrus streaks") tick(2) assert(numos("cloudCirrusOpticalDepth")=="0.3")
assert(numos("rays.strength")=="1.4" and convars.nativeloader_weather.value=="partlyCloudy")
widgets["Reset to current weather"]:DoClick() tick(2)
assert(tonumber(numos("fogVisibilityMeters"))==looks.partlyCloudy.fogVisibilityMeters)
widgets["Copy look as text"]:DoClick()
local text=clipboard
assert(type(text)=="string" and #text<8192 and not text:find("\n",1,true))
local original=assert(parsed[text])
local fields=0 for key in pairs(original.look) do fields=fields+1 assert(looks.partlyCloudy[key]~=nil) end
assert(original.version==2 and fields==46 and original.look["rays.strength"]==nil and original.look.nightGainStops==nil)
for name,c in pairs(convars) do
    if name:find("nativeloader_sky_look_",1,true) or name:find("nativeloader_sky_style_",1,true) then assert(c.archived,name) end
end
local function save(id)
    widgets["Save as"]:DoClick()
    prompt(id)
end
save("My-Sky_1")
local path=folder.."my-sky_1.json"
assert(files[path]==text and start.choices["My look (my-sky_1)"])
for _,name in ipairs({"../dir", "COM1", "a.b", "", string.rep("x",33), "bad\\file"}) do
    save(name)
    assert(notes[#notes]:find("refused",1,true))
end
start:pick("Broken cloud") tick(2) save("my-sky_1")
assert(files[path]==text and confirm)
failRename=true confirm() failRename=false assert(files[path]==text) -- failed replacement put the original back
save("my-sky_1") confirm() assert(files[path]~=text)
widgets["Paste a look"]:DoClick() prompt(text) tick(2)
assert(numos("cloudDepthMeters")==tostring(original.look.cloudDepthMeters))
-- Both entry points upgrade a pre-E3 look in memory. Every old field survives the round trip.
local old=duplicate(original)
old.version=1
old.look.mieAbsorption=nil
old.look.cloudDensity=17
local oldText=util.TableToJSON(old,false)
files[path]=oldText
local upgraded=duplicate(old.look)
upgraded.mieAbsorption={0.0044,0.0044,0.0044}
for _,source in ipairs({"file","paste"}) do
    darkness:SetValue(3)
    if source=="file" then start:pick("My look (my-sky_1)")
    else widgets["Paste a look"]:DoClick() prompt(oldText) end
    tick(2) ctrl:Think()
    assert(numos("cloudDensity")=="17", source .. " missed the old look")
    assert(numos("mieAbsorption")=="0.0044, 0.0044, 0.0044", source .. " absorption " .. tostring(numos("mieAbsorption")))
    assert(math.abs(darkness.val-1)<1e-9, source .. " slider " .. tostring(darkness.val))
    widgets["Copy look as text"]:DoClick()
    assert(parsed[clipboard].version==2 and encode(parsed[clipboard].look)==encode(upgraded))
    assert(files[path]==oldText)
end
local function refused(bad)
    local before=#calls
    files[path]=bad
    start:pick("My look (my-sky_1)")
    assert(#calls==before and notes[#notes]:find("my-sky_1.json refused",1,true))
    widgets["Paste a look"]:DoClick() prompt(bad)
    assert(#calls==before and notes[#notes]:find("pasted text refused",1,true))
end
refused("not json") refused(string.rep("x",8193))
for _,modify in ipairs({
    function(d) d.version=3 end, function(d) d.extra=1 end, function(d) d.look.cloudColor={1,1} end,
    function(d) d.look.cloudColor={0,1,1,1} end, function(d) d.look.cloudColor={-0.1,0,0} end,
    function(d) d.look.cloudDensity="20" end, function(d) d.look.fogVisibilityMeters=50001 end,
    function(d) d.look.aerosolDensity=100.01 end,
    function(d) d.look.mieAbsorption=nil end, function(d) d.look.mieAbsorption=0.0044 end,
    function(d) d.look.mieAbsorption={0.0044,0.0044} end, function(d) d.look.mieAbsorption={0.001,0.002,0.001} end,
    function(d) d.look.mieAbsorption={0.01321,0.01321,0.01321} end,
    function(d) d.version=1 d.look.mieAbsorption=nil d.look.cloudDensity=nil end,
    function(d) d.look.cloudLayer2Enable=1 end, function(d) d.look.cloudDensity=nil end,
    function(d) d.look["rays.strength"]=1 end, function(d) d.look["rtx.volumetrics.enable"]=true end,
    function(d) d.look.cloudDensity=math.huge end, function(d) d.look.cloudDensity=0/0 end,
}) do
    local doc=duplicate(original) modify(doc)
    refused(util.TableToJSON(doc,false))
end
local dup=text:gsub('"version":2','"version":1,"version":2')
parsed[dup]=original refused(dup) -- native JSON decoding may collapse the two keys
local nul=text:gsub('"version":2','"unrecognised":null,"version":2')
parsed[nul]=original refused(nul)
local comma=text:gsub("}$",",}")
parsed[comma]=original refused(comma)
local comment="/*weather*/"..text
parsed[comment]=original refused(comment)
files[path]=text start:pick("My look (my-sky_1)") tick(2)
widgets["Delete saved look"]:DoClick() assert(files[path]) confirm()
assert(not files[path] and not start.choices["My look (my-sky_1)"] and numos("rays.strength")=="1.4")
-- A replacement interrupted between the two renames left the previous look on disk.
files[folder.."my-sky_1.old.txt"]=text
NATIVELOADER_SKY.buildEnhancedPanel(form())
assert(files[path]==text and not files[folder.."my-sky_1.old.txt"])
assert(widgets["Start from"].choices["My look (my-sky_1)"])
