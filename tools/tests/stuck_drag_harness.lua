-- Runs companion/nativeloader/lua/autorun/client/nativeloader_dragdrop.lua against a mocked GMod drag and drop.
-- Arguments: the Lua file, a scenario. Prints "PASS <scenario>" or fails with an assertion.
local source, scenario = ...
local hooks = {}
local log = {}
local function note(text) log[#log + 1] = text end

hook = {Add = function(event, name, fn) hooks[event .. ":" .. name] = fn end}
SERVER = false
istable = function(v) return type(v) == "table" end
isfunction = function(v) return type(v) == "function" end
isnumber = function(v) return type(v) == "number" end
IsValid = function(v) return type(v) == "table" and v.valid == true end
MOUSE_LEFT, MOUSE_RIGHT = 107, 108
local frame = 0
FrameNumber = function() return frame end
ErrorNoHalt = function(text) log[#log + 1] = "error" end

local cursor, buttons = true, {}
vgui = {CursorVisible = function() return cursor end}
input = {IsMouseDown = function(code) return buttons[code] == true end}

local function panel(name, visible, parent)
    local p = {valid = true, name = name, visible = visible, parent = parent}
    function p:IsVisible() return self.visible end
    function p:GetParent() return self.parent end
    function p:MouseCapture(on) note(self.name .. ":capture:" .. tostring(on)) end
    return p
end

local world = panel("world", true, nil)
local spawnmenu = panel("spawnmenu", true, world)
local canvas = panel("canvas", true, spawnmenu)
local icon = panel("icon", true, canvas)

dragndrop = {}
function dragndrop.Clear()
    note("Clear")
    dragndrop.m_Dragging, dragndrop.m_DraggingMain, dragndrop.m_DragWatch = nil, nil, nil
    dragndrop.m_MouseCode, dragndrop.m_DropMenu = 0, nil
end
function dragndrop.StopDragging()
    note("StopDragging")
    dragndrop.Clear()
end
dragndrop.Clear()
log = {}

local function dragging()
    dragndrop.m_Dragging, dragndrop.m_DraggingMain, dragndrop.m_MouseCode = {icon}, icon, MOUSE_LEFT
end

local function think() frame = frame + 1 hooks["Think:nativeloader_stuck_drag"]() end
local function expect(list)
    local got = table.concat(log, ",")
    assert(got == table.concat(list, ","), scenario .. ": expected [" .. table.concat(list, ",") .. "], got [" .. got .. "]")
end

assert(loadfile(source))()
assert(hooks["Think:nativeloader_stuck_drag"], "no Think hook")

if scenario == "idle" then
    -- Nothing dragged: the hook neither reads the cursor's state nor touches dragndrop.
    vgui.CursorVisible = function() error("cursor read while idle") end
    think()
    expect({})
elseif scenario == "hidden_cursor" then
    -- The spawn menu closed with the icon held: no cursor, so nothing can receive the release.
    dragging()
    buttons[MOUSE_LEFT] = true
    cursor = false
    think()
    expect({"StopDragging", "Clear", "icon:capture:false"})
    log = {}
    think() -- the drag is over: nothing more
    expect({})
elseif scenario == "visible" then
    -- An ordinary drag inside the open spawn menu is left alone.
    dragging()
    think()
    buttons[MOUSE_LEFT] = true
    think()
    expect({})
elseif scenario == "hidden_panel" then
    -- Another menu still shows the cursor, the spawn menu is hidden and the button is up: ended after two frames.
    dragging()
    spawnmenu.visible = false
    think()
    think()
    expect({})
    think()
    expect({"StopDragging", "Clear", "icon:capture:false"})
elseif scenario == "hidden_then_drop" then
    -- The spawn menu hides the source panel in the frame the drop arrives: GMod drops it, nothing is cancelled.
    dragging()
    spawnmenu.visible = false
    think()
    dragndrop.StopDragging() -- GMod's own drop
    log = {}
    spawnmenu.visible = true
    think()
    think()
    think()
    expect({})
elseif scenario == "stop_error" then
    -- Another add-on's OnStopDragging fails: dragndrop is still cleared and the mouse let go, once.
    dragging()
    function dragndrop.StopDragging() note("StopDragging") error("an add-on's OnStopDragging failed") end
    cursor = false
    think()
    expect({"StopDragging", "error", "Clear", "icon:capture:false"})
    log = {}
    think()
    expect({})
elseif scenario == "hidden_panel_held" then
    -- The spawn menu is hidden but the button is still held: GMod may still drop it.
    dragging()
    spawnmenu.visible = false
    buttons[MOUSE_LEFT] = true
    think()
    expect({})
elseif scenario == "drop_menu" then
    -- A right-drag's menu is open: the drag waits for a choice, even with no cursor.
    dragging()
    dragndrop.m_MouseCode = MOUSE_RIGHT
    dragndrop.m_DropMenu = panel("menu", true, world)
    cursor = false
    think()
    expect({})
elseif scenario == "watch" then
    -- A press that has not become a drag yet, and the menu closed: the press is cleared.
    dragndrop.m_DragWatch, dragndrop.m_MouseCode = icon, MOUSE_LEFT
    cursor = false
    think()
    expect({"Clear", "icon:capture:false"})
elseif scenario == "removed_panel" then
    -- The dragged panel was removed (a spawn-menu rebuild) while the cursor is still visible and the button is up.
    dragging()
    icon.valid = false
    think()
    -- Nothing valid is dragged: the drag paints nothing and is left for GMod (its next click stops it).
    expect({})
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
