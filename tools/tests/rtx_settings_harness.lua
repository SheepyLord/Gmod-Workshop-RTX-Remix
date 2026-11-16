-- Regression for the RTX fixes' Utilities > RTX Remix pages (ADR 0212, 0213), without a game: the ToPBR page says
-- what it does next to Imported game PBR and has no switch that does nothing; the Auto-Categorization page's World
-- Geometry help names what it covers and the player's own rtx.conf choices.
-- Usage: luajit tools/tests/rtx_settings_harness.lua <cl_rtx_settings.lua>
local path = assert(arg[1], "usage: rtx_settings_harness.lua <cl_rtx_settings.lua>")
BRANCH, CLIENT = "x86-64", true
file = {Exists = function() return false end}
function CreateClientConVar() return {GetBool = function() return true end} end
function GetConVar() return {GetBool = function() return false end, GetInt = function() return 0 end} end
local commands = {}
function RunConsoleCommand(name, value) commands[#commands + 1] = {name, value} end
function Color(...) return {...} end
cvars = {AddChangeCallback = function() end}
local pages, hooks = {}, {}
hook = {Add = function(event, name, fn) hooks[name] = fn end}
spawnmenu = {AddToolMenuOption = function(tab, category, id, title, _, _, build)
    assert(tab == "Utilities" and category == "RTX Remix")
    pages[id] = {title = title, build = build}
end}
dofile(path)
for _, fn in pairs(hooks) do if type(fn) == "function" then pcall(fn) end end

local function Build(id)
    local page = assert(pages[id], id)
    local items = {}
    local panel = {}
    function panel:ClearControls() end
    function panel:CheckBox(label, convar) local w = {SetEnabled = function() end} items[#items + 1] = {kind = "check", label = label, convar = convar} return w end
    function panel:ControlHelp(text) items[#items + 1] = {kind = "help", text = text} end
    function panel:Help(text) items[#items + 1] = {kind = "help", text = text} end
    function panel:Button(label) local w = {SetEnabled = function() end} items[#items + 1] = {kind = "button", label = label} return w end
    function panel:NumSlider(label, convar) items[#items + 1] = {kind = "slider", label = label, convar = convar} return {SetEnabled = function() end} end
    function panel:ComboBox(label, convar)
        local combo = {kind = "combo", label = label, convar = convar, choices = {}}
        function combo:SetSortItems(sort) self.sorted = sort end
        function combo:AddChoice(text, data) self.choices[#self.choices + 1] = {text = text, data = data} end
        function combo:ChooseOptionID(index) self.chosen = index end
        items[#items + 1] = combo
        return combo
    end
    page.build(panel)
    return page.title, items
end
local function Has(items, kind, field, text)
    for _, item in ipairs(items) do if item.kind == kind and item[field] and item[field]:find(text, 1, true) then return item end end
end

local title, items = Build("RTX_Client_ToPBR")
-- The user's request of 2026-11-16 (ADR 0229): marked experimental, the map's own surfaces by default.
assert(title == "Map and prop PBR (ToPBR, experimental)", title)
assert(items[1].kind == "help" and items[1].text == "Experimental feature.", "the page opens with the experimental note")
local enable = assert(Has(items, "check", "label", "Enable ToPBR (experimental)"))
assert(enable.convar == "rtx_topbr_enabled")
local range = assert(Has(items, "combo", "label", "Apply to"))
assert(range.sorted == false, "the ranges keep their order")
assert(#range.choices == 3 and range.choices[1].data == 0 and range.choices[2].data == 1 and range.choices[3].data == 2)
assert(range.choices[1].text == "The map's own surfaces (default)" and range.chosen == 1, "the map's own surfaces by default")
range.OnSelect(range, 2, range.choices[2].text, range.choices[2].data)
assert(commands[#commands][1] == "rtx_topbr_scope" and commands[#commands][2] == "1", "a choice sets rtx_topbr_scope")
assert(Has(items, "help", "text", "By default only the map's own surfaces are converted"))
assert(Has(items, "help", "text", "A narrower range removes what a wider one converted."))
for _, item in ipairs(items) do
    assert(item.convar ~= "rtx_topbr_metallic", "the metallic switch changes nothing since R11 and is not on the page")
    assert(not (item.text or ""):find("map reload", 1, true), "enabling needs no map reload")
end
assert(Has(items, "help", "text", "Imported characters use Imported game PBR instead."))
assert(Has(items, "help", "text", "A real PBR mod for a texture always wins over it."))
assert(Has(items, "help", "text", "rtx-remix/mods/~gmod_topbr"))
assert(Has(items, "check", "label", "Debug Output") and Has(items, "button", "label", "Clear Cache"))

title, items = Build("RTX_Client_AutoCategorization")
assert(title == "Auto-Categorization", title)
local world = assert(Has(items, "check", "label", "World Geometry"))
assert(world.convar == "rtx_auto_categorize_world")
assert(Has(items, "help", "text", "walls, floors, ceilings, displacements and static props"))
assert(Has(items, "help", "text", "save to rtx.conf is never put back in it"))
io.write("PASS RTX settings pages: ToPBR is marked experimental, its range starts at the map's own surfaces, names Imported game PBR, no dead metallic switch, no map reload; World Geometry help and the rtx.conf rule\n")
