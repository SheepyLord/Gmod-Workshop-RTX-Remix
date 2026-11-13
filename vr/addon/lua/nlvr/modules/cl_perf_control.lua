-- V6's Auto controller: windowed measurement in, one rung of movement out. No engine calls here,
-- so the whole decision is testable offline.
local Control = {}
local defaults = {
    window = 1.0,        -- seconds of frames behind each decision
    missRatio = 0.95,    -- below this share of the target rate the window is a miss
    keepRatio = 0.97,    -- at or above this share it is settled (SteamVR's half-rate lock reads 44.1-45.1 of 45)
    headroom = 0.80,     -- and the GPU must fit in this share of the frame budget to climb
    gpuBound = 0.70,     -- a missed window counts only while the GPU fills this share of the budget
    downWindows = 2,     -- consecutive misses before stepping down
    upWindows = 8,       -- consecutive settled windows before stepping up
    cooldown = 3.0,      -- seconds after a step: a DLSS or scale change recreates render targets
}
function Control.New(options)
    local self = {steps = 1, lowest = 1}
    for key, value in pairs(defaults) do self[key] = value end
    for key, value in pairs(options or {}) do if defaults[key] ~= nil or key == "steps" then self[key] = value end end
    self.index, self.misses, self.settled = 1, 0, 0
    self.windowStart, self.windowFrames, self.windowGpuMs, self.windowGpuSamples = nil, 0, 0, 0
    self.lastStep, self.reason, self.cpuLimited = nil, nil, false
    -- Begin at a step; the caller takes it from the GPU's tier.
    function self.Begin(index, now)
        self.index = math.max(1, math.min(math.floor(index or 1), self.steps))
        self.misses, self.settled, self.lastStep = 0, 0, now
        self.windowStart, self.windowFrames, self.windowGpuMs, self.windowGpuSamples = now, 0, 0, 0
        self.reason, self.cpuLimited = nil, false
        return self.index
    end
    -- One observation. `frames` is the eye pairs submitted since the last call, `targetRate` the
    -- rate we aim for (half the headset's refresh), `gpuMs` the runtime's last frame time or nil.
    -- Returns the step to use and, when it changed, why.
    function self.Sample(now, frames, targetRate, gpuMs, budgetMs)
        if not self.windowStart then self.windowStart = now end
        self.windowFrames = self.windowFrames + math.max(0, frames or 0)
        if gpuMs and gpuMs > 0 then
            self.windowGpuMs, self.windowGpuSamples = self.windowGpuMs + gpuMs, self.windowGpuSamples + 1
        end
        local elapsed = now - self.windowStart
        if elapsed < self.window then return self.index, nil end
        local rate = self.windowFrames / elapsed
        local gpu = self.windowGpuSamples > 0 and self.windowGpuMs / self.windowGpuSamples or nil
        self.rate, self.gpuMs = rate, gpu
        self.windowStart, self.windowFrames, self.windowGpuMs, self.windowGpuSamples = now, 0, 0, 0
        if not targetRate or targetRate <= 0 then return self.index, nil end
        local missed = rate < targetRate * self.missRatio
        -- Frames lost while the GPU has room are the game's, not the GPU's: a cheaper step would
        -- not bring them back, so they never count toward stepping down. An unknown GPU time counts.
        local gpuLimited = not gpu or not budgetMs or budgetMs <= 0 or gpu >= budgetMs * self.gpuBound
        self.cpuLimited = missed and not gpuLimited
        local settled = rate >= targetRate * self.keepRatio and
            (not gpu or not budgetMs or budgetMs <= 0 or gpu <= budgetMs * self.headroom)
        self.misses = (missed and gpuLimited) and self.misses + 1 or 0
        self.settled = settled and self.settled + 1 or 0
        if self.lastStep and now - self.lastStep < self.cooldown then return self.index, nil end
        if self.misses >= self.downWindows and self.index < self.steps then
            self.index, self.misses, self.settled, self.lastStep = self.index + 1, 0, 0, now
            self.reason = "down"
            return self.index, self.reason
        end
        if self.settled >= self.upWindows and self.index > self.lowest then
            self.index, self.misses, self.settled, self.lastStep = self.index - 1, 0, 0, now
            self.reason = "up"
            return self.index, self.reason
        end
        return self.index, nil
    end
    return self
end
return Control
