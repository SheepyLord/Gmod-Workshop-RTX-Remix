local Manager = {}
-- Reserved literal RGBA8/no-depth sizes. Both dimensions are odd; no two pairs may coincide.
Manager.Sizes = {wrist = {769, 257}, wrist_menu = {513, 515}, spawn = {1537, 1025}, context = {1281, 961},
    flat = {1921, 1081}, laser = {65, 1027}, teleport_arc = {1029, 259}, teleport_arc_2 = {81, 83},
    teleport_arc_3 = {85, 87}, teleport_target = {261, 263},
    vignette = {1031, 1033}, ghost_left = {265, 267}, ghost_right = {269, 271},
    gloves_left = {273, 275}, gloves_right = {277, 279}, ammo = {387, 129},
    wheel = {1035, 1037}, tool = {643, 133}, settings = {1283, 963}, flat_close = {131, 133}, keyboard = {1039, 391}}
function Manager.New(core)
    local self = {Sizes = Manager.Sizes, Objects = {}, NativeLimit = 32, SourceLimit = 16, GraceSeconds = 2}
    local sizes = {}
    local retired, live, requests, requestCount, requestFrame = {}, 0, {}, 0, nil
    local function budget(handle)
        local frame=FrameNumber and FrameNumber() or 0
        if frame~=requestFrame then requests,requestCount,requestFrame={},0,frame end
        if requests[handle] then return true end
        if requestCount>=self.SourceLimit then return false end
        requests[handle],requestCount=true,requestCount+1
        return true
    end
    local function invoke(method,...)
        local ok,result,detail=pcall(core.Native[method],...)
        if not ok then return false,result end
        if result==false or result==nil and detail~=nil then return false,detail end
        return true,result
    end
    local function checked(method, ...)
        local result, detail = core.Native[method](...)
        if result == false or (result == nil and detail ~= nil) then error(method .. ": " .. tostring(detail)) end
        return result
    end
    local function release(object)
        if not object.handle then return true end
        if not budget(object.handle) then return false end
        local ok=invoke("OverlayDestroy",object.handle)
        if not ok then return false end -- pending runtime queue may not have drained yet
        object.handle,object.bound,object.visible=nil,false,false live=live-1
        object.bindFrame,object.paintAfterBind=nil,false
        return true
    end
    local function warn(object,reason)
        if object.warned then return end
        object.warned=true
        MsgN("[nlvr] overlay "..object.key.." waiting: "..tostring(reason))
    end
    local function limited(detail)
        local value=tostring(detail)
        return value:find("overlay limit",1,true) or value:find("RTXVR error 8",1,true) or value:find("RTXVR_E_RESOURCES",1,true)
    end
    local function bind(object)
        if not budget(object.handle) then return false end
        local ok,detail
        if object.window then ok,detail=invoke("OverlayWindow",object.handle,true)
        else ok,detail=invoke("OverlaySource",object.handle,object.width,object.height) end
        object.sourceError=not ok and detail or nil
        if not ok then
            if not object.window and not limited(detail) then error("OverlaySource: "..tostring(detail)) end
            if object.window and not limited(detail) then object.windowRefused=detail or "Window source refused" end
            warn(object,detail) return false
        end
        object.bound=true
        -- Runtime copies are triggered by painting the matching target. A logical
        -- canvas may have been painted before its lazy/recreated handle existed.
        object.dirty,object.bindFrame,object.paintAfterBind=true,FrameNumber(),true
        checked("OverlayAttach",object.handle,object.device,object.pos,object.ang,object.metres)
        if object.alpha then checked("OverlayAlpha",object.handle,object.alpha) end
        if object.sort and core.Native.OverlaySortOrder then checked("OverlaySortOrder",object.handle,object.sort) end
        return true
    end
    local function acquire(object)
        if object.window and object.windowRefused then return false end
        if not object.handle then
            if live>=self.NativeLimit then
                local oldest
                for _,candidate in pairs(self.Objects) do
                    if candidate.handle and not candidate.wanted and
                        (not oldest or candidate.hiddenAt<oldest.hiddenAt) then oldest=candidate end
                end
                if oldest then release(oldest) end
            end
            if live>=self.NativeLimit then warn(object,"native handle budget") return false end
            -- A create without a source is harmless, but avoid accumulating such handles.
            local frame=FrameNumber and FrameNumber() or 0
            if requestFrame==frame and requestCount>=self.SourceLimit then return false end
            local ok,handle,detail=pcall(core.Native.OverlayCreate,
                object.key=="wrist" and "nativeloader.wrist.v1" or "nativeloader."..object.key,object.name)
            if not ok or not handle then
                local reason=detail or handle or "SteamVR could not create the overlay"
                if not limited(reason) then error(tostring(reason)) end
                warn(object,reason) return false
            end
            object.handle=handle live=live+1
        end
        if not object.bound and not bind(object) then return false end
        return true
    end
    function self.New(options)
        local w, h, key = options.width, options.height, options.key
        assert(type(key) == "string" and key ~= "" and not self.Objects[key], "Duplicate or empty overlay key")
        assert(type(w) == "number" and type(h) == "number" and w >= 1 and h >= 1 and
            w <= 4095 and h <= 4095 and w % 2 == 1 and h % 2 == 1, "Overlay dimensions must be odd integers up to 4095")
        for slot, size in pairs(self.Sizes) do
            if size[1] == w and size[2] == h then assert(key == slot, "Overlay size reserved for " .. slot) end
        end
        local sizeKey = w .. "x" .. h
        assert(not sizes[sizeKey], "Overlay size already in use")
        local object = {key = key, name = options.name or key, width = w, height = h, dirty = true, visible = false,
            device = options.device or "world", pos = options.pos or Vector(), ang = options.ang or Angle(),
            metres = options.metres or 1, paint = options.paint, clear = options.clear or {0, 0, 0, 0}}
        local entry = assert(core.Registry.current, "Create overlays in a module context")
        function object:Destroy()
            if self.destroyed then return end
            self.destroyed,self.wanted = true,false
            if self.handle then
                pcall(core.Native.OverlayShow, self.handle, false)
                if not release(self) then retired[#retired+1]=self end
            end
            sizes[sizeKey], core.Overlay.Objects[key] = nil, nil
        end
        core.Registry:Own(function() object:Destroy() end, entry)
        self.Objects[key], sizes[sizeKey] = object, object
        local targetName = key == "wrist" and "nlvr_wrist_v1_769x257" or "nlvr_" .. key .. "_" .. sizeKey
        object.target = GetRenderTargetEx(targetName, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)
        assert(object.target and object.target:Width() == w and object.target:Height() == h,
            "The render guard or engine refused the " .. w .. " x " .. h .. " overlay target")
        function object:Show(show)
            if self.destroyed then return end
            if not show and self.wanted then self.hiddenAt=RealTime() end
            self.wanted=show==true
            if show and not acquire(self) then self.visible=false return false end
            if self.handle then checked("OverlayShow", self.handle, show) end
            self.visible=show==true
            if show then self.warned=false end
            return true
        end
        function object:Place(device, pos, ang, metres)
            if self.destroyed then return end
            assert(device == "left" or device == "right" or device == "head" or device == "world", "Invalid overlay attachment")
            self.device, self.pos, self.ang, self.metres = device, Vector(pos.x, pos.y, pos.z), Angle(ang.p, ang.y, ang.r), metres or self.metres
            if self.handle then checked("OverlayAttach", self.handle, device, pos, ang, self.metres) end
        end
        function object:Alpha(alpha)
            if self.destroyed then return end
            self.alpha=alpha
            if self.handle then checked("OverlayAlpha", self.handle, alpha) end
        end
        function object:SortOrder(order)
            self.sort=order
            if self.handle and core.Native.OverlaySortOrder then checked("OverlaySortOrder",self.handle,order) end
        end
        function object:Window(enable)
            if not core.Native.OverlayWindow then return false,"Window overlays unavailable" end
            if enable and self.windowRefused then return false,self.windowRefused end
            if not enable then self.windowRefused=nil end
            self.window,self.bound=enable==true,false
            if self.handle then return bind(self) end
            return nil,"pending"
        end
        function object:WindowState()
            if self.windowRefused then return "refused",self.windowRefused end
            if self.window and self.bound and self.handle then return "ready" end
            return "pending"
        end
        function object:IsVisible()
            if not self.visible or not self.handle then return false end
            if not core.Native.OverlayVisible then return true end
            local ok,value=pcall(core.Native.OverlayVisible,self.handle)
            return ok and value==true
        end
        function object:Invalidate() if not self.destroyed then self.dirty = true end end
        object:Place(object.device, object.pos, object.ang, object.metres)
        if options.alpha ~= nil then object:Alpha(options.alpha) end
        return object
    end
    function self.Paint()
        for i=#retired,1,-1 do if release(retired[i]) then table.remove(retired,i) end end
        for _,object in pairs(self.Objects) do
            if object.handle and not object.wanted and object.hiddenAt and RealTime()-object.hiddenAt>=self.GraceSeconds then release(object) end
        end
        for _,object in pairs(self.Objects) do if object.wanted and not object.visible then object:Show(true) end end
        core.Emit("before_overlay_paint")
        for _, object in pairs(self.Objects) do
            if object.paintAfterBind and FrameNumber()>object.bindFrame then
                object.dirty,object.paintAfterBind=true,false
            end
            if object.dirty and not object.destroyed and object.paint then
                object.dirty = false
                render.PushRenderTarget(object.target)
                local in2D = false
                local ok, err = pcall(function()
                    local clear = object.clear
                    render.Clear(clear[1], clear[2], clear[3], clear[4], false, false)
                    cam.Start2D() in2D = true
                    object.paint(object, object.width, object.height)
                end)
                if in2D then cam.End2D() end
                render.PopRenderTarget()
                if not ok then core.Fail(tostring(err)) return end
            end
        end
    end
    function self.Hit(object, origin, direction)
        if object.destroyed or not object.visible then return end
        local basePos, baseAng = Vector(), Angle()
        if object.device ~= "world" then
            local pose = core.Pose[object.device]
            if not pose or not pose.valid then return end
            basePos, baseAng = pose.raw.pos, pose.raw.ang
        end
        local trackingPos, trackingAng = LocalToWorld(object.pos, object.ang, basePos, baseAng)
        local pos, ang = core.ToWorld(trackingPos, trackingAng)
        -- OpenVR's overlay XY plane maps to Source: right=-Y, up=Z, front normal=-X.
        local normal, right, up = -ang:Forward(), ang:Right(), ang:Up()
        local length = direction:Length()
        if length < 0.000001 then return end
        local ray = direction / length
        local denominator = ray:Dot(normal)
        if denominator >= -0.000001 then return end -- back face, parallel, or pointing away
        local distance = (pos - origin):Dot(normal) / denominator
        if distance < 0 then return end
        local point = origin + ray * distance - pos
        local width = object.metres * core.Space.scale
        local u, v = 0.5 + point:Dot(right) / width, 0.5 - point:Dot(up) / (width * object.height / object.width)
        if u < 0 or u > 1 or v < 0 or v > 1 then return end
        return u, v, distance
    end
    function self.Destroy()
        local objects = {} for _, object in pairs(self.Objects) do objects[#objects + 1] = object end
        for _, object in ipairs(objects) do object:Destroy() end
    end
    return self
end
return Manager
