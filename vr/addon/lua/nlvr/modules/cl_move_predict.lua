-- Render prediction only. The server remains the player-hull authority.
local M = include("nlvr/modules/cl_move_math.lua")
local P = {}
function P.New()
    local self = {consumed = Vector(), applied = Vector(), revision = 0, blocked = false}
    local cache, samples, clock, cursor, epoch = nil, {}, nil, nil, nil
    local cadence = {}
    local delay, delayAt = nil, nil -- the motor delay in use; it eases toward bufferSeconds
    local neededAt = nil -- when the cadence last needed the current buffer
    local began=SysTime()
    self.bufferSeconds = engine.TickInterval()
    function self.Receive(consumed, applied, origin, mode, blocked, stamp, wall, generation)
        if not M.Vector(consumed) or not M.Vector(applied) or not M.Vector(origin) then return false end
        stamp, wall = stamp or CurTime(), wall or SysTime()
        generation = generation or epoch or 0
        if not M.Finite(stamp) or not M.Finite(wall) then return false end
        local discontinuity = self.stale or epoch ~= nil and generation ~= nil and epoch ~= generation or self.mode and self.mode ~= mode
        -- A discontinuity restarts the trajectory, not the wire: the learned cadence and buffer stay,
        -- so movement after a blink, respawn or pause is not starved while 16 gaps are relearned.
        if discontinuity then samples, clock, cursor, delay = {}, nil, nil, nil end
        if not clock or math.abs(stamp - (clock.sim + wall - clock.wall)) > 0.25 then
            clock = {sim = stamp, wall = wall}
        end
        epoch = generation or epoch
        if not samples[#samples] or stamp > samples[#samples].time then
            local previous=samples[#samples]
            local tick=engine.TickInterval()
            local gap=previous and stamp-previous.time or 0
            if gap>=tick*.5 and gap<=tick*8 then
                cadence[#cadence+1]={gap=gap,age=math.Clamp(SysTime()-wall,0,.12)}
                if #cadence>16 then table.remove(cadence,1) end
                local interval,age=tick,0
                for _,sample in ipairs(cadence) do interval=math.max(interval,sample.gap) age=math.max(age,sample.age) end
                -- The shared wire coalesces movement with physical-hand updates. Buffer
                -- their measured cadence plus delivery age, not just one simulation tick.
                local delivery=math.max(tick,math.ceil(age/tick-.0001)*tick)
                local wanted=interval>tick*1.5 and math.min(.12,interval+delivery) or tick
                -- Grow at once; shrink only after the larger buffer went unneeded for ten seconds,
                -- so a wire that alternates between gaps keeps one buffer instead of easing all the time.
                local now=SysTime()
                if wanted>=self.bufferSeconds-1e-9 or not neededAt then self.bufferSeconds,neededAt=wanted,now
                elseif now-neededAt>=10 then self.bufferSeconds,neededAt=wanted,now end
            end
            samples[#samples + 1] = {time = stamp, pos = origin - applied}
            while #samples > 2 and stamp - samples[1].time > 1 do table.remove(samples, 1) end
        end
        self.consumed, self.applied, self.origin, self.mode, self.serverBlocked = consumed, applied, origin, mode, blocked
        self.received, self.stale = SysTime(), false
        self.revision = self.revision + 1 cache = nil
        return true
    end
    local function nonroom()
        local latest = samples[#samples]
        if not latest then return self.origin - self.applied end
        -- Server simulation ticks are uniformly spaced even when two execute in one
        -- engine frame. Advance that clock by render wall time, never by packet arrival.
        -- A one-tick change of the buffer is eased in by running the motor clock at most 2.5 % slower
        -- or faster. Applied at once it moved the target a whole tick: the monotonic cursor then held
        -- the camera for a frame (longer buffer) or skipped one (shorter). Larger changes (the first
        -- cadence learned in a session) still apply at once.
        local now = SysTime()
        if not delay or math.abs(self.bufferSeconds - delay) > 1.5 * engine.TickInterval() then
            delay = self.bufferSeconds
        else
            local limit = math.Clamp(now - (delayAt or now), 0, .05) * .025
            delay = delay + math.Clamp(self.bufferSeconds - delay, -limit, limit)
        end
        delayAt, self.delaySeconds = now, delay
        local target = clock.sim + now - clock.wall - delay
        cursor = math.max(cursor or samples[1].time, math.min(target, latest.time))
        if cursor <= samples[1].time then return samples[1].pos end
        for i = 2, #samples do
            local a, b = samples[i - 1], samples[i]
            if cursor <= b.time then return a.pos + (b.pos - a.pos) * ((cursor - a.time) / (b.time - a.time)) end
        end
        return latest.pos -- no extrapolation, so a stop cannot overshoot then snap back
    end
    function self.Feet(ply, base, total, enabled)
        if not enabled then self.blocked = false return base end
        if self.received and SysTime()-self.received>.3 or not self.received and SysTime()-began>.3 then
            self.blocked, self.stale = false, true
            return base
        end
        self.origin = self.origin or Vector(base.x, base.y, base.z)
        if not cache or cache.frame ~= FrameNumber() or cache.revision ~= self.revision or
            cache.x ~= total.x or cache.y ~= total.y or cache.z ~= base.z then
            -- FinishMove origin already contains stick/climb/teleport movement. Add only
            -- room intent that the server has not processed; discarded wall input is gone.
            local pending = total - self.consumed
            local from = self.origin
            local predicted, blocked
            if self.mode == MOVETYPE_NOCLIP or ply:GetMoveType() == MOVETYPE_NOCLIP then
                predicted, blocked = from + pending, false -- engine already granted flight
            else predicted, blocked = M.Follow(ply, from, pending) end
            cache = {frame = FrameNumber(), revision = self.revision, x = total.x, y = total.y, z = base.z,
                correction = self.applied + predicted - from, blocked = blocked}
        end
        self.blocked = cache.blocked
        -- Collision/pending-room work is frame-cached; motor time is sampled at the
        -- actual view call, not an earlier CreateMove/resolver in the same frame.
        return nonroom() + cache.correction
    end
    return self
end
return P
