-- Private controller fixture: one tap per key, held on that cell through release.
local Typing={}
function Typing.New()
    local keys={"b","a","r","r","e","l","Enter"}
    local index,phase,at,aimed=1,"aim",0,0
    local text,seenFrame="",nil
    local self={}
    function self.Key() return keys[index] end
    function self.Down() return phase=="press" end
    function self.Update(frame,value,ready,hovered)
        if frame==seenFrame then return end seenFrame=frame
        text=value or ""
        if phase=="aim" then
            aimed=ready and hovered and aimed+1 or 0
            if aimed>=2 then phase,at="press",frame end
        elseif phase=="press" and frame-at>=3 then phase,at="release",frame
        elseif phase=="release" and frame-at>=3 then
            local wanted=("barrel"):sub(1,math.min(index,6))
            if text==wanted then
                if index==#keys then phase="done"
                else index,phase,aimed=index+1,"aim",0 end
            end -- A missed/wrong character remains failed; never retry or set text.
        end
    end
    function self.State() return {index=index,key=keys[index],phase=phase,text=text} end
    return self
end
return Typing
