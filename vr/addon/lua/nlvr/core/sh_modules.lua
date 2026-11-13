-- Resource ownership shared by the two realms. Nothing is installed by including this file.
local Registry = {}
function Registry.New(core, fatal)
    local self = {core = core, entries = {}, current = nil}
    function self:Cleanup(entry)
        for i = #entry.cleanups, 1, -1 do
            local ok, err = pcall(entry.cleanups[i])
            if not ok then MsgN("[nlvr] cleanup " .. entry.module.name .. ": " .. tostring(err)) end
        end
        entry.cleanups = {}
    end
    function self:StopEntry(entry)
        if entry.stopped then return end
        entry.stopped, entry.active = true, false
        local previous = self.current
        self.current = entry
        local ok, err = pcall(entry.module.Stop)
        self.current = previous
        self:Cleanup(entry)
        if not ok then MsgN("[nlvr] stop " .. entry.module.name .. ": " .. tostring(err)) end
    end
    function self:Call(entry, fn, ...)
        if not entry.active then return end
        local previous = self.current
        self.current = entry
        local ok, a, b, c = pcall(fn, ...)
        self.current = previous
        if not ok then
            MsgN("[nlvr] module " .. entry.module.name .. ": " .. tostring(a))
            self:StopEntry(entry) -- a failed hook cannot run or log again
            if entry.module.name == "core" and fatal then fatal(tostring(a)) end
            return
        end
        return a, b, c
    end
    function self:Own(cleanup, entry)
        entry = entry or assert(self.current, "Resource registration needs a module context")
        assert(entry.active, "Module has stopped")
        entry.cleanups[#entry.cleanups + 1] = cleanup
        return cleanup
    end
    function self:Add(module)
        assert(type(module) == "table" and type(module.name) == "string" and
            type(module.order) == "number" and type(module.Start) == "function" and
            type(module.Stop) == "function", "Invalid VR module")
        for _, entry in ipairs(self.entries) do assert(entry.module.name ~= module.name, "Duplicate VR module") end
        local entry = {module = module, active = true, cleanups = {}}
        local ctx = setmetatable({core = core, native = core.Native, name = module.name}, {__index = core})
        function ctx.cleanup(fn) return self:Own(fn, entry) end
        function ctx.hook(event, fn)
            local id = "nlvr." .. module.name
            hook.Add(event, id, function(...) return self:Call(entry, fn, ...) end)
            ctx.cleanup(function() hook.Remove(event, id) end)
        end
        function ctx.timer(name, delay, repetitions, fn)
            local id = "nlvr." .. module.name .. "." .. name
            timer.Create(id, delay, repetitions, function(...) return self:Call(entry, fn, ...) end)
            ctx.cleanup(function() timer.Remove(id) end)
        end
        function ctx.On(name, fn) return core._On(entry, name, fn) end
        if core._Mover then function ctx.mover(priority, fn) return core._Mover(entry, priority, fn) end end
        if core._Resolver then function ctx.resolver(priority, fn) return core._Resolver(entry, priority, fn) end end
        entry.ctx = ctx
        self.entries[#self.entries + 1] = entry
        table.sort(self.entries, function(a, b) return a.module.order < b.module.order end)
        return entry
    end
    function self:Start()
        for _, entry in ipairs(self.entries) do
            local previous = self.current
            self.current = entry
            local ok, err = pcall(entry.module.Start, entry.ctx)
            self.current = previous
            if not ok then self:StopEntry(entry) error(entry.module.name .. ": " .. tostring(err)) end
        end
    end
    function self:Stop()
        for i = #self.entries, 1, -1 do self:StopEntry(self.entries[i]) end
    end
    return self
end
return Registry
