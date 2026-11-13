local root=...
local Typing=assert(loadfile(root.."/companion/tests/vr_fixture_typing.lua"))()
local t=Typing.New()
for frame=1,5 do t.Update(frame,"",true,false) assert(not t.Down()) end
t.Update(6,"",true,true) t.Update(7,"",true,true) assert(t.Down())
t.Update(10,"",true,true) assert(not t.Down() and t.Key()=="b")
t.Update(13,"",true,true) assert(t.Key()=="b" and not t.Down(),"missing text must not be hidden by a retry")
t.Update(14,"b",true,true) assert(t.Key()=="a")
local field,pressed,presses="",nil,0
t=Typing.New()
for frame=1,180 do
    local key=t.Key() local before=t.Down()
    t.Update(frame,field,true,true)
    if t.Down() and not before then pressed=key presses=presses+1 end
    if not t.Down() and before then
        assert(t.Key()==pressed,"fixture changed target before releasing")
        if pressed~="Enter" then field=field..pressed end
    end
    if t.State().phase=="done" then break end
end
assert(field=="barrel" and presses==7 and t.State().phase=="done")
print("PASS controller typing")
