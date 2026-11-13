-- Reuse the existing engine fixture, with an extra branch in memory. Production guard is unmodified.
local root = ...
local input = assert(io.open(root .. "/tools/tests/render_guard_harness.lua", "rb"))
local fixture = input:read("*a") input:close()
local ending = 'else error("unknown scenario "..tostring(scenario)) end'
local at = assert(fixture:find(ending, 1, true), "guard fixture dispatch changed")
local extra = [[
elseif scenario=="vr_wrist" then
    local count=#rtCalls
    local blocked=#guard.blocked
    local make=assert(loadstring([=[
        return GetRenderTargetEx("nlvr_wrist_v1_769x257",769,257,RT_SIZE_LITERAL,
            MATERIAL_RT_DEPTH_NONE,0,0,IMAGE_FORMAT_RGBA8888)
    ]=],"@lua/nlvr/core/cl_overlay.lua"))
    local wrist=make()
    eq(wrist:Width(),769) eq(wrist:Height(),257)
    eq(#rtCalls,count+1,"one native allocation")
    eq(guard.allocation_bytes,790532,"RGBA8 colour bytes")
    local draw=assert(loadstring([=[
        return function(target)
            render.PushRenderTarget(target)
            render.Clear(12,18,26,235,false,false)
            cam.Start2D()
            surface.DrawTexturedRect(0,0,100,20)
            cam.End2D()
            render.PopRenderTarget()
        end
    ]=],"@lua/nlvr/modules/cl_hud.lua"))()
    draw(wrist)
    eq(#guard.blocked,blocked,"no guard refusal for ordinary 2D wrist painting")
    eq(cameraDepth,0) eq(#rtStack,0)
    eq(surfaceDraws,1,"native canvas draw reached")
    print("WRIST 769x257 RGBA8 790532 bytes; native allocation=1; guard refusals=0")
]]
fixture = fixture:sub(1, at - 1) .. extra .. fixture:sub(at)
assert(loadstring(fixture, "@" .. root .. "/tools/tests/render_guard_harness.lua"))(
    root .. "/companion/nativeloader/lua/autorun/_nativeloader_guard.lua", "vr_wrist")
