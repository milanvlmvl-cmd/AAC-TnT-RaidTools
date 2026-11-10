local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local trace = require("AAC-TnT-RaidTools/core/trace")

-- Whether this player may run the auto invites and the raid sort. Both need raid lead, so they
-- are paused (settings untouched) while you are in a raid of more than one person without it.
-- Alone you are always allowed: inviting someone is what makes you the leader.
-- Lead is read from UnitTeamAuthority("player"): "leader" for the raid leader, nil for a member.
local Authority = {}

local MAX_SLOTS = 50
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

local function call(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

-- Number of people in the raid, counting yourself (0 when not in a team).
function Authority.MemberCount()
    local playerSlot = call(function() return api.Team:GetTeamPlayerIndex() end)
    local count = 0
    for slot = 1, MAX_SLOTS do
        local unit = (slot == playerSlot) and "player" or ("team" .. slot)
        local name = call(function() return api.Unit:UnitName(unit) end)
        if type(name) == "string" and name ~= "" then count = count + 1 end
    end
    return count
end

function Authority.IsLead()
    return call(function() return api.Unit:UnitTeamAuthority("player") end) == "leader"
end

-- true when invites and sorting may act. Logs, and writes one chat line, each time that flips.
function Authority.CanManage()
    local count = Authority.MemberCount()
    local lead = Authority.IsLead()
    local allowed = count <= 1 or lead
    if allowed ~= lastAllowed then
        local first = lastAllowed == nil
        lastAllowed = allowed
        for _, fn in ipairs(listeners) do pcall(fn, allowed) end
        if first and allowed then return allowed end -- nothing to report on the first, normal, check
        local text = allowed
            and ("raid tools active (" .. (lead and "you are lead" or "not in a raid") .. ")")
            or ("raid tools paused: you are not raid lead (raid of " .. count .. "). Auto invites and raid sort are off until you have lead.")
        trace.Add("[authority] " .. text)
        pcall(function() api.Log:Info("[" .. constants.displayName .. "] " .. text) end)
    end
    return allowed
end

return Authority
