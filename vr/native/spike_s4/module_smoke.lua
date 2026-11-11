-- Production module only; the current PoC runtime intentionally has no rtxvr exports.
local loaded,err=pcall(require,'nlvr')
print('NL_D_MODULE_REQUIRE',loaded,tostring(err))
if not loaded then return end
print('NL_D_MODULE_VERSION',nlvr.Version())
print('NL_D_MODULE_PROBE',util.TableToJSON(nlvr.Probe()))
print('NL_D_MODULE_INITIAL',nlvr.State())
print('NL_D_MODULE_OFF_FRAME',nlvr.BeginFrame()==nil)
print('NL_D_MODULE_START',nlvr.Start())
local started=SysTime()
timer.Create('NL.D.ModuleSmoke',0.05,0,function()
  local state,detail=nlvr.State()
  if state=='failed' or SysTime()-started>8 then
    timer.Remove('NL.D.ModuleSmoke')
    print('NL_D_MODULE_RESULT',state,detail)
    print('NL_D_MODULE_STOP1',nlvr.Stop())
    print('NL_D_MODULE_STOP2',nlvr.Stop())
    print('NL_D_MODULE_FINAL',nlvr.State())
    print('NL_D_MODULE_STOPPED_FRAME',nlvr.BeginFrame()==nil)
    print('NL_D_MODULE_DONE')
  end
end)
