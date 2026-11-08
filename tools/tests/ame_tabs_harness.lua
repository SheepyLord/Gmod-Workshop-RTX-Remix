-- Loads the Advanced Material Editor's real RTX editor panel (cl_76_rtx_editor.lua) and switches its
-- sheets the way Derma does (OnActiveTabChanged before the sheet records the new tab), R23 item 4.
-- See the adjacent .md.
local root = ...
local file = root .. "/packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_76_rtx_editor.lua"

local PANEL
local noop = setmetatable({}, { __index = function() return function() end end })
AdvMat = setmetatable({}, { __index = function() return nil end })
vgui = { Register = function(name, panel) if name == "AdvMatRTXEditor" then PANEL = panel end end }
function IsValid(value) return type(value) == "table" and not value.removed end
local errors = {}
function ErrorNoHaltWithStack(message) errors[#errors + 1] = tostring(message) end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
setmetatable(_G, { __index = function(_, name)
    -- Globals the file reads at load time and does not call here (surface, draw, hook...).
    if name == "L" then return nil end
    return noop
end })
dofile(file)
assert(PANEL, "the editor panel registered")
setmetatable(_G, nil)

-- A DPropertySheet as Derma's dpropertysheet.lua:212-234 orders it.
local function sheet()
    local s = { tabs = {} }
    function s:GetActiveTab() return self.m_pActiveTab end
    function s:SetActiveTab(active)
        if self.m_pActiveTab == active then return end
        if self.m_pActiveTab then self:OnActiveTabChanged(self.m_pActiveTab, active) end
        self.m_pActiveTab = active
    end
    return s
end

local function editor()
    local material, source, graph = { name = "Material" }, { name = "Source" }, { name = "Graph" }
    local e = setmetatable({}, { __index = PANEL })
    e.Tabs = sheet()
    e.Tabs.m_pActiveTab = material
    e.Tabs.OnActiveTabChanged = function(_, old, new) e:OnWorkspaceChanged(old, new) end
    e.SourceSheet = { Tab = source }
    e.tabs = { material = material, source = source, graph = graph }
    e.calls = {}
    e.MaterialLines = {}
    for i = 0, 7 do e.MaterialLines[i] = { index = i } end
    e.MaterialList = { SelectItem = function(_, line) e.calls[#e.calls + 1] = { "row", line.index, e:IsSourceTabActive() } end }
    function e:CanonicalSlot(index) return self.aliases and self.aliases[index] or index end
    function e:SelectSourceMaterial(index)
        self.SourceDisplaySelected = index
        self.calls[#self.calls + 1] = { "source", index, self:IsSourceTabActive() }
        return true
    end
    function e:SelectMaterial(index, force)
        self.Selected = index
        self.calls[#self.calls + 1] = { "pbr", index, self:IsSourceTabActive(), force == true }
    end
    function e:UpdateActionMode() self.calls[#self.calls + 1] = { "mode", self:IsSourceTabActive() } end
    return e
end

local function find(calls, kind)
    for _, call in ipairs(calls) do if call[1] == kind then return call end end
end

-- Material -> Source / VMT: the PBR selection is handed over, while the Source sheet counts as active.
local e = editor()
e.Selected, e.SourceDisplaySelected = 3, 1
e.Tabs:SetActiveTab(e.tabs.source)
local call = find(e.calls, "source")
assert(call and call[2] == 3 and call[3] == true, "Source / VMT shows the material being edited")
local row = find(e.calls, "row")
assert(row and row[2] == 3, "its row is the selected one")
assert(e.SwitchingTo == nil and e:IsSourceTabActive(), "the sheet is active afterwards")

-- Source / VMT -> Material: the Source selection is handed back (its canonical PBR slot).
e.calls = {}
e.SourceDisplaySelected = 5
e.Tabs:SetActiveTab(e.tabs.material)
call = find(e.calls, "pbr")
assert(call and call[2] == 5 and call[3] == false and call[4] == true, "Material shows the Source sheet's material")
local mode = find(e.calls, "mode")
assert(mode and mode[2] == false, "the action bar is the Material sheet's")
assert(not e:IsSourceTabActive())

-- A shared texture identity: the Source row's canonical PBR owner.
e.Tabs:SetActiveTab(e.tabs.source)
e.calls = {}
e.aliases = { [6] = 2 }
e.SourceDisplaySelected = 6
e.Tabs:SetActiveTab(e.tabs.graph)
call = find(e.calls, "pbr")
assert(call and call[2] == 2, "the canonical owner of a shared identity")

-- Between PBR sheets nothing changes; an error inside never leaves the switch state behind.
e.calls = {}
e.Tabs:SetActiveTab(e.tabs.material)
call = find(e.calls, "pbr")
assert(call and call[2] == 2 and call[3] == false)
function e:SelectSourceMaterial() error("boom") end
e.Tabs:SetActiveTab(e.tabs.source)
assert(#errors == 1 and errors[1]:find("boom"), "the error is reported")
assert(e.SwitchingTo == nil, "the switch state is cleared")
print("PASS ame tabs")
