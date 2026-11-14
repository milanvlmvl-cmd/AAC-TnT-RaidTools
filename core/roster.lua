local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local Guard = require("AAC-TnT-RaidTools/core/guard")

-- Walks the raid slots. Your own slot is read as "player", every other as "team<slot>".
local Roster = {}

-- visit(slot, unit, name) is called for every occupied slot (1 .. raidSort.maxMembers).
-- safe is an optional protected-call function (see core/guard.lua).
function Roster.Each(visit, safe)
    safe = safe or Guard.Silent
    local playerSlot = safe("GetTeamPlayerIndex", function() return api.Team:GetTeamPlayerIndex() end)
    for slot = 1, constants.raidSort.maxMembers do
        local unit = (slot == playerSlot) and "player" or ("team" .. slot)
        local name = safe("UnitName", function() return api.Unit:UnitName(unit) end)
        if type(name) == "string" and name ~= "" then visit(slot, unit, name) end
    end
end

-- Sorted names joined by commas: the same text for the same set of people.
function Roster.Join(names)
    local sorted = {}
    for i, name in ipairs(names) do sorted[i] = name end
    table.sort(sorted)
    return table.concat(sorted, ",")
end

-- Names currently in the raid in Join form, read cheaply (no class / gear lookups).
function Roster.Signature(safe)
    local names = {}
    Roster.Each(function(_, _, name) names[#names + 1] = name end, safe)
    return Roster.Join(names)
end

-- Number of people in the raid, counting yourself (0 when not in a team).
function Roster.Count()
    local count = 0
    Roster.Each(function() count = count + 1 end)
    return count
end

return Roster
