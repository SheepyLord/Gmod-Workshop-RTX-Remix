-- R23 (the user's item 3): while an imported character's game PBR maps convert, a notice at the top right
-- says so with a progress bar, then that they are ready. The count comes from the RTX fixes' ToPBR driver
-- (RTXGamePBRProgress: materials still converting, and how many the batch had). Shown only once a batch
-- has taken SHOW_AFTER seconds, so restoring saved maps shows nothing; a notice the player closes stays
-- closed until the next batch. Documented in nativeloader_pbr_progress.lua.md beside this file.
local POLL, SHOW_AFTER, READY_SECONDS = 0.25, 1.5, 4
local notice, began, closed
local L = function(text) return text end

local function progressText(done, total)
    return string.format(L("Preparing PBR materials for imported characters: %d of %d."), done, total)
end

local function poll()
    if type(RTXGamePBRProgress) ~= "function" then return end
    local ok, pending, total = pcall(RTXGamePBRProgress)
    if not ok or type(pending) ~= "number" or type(total) ~= "number" then return end
    if pending > 0 and total > 0 then
        local done = math.max(0, total - pending)
        began = began or RealTime()
        if IsValid(notice) then
            notice:SetNoticeText(progressText(done, total))
            notice:SetNoticeProgress(done / total)
        elseif notice ~= nil then
            closed, notice = true, nil -- the player closed it: not again for this batch
        elseif not closed and RealTime() - began >= SHOW_AFTER then
            local i18n = include("nativeloader/i18n.lua")
            if i18n and i18n.L then L = i18n.L end
            local Notice = include("nativeloader/notice.lua")
            notice = Notice and Notice.Show(progressText(done, total), { seconds = 0, progress = done / total }) or nil
        end
        return
    end
    if IsValid(notice) then
        notice:SetNoticeText(L("PBR materials for imported characters are ready."))
        notice:SetNoticeProgress(1)
        notice:FinishNotice(READY_SECONDS)
    end
    notice, began, closed = nil, nil, nil
end

timer.Create("nativeloader_pbr_progress", POLL, 0, function()
    local ok, problem = pcall(poll)
    if not ok then
        timer.Remove("nativeloader_pbr_progress")
        MsgN("[nativeloader] PBR progress notice stopped: " .. tostring(problem))
    end
end)
