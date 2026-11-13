-- V2-N's owned-session feature proof, appended by the disposable launcher to the normal probe.
-- Uses no filesystem paths and changes no SteamVR binding or setting.
local id = "nlvr_n_feature_probe"
local api, events, create = nlvr, nlvr.Events, nlvr.OverlayCreate
local result = {keyboard_done = false, keyboard_closed = false}
local shown, hidden, binding, completed, object = false, false, false, false, nil
local function emit()
    local text = util.TableToJSON(result)
    assert(#text < 3000, "native feature witness exceeds the bounded console record")
    print("NLVR_N_FEATURES " .. text)
end
api.Events = function(...)
    local list, detail = events(...)
    if type(list) == "table" then
        for _, event in ipairs(list) do
            if event.type == "keyboard_done" and event.text == "V2 native keyboard" then result.keyboard_done = true end
            if event.type == "keyboard_closed" then result.keyboard_closed = true end
        end
    end
    return list, detail
end
hook.Add("PreRender", id, function()
    local state = api.State()
    if state == "off" and shown then
        api.Events = events
        hook.Remove("PreRender", id)
        result.cleaned = true
        emit()
        return
    end
    if state ~= "running" or completed then return end
    local test = api.TestState()
    local time = test and test.time or 0
    if time >= 7 and not shown then
        shown = true
        local facts = api.Info()
        -- Exact eyes/description without the large timing/status tables; Source lines cap at 4095 bytes.
        result.info = {eyes = facts.eyes, model = facts.model, tracking = facts.tracking, refresh = facts.refresh,
            ipd = facts.ipd, eye_width = facts.eye_width, eye_height = facts.eye_height, simulated = facts.simulated}
        result.show, result.show_detail = api.ShowKeyboard("", "V2 native proof", false, 128)
        result.keyboard_was_visible = api.Info().keyboard_visible
        object, result.create_detail = create("nlvr.v2n.proof", "V2 native proof")
        if object then
            result.tint, result.tint_detail = api.OverlayColor(object, 0.8, 0.9, 1)
            result.sort, result.sort_detail = api.OverlaySortOrder(object, 42)
            result.window, result.window_detail = api.OverlayWindow(object, true)
            result.overlay = api.OverlayInfo(object)
        end
    end
    if time >= 9.5 and shown and not hidden then
        hidden = true
        result.hide, result.hide_detail = api.HideKeyboard()
        result.keyboard_is_hidden = not api.Info().keyboard_visible
    end
    if time >= 10 and not binding then
        binding = true
        result.binding, result.binding_detail = api.OpenBindingUI()
    end
    if time >= 11 and shown and hidden and binding then
        if object then result.destroy, result.destroy_detail = api.OverlayDestroy(object) object = nil end
        completed = true
        emit()
    end
end)
