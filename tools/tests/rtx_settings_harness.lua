-- Regression for the RTX fixes' Utilities > RTX Remix pages (ADR 0212, 0213), without a game: the ToPBR page says
-- what it does next to Imported game PBR and has no switch that does nothing; the Auto-Categorization page's World
-- Geometry help names what it covers and the player's own rtx.conf choices.
-- Usage: luajit tools/tests/rtx_settings_harness.lua <cl_rtx_settings.lua>
local path = assert(arg[1], "usage: rtx_settings_harness.lua <cl_rtx_settings.lua>")
BRANCH, CLIENT = "x86-64", true
file = {Exists = function() return false end}
function CreateClientConVar() return {GetBool = function() return true end} end
function GetConVar() return {GetBool = function() return false end} end
function RunConsoleCommand() end
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
    page.build(panel)
    return page.title, items
end
local function Has(items, kind, field, text)
    for _, item in ipairs(items) do if item.kind == kind and item[field] and item[field]:find(text, 1, true) then return item end end
end

local title, items = Build("RTX_Client_ToPBR")
assert(title == "Map and prop PBR (ToPBR)", title)
local enable = assert(Has(items, "check", "label", "Enable ToPBR for maps and props"))
assert(enable.convar == "rtx_topbr_enabled")
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
io.write("PASS RTX settings pages: ToPBR names maps and props beside Imported game PBR, no dead metallic switch, no map reload; World Geometry help and the rtx.conf rule\n")
