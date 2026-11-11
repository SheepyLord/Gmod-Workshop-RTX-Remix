-- Disposable S4 driver. Sent through poc_session.py --lua, never installed as an add-on.
require('nlvrs4')
print('NL_S4_MODE',GetConVar('mat_queue_mode'):GetInt())
print('NL_S4_LAYOUT',util.TableToJSON(nlvrs4.Layout()))
local frame=0
local accepted=0
local target=GetRenderTarget('nlvrs4_333_197',333,197,false)
print('NL_S4_TARGET',target:Width(),target:Height())
hook.Add('PostRender','NLVR.S4',function()
  frame=frame+1
  if frame==1 then print('NL_S4_RENDER_LAYOUT',util.TableToJSON(nlvrs4.Layout())) end
  if frame<=120 then
    if nlvrs4.Queue(frame,0) then accepted=accepted+1 end
    render.PushRenderTarget(target)
    cam.Start2D()
    surface.SetDrawColor(20+frame%200,40,100,255)
    surface.DrawRect(0,0,333,197)
    cam.End2D()
    if frame==1 then print('NL_S4_TARGET_LAYOUT',util.TableToJSON(nlvrs4.Layout())) end
    if nlvrs4.Queue(frame,1) then accepted=accepted+1 end
    render.PopRenderTarget()
    if nlvrs4.Queue(frame,2) then accepted=accepted+1 end
  end
  if frame==145 then
    hook.Remove('PostRender','NLVR.S4')
    local records=nlvrs4.Records()
    if #records==0 then print('NL_S4_RECORDS','[]') end
    for i=1,#records,16 do
      local batch={}
      for j=i,math.min(i+15,#records) do batch[#batch+1]=records[j] end
      print('NL_S4_RECORDS',util.TableToJSON(batch))
    end
    print('NL_S4_ACCEPTED',accepted,360)
    print('NL_SHOT_DONE')
  end
end)
