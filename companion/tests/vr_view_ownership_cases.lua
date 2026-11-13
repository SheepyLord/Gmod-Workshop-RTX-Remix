return function(e,cases,helpers)
    local function library(known)
        local saved={}
        for _,k in ipairs({"GetTable","GetULibTable","Add","Remove","Call","Run"}) do saved[k]=hook[k] end
        local fixture=assert(loadfile(e.root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",e.hooks)
        if not known then fixture.GetULibTable=nil end
        for _,k in ipairs({"GetTable","GetULibTable","Add","Remove","Call","Run"}) do hook[k]=fixture[k] end
        return function() for _,k in ipairs({"GetTable","GetULibTable","Add","Remove","Call","Run"}) do hook[k]=saved[k] end end
    end
    function cases.f_view_ulib()
        local restore=library(true)
        local competing=0
        hook.Add("CalcView","competitor",function() competing=competing+1 return {origin=Vector(9999,0,0)} end,-2)
        e.running()
        local v=helpers.view()
        assert(v and v.origin.x~=9999 and competing==0,"ULib competitor overrode the VR view")
        hook.Add("CalcView","late",function() return {origin=Vector(8888,0,0)} end,-1)
        hook.Remove("CalcView","competitor") e.step()
        v=helpers.view() assert(v.origin.x~=8888,"late ULib hook escaped isolation")
        NativeLoaderVR.Stop()
        hook.Add("CalcView","flat_monitor",function() return {origin=Vector(9999,0,0)} end,-2)
        local flat=hook.Run("CalcView",e.player,e.player.feet+e.player.offset,Angle(),90,1,9000)
        assert(flat.origin.x==8888,"deferred ULib registrations not restored")
        hook.Remove("CalcView","flat_monitor") hook.Remove("CalcView","late") restore() e.clean()
    end
    local function lifecycle(ulib)
        local restore=ulib and library(true) or function() end
        for i=1,2 do
            e.running() assert(helpers.view(),"VR view absent") NativeLoaderVR.Stop()
            assert(type(hook.GetTable().CalcView)=="table","Exit removed ULib's backward table")
            hook.Add("CalcView","after_exit",function() return {origin=Vector(123,0,0)} end)
            assert(hook.Run("CalcView").origin.x==123)
            hook.Remove("CalcView","after_exit")
        end
        restore() e.clean()
    end
    function cases.f_view_ulib_lifecycle() lifecycle(true) end
    function cases.f_view_stock_lifecycle() lifecycle(false) end
    local function removed(ulib)
        local restore=ulib and library(true) or function() end
        e.running()
        for id in pairs(hook.GetTable().CalcView) do hook.Remove("CalcView",id) end
        if hook.GetULibTable then
            local levels=hook.GetULibTable().CalcView
            for priority=-2,2 do for id in pairs(levels and levels[priority] or {}) do hook.Remove("CalcView",id) end end
        end
        e.step() hook.Run("PreRender")
        assert(NativeLoaderVR.state=="failed","removing the private dispatch did not fail VR safely")
        NativeLoaderVR.Stop() restore() e.clean()
    end
    function cases.f_view_removed_stock() removed(false) end
    function cases.f_view_removed_ulib() removed(true) end
    function cases.f_view_ulib_detached_dispatch()
        local restore=library(true) local get=hook.GetULibTable local shadow={}
        hook.GetULibTable=function()
            if not shadow.CalcView and get().CalcView then
                shadow.CalcView={}
                for n=-2,2 do shadow.CalcView[n]={} for id,entry in pairs(get().CalcView[n]) do shadow.CalcView[n][id]=entry end end
            end
            return shadow
        end
        e.running()
        assert(NativeLoaderVR.state=="failed","ULib-shaped tables without authoritative dispatch were accepted")
        NativeLoaderVR.Stop() restore() e.clean()
    end
    function cases.f_view_ulib_no_shortcircuit()
        local restore=library(true) local call=hook.Call
        hook.Call=function(event,gm,...)
            local value=call(event,nil,...)
            if gm and gm[event] then gm[event](gm,...) end
            return value
        end
        e.running()
        assert(NativeLoaderVR.state=="failed","ULib-shaped dispatch leaked into the gamemode after a view return")
        NativeLoaderVR.Stop() restore() e.clean()
    end
    function cases.f_view_unknown()
        local restore=library(false)
        hook.Add("CalcView","competitor",function() return {origin=Vector(9999,0,0)} end)
        e.running()
        assert(NativeLoaderVR.state=="failed","unsupported detached hook library must refuse VR safely")
        hook.Remove("CalcView","competitor") restore() e.clean()
    end
    function cases.f_view_ulib_copy()
        local restore=library(true) local get=hook.GetTable
        hook.GetTable=function()
            local out={} for event,list in pairs(get()) do
                out[event]={} for id,fn in pairs(list) do out[event][id]=fn end
            end return out
        end
        hook.Add("CalcView","copy_competitor",function() return {origin=Vector(9999,0,0)} end,-2)
        e.running() local v=helpers.view() assert(v and v.origin.x~=9999)
        NativeLoaderVR.Stop() hook.Remove("CalcView","copy_competitor") restore() e.clean()
    end
    function cases.f_view_reentry()
        e.running() local old=e.api.SetFrameCamera local nested,calls
        e.api.SetFrameCamera=function(...)
            calls=(calls or 0)+1
            assert(calls==1,"CalcView re-entered camera submission")
            nested=helpers.view()
            return old(...)
        end
        helpers.view() assert(nested==false,"reentry must not reach competing/gamemode views")
        e.api.SetFrameCamera=old NativeLoaderVR.Stop() e.clean()
    end
end
