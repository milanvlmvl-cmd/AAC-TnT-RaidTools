local api = require("api")
local Notify = require("AAC-TnT-RaidTools/core/notify")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Roster = require("AAC-TnT-RaidTools/core/roster")

-- Whether this player may run the auto invites and the raid sort. Both need raid lead, so they
-- are paused (settings untouched) while you are in a raid of more than one person without it.
-- Alone you are always allowed: inviting someone is what makes you the leader.
-- Lead is read from UnitTeamAuthority("player"): "leader" for the raid leader, nil for a member.
local Authority = {}

local lastAllowed = nil
local listeners = {}

-- Call fn(allowed) whenever the state flips (and on the first check). Cleared by Authority.Reset.
function Authority.Subscribe(fn)
    listeners[#listeners + 1] = fn
end

function Authority.Reset()
    listeners = {}
    lastAllowed = nil
end

-- false only when a check has found that you may not manage the raid (not lead, raid of 2+).
function Authority.IsPaused()
    return lastAllowed == false
end

function Authority.IsLead()
    return Guard.Silent("UnitTeamAuthority", function() return api.Unit:UnitTeamAuthority("player") end) == "leader"
end

-- true when invites and sorting may act. Writes one chat line each time that flips.
function Authority.CanManage()
    local count = Roster.Count()
    local lead = Authority.IsLead()
    local allowed = count <= 1 or lead
    if allowed ~= lastAllowed then
        local first = lastAllowed == nil
        lastAllowed = allowed
        for _, fn in ipairs(listeners) do pcall(fn, allowed) end
        if first and allowed then return allowed end -- nothing to report on the first, normal, check
        Notify.Chat(allowed
            and ("raid tools active (" .. (lead and "you are lead" or "not in a raid") .. ")")
            or ("raid tools paused: you are not raid lead (raid of " .. count .. "). Auto invites and raid sort are off until you have lead."))
    end
    return allowed
end

return Authority
