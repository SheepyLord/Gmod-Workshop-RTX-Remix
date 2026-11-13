-- Development probe only: wait for new overlay targets to have a painted render frame.
local Queue={}
function Queue.New(options)
    local self,pending,lastFrame={}, {}, nil
    function self.Request(...)
        pending[#pending+1]={args={...},frame=options.Frame(),time=options.Now()}
        return true
    end
    function self.Pump()
        local entry=pending[1] local frame=options.Frame()
        if not entry or frame==lastFrame or frame<=entry.frame or not options.Running() then return end
        local inventory,expected=options.Inventory()
        for _,item in pairs(inventory) do
            if item.required and (not item.handle or not item.info or not item.info.visible) or
                item.info and item.info.visible and frame-(item.created_frame or -1000000)<2 then
                if options.Now()-entry.time>1 then
                    table.remove(pending,1) options.Error("Capture source did not become ready: "..entry.args[1])
                end
                return
            end
        end
        table.remove(pending,1) lastFrame=frame
        options.Describe(entry.args[1],inventory,expected)
        local ok,result,detail=pcall(options.Forward,unpack(entry.args))
        if not ok or result==false or result==nil and detail then
            options.Error("Capture dispatch failed: "..tostring(detail or result))
        end
    end
    function self.Stop()
        for _,entry in ipairs(pending) do options.Error("Capture ended before dispatch: "..entry.args[1]) end
        pending={}
    end
    return self
end
return Queue
