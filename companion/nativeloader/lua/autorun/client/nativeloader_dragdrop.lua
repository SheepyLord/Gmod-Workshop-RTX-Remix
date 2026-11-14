-- R25: a spawn-menu icon left on the screen for the rest of a session.
-- GMod's drag and drop (lua/includes/extensions/client/panel/dragdrop.lua) ends a drag only when the dragged panel
-- receives the mouse release; its own "no button is held any more" check is commented out. When the spawn menu closes
-- while an icon is held (Q released before the mouse button, or the icon moved 20 pixels on its way to a click), the
-- release goes to the game instead, the drag never ends, and the DrawOverlay hook "DragNDropPaint" keeps painting the
-- icon at the last cursor position. A drag needs a visible cursor, and a panel on screen or a held button: once that
-- is no longer so, it is ended here as GMod ends one (dragndrop.StopDragging) and the panel lets the mouse go.
-- ADR 0206: nothing in a start where this machine's loader did not activate RTX (NativeLoaderRTXStart, set by
-- !!!!nativeloader_engine_guard.lua, which runs first).
if NativeLoaderRTXStart and not NativeLoaderRTXStart() then return end
if SERVER then return end

local MAX_DEPTH = 64

-- The panel and every panel above it are visible (Panel:IsVisible reports only the panel's own flag).
local function shown(panel)
    local depth = 0
    while IsValid(panel) and depth < MAX_DEPTH do
        if not panel:IsVisible() then return false end
        panel = panel:GetParent()
        depth = depth + 1
    end
    return true
end

local function held(code)
    return isnumber(code) and code ~= 0 and input.IsMouseDown(code) == true
end

-- Whether the drag (or the press that may become one) can no longer end on its own, and the panel holding the mouse.
-- A hidden panel with the button up waits two frames: the spawn menu can hide the panel a drag comes from (its content
-- tree switches pages under a dragged icon) in the frame the game delivers the drop to it.
local hiddenSince
local function stuck(dnd)
    if IsValid(dnd.m_DropMenu) then hiddenSince = nil return false end -- a right-drag's menu is waiting for a choice
    local main = IsValid(dnd.m_DraggingMain) and dnd.m_DraggingMain or dnd.m_DragWatch
    if not vgui.CursorVisible() then return true, main end
    if shown(main) or held(dnd.m_MouseCode) then hiddenSince = nil return false end
    local frame = FrameNumber()
    if not hiddenSince then hiddenSince = frame return false end
    if frame - hiddenSince < 2 then return false end
    return true, main
end

-- Ends the drag as GMod does; another add-on's OnStopDragging or DragHoverEnd failing still leaves dragndrop cleared
-- (else this hook would meet the same drag, and the same error, every frame).
local function finish(dnd, dragging, main)
    hiddenSince = nil
    if dragging and isfunction(dnd.StopDragging) then
        local ok, err = pcall(dnd.StopDragging)
        if not ok then ErrorNoHalt("[nativeloader] ending a stuck drag: " .. tostring(err) .. "\n") end
    end
    if isfunction(dnd.Clear) and (dnd.m_Dragging ~= nil or dnd.m_DragWatch ~= nil) then dnd.Clear() end
    if IsValid(main) then pcall(main.MouseCapture, main, false) end
end

hook.Add("Think", "nativeloader_stuck_drag", function()
    local dnd = dragndrop
    if not istable(dnd) then return end
    local dragging = dnd.m_Dragging ~= nil
    if not dragging and not IsValid(dnd.m_DragWatch) then hiddenSince = nil return end
    local yes, main = stuck(dnd)
    if yes then finish(dnd, dragging, main) end
end)
