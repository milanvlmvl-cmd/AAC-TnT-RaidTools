local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local trace = require("AAC-TnT-RaidTools/core/trace")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Roles = require("AAC-TnT-RaidTools/features/roles")
local PlayerStore = require("AAC-TnT-RaidTools/features/playerstore")

-- Test-only helpers for the raid sort, switched on by constants.raidSort.dump / .probe (both off).
-- While one is on the raid sort does not sort. Their output goes to the debug trace (/debug).
local Debug = {}

local cfg = constants.raidSort
local log = trace.Logger("raidsort-debug")
local safe = Guard.New(log)

-- ---------------------------------------------------------------------------------------------
-- Dump: one file per raid member describing their class and skillsets
-- ---------------------------------------------------------------------------------------------
local dumped = {} -- player name -> true, once their file is written for this enable

function Debug.ResetDump()
    dumped = {}
end

-- Plain copy of a game table that file serialisation can handle: functions dropped, userdata and
-- other types turned into text, depth limited.
local function copyPlain(value, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind == "table" then
        if (depth or 0) >= 5 then return "<table too deep>" end
        local copy = {}
        for key, item in pairs(value) do
            if type(item) ~= "function" then
                local plainKey = (type(key) == "string" or type(key) == "number") and key or tostring(key)
                copy[plainKey] = copyPlain(item, (depth or 0) + 1)
            end
        end
        return copy
    end
    if value == nil then return nil end
    return tostring(value)
end

local function dumpMember(member)
    local unit = member.unit
    local unitId = safe("GetUnitId", function() return api.Unit:GetUnitId(unit) end)
    local infoById = unitId ~= nil and safe("GetUnitInfoById", function() return api.Unit:GetUnitInfoById(unitId) end) or nil
    local info = safe("UnitInfo", function() return api.Unit:UnitInfo(unit) end)
    local record = {
        name = member.name,
        slot = member.slot,
        unit = unit,
        className = safe("GetUnitClassName", function() return api.Ability:GetUnitClassName(unit) end),
        unitClass = safe("UnitClass", function() return api.Unit:UnitClass(unit) end),
        gearScore = copyPlain(safe("UnitGearScore", function() return api.Unit:UnitGearScore(unit) end)),
        raidSortRole = member.role,
        raidSortRoleSource = member.roleSource,
    }
    local ids = Roles.IdsFromInfo(infoById) or Roles.IdsFromInfo(info) or {}
    local names, display = {}, {}
    for i, id in ipairs(ids) do
        names[i] = safe("GetSkillsetNameById", function() return api.Ability:GetSkillsetNameById(id) end)
        display[i] = Roles.SkillsetName(id)
    end
    record.skillsetIds = ids
    record.skillsetNames = names -- the game's internal names
    record.skillsetDisplayNames = display -- after the lookup in constants.raidSort.skillsetDisplayNames
    if #ids == 3 then
        record.classFromSkillsetIds = safe("GetClassNameFromSkillsetIds", function()
            return api.Ability:GetClassNameFromSkillsetIds(ids[1], ids[2], ids[3])
        end)
    end
    record.unitInfoById = copyPlain(infoById)
    record.unitInfo = copyPlain(info)

    local path = PlayerStore.Path(member.name)
    local ok = safe("File:Write", function() api.File:Write(path, record) return true end)
    log("dump " .. member.name .. ": class " .. tostring(record.className) .. ", skillset ids "
        .. table.concat(ids, ",") .. " (" .. table.concat(names, ",") .. ") -> " .. path .. (ok and "" or " WRITE FAILED"))
    dumped[member.name] = true
end

-- Write a file for every member that does not have one yet this enable (out-of-range members are
-- picked up on a later pass once they can be read).
function Debug.DumpRoster(members)
    local written = 0
    for _, member in ipairs(members) do
        if not dumped[member.name] then
            dumpMember(member)
            written = written + 1
        end
    end
    if written > 0 then log("dump: wrote " .. written .. " player files to " .. cfg.playersFolder) end
end

-- ---------------------------------------------------------------------------------------------
-- Probe: move one character to each configured slot, one at a time, and log what the game did
-- ---------------------------------------------------------------------------------------------
local probeIndex, probeDone, probePending, probeMissingLogged = 1, false, nil, false

function Debug.ResetProbe()
    probeIndex, probeDone, probePending, probeMissingLogged = 1, false, nil, false
end

-- "g2[6]=Ann [7]=- ..." for the group(s) containing the given slots, for the probe's log lines.
local function dumpGroups(current, slots)
    local seen, parts = {}, {}
    for _, slot in ipairs(slots) do
        local group = math.ceil(slot / cfg.groupSize)
        if not seen[group] then
            seen[group] = true
            local cells = {}
            for s = (group - 1) * cfg.groupSize + 1, group * cfg.groupSize do
                cells[#cells + 1] = "[" .. s .. "]=" .. (current[s] or "-")
            end
            parts[#parts + 1] = "g" .. group .. " " .. table.concat(cells, " ")
        end
    end
    return table.concat(parts, " | ")
end

-- current: slot -> name; clock: ms since load. Returns "moved" / "waiting" / false like the raid
-- sort's pass.
function Debug.RunProbe(current, clock)
    local probe = cfg.probe
    if probeDone then return false end
    local slotOf
    for slot, name in pairs(current) do if name == probe.name then slotOf = slot end end
    if slotOf == nil then
        if not probeMissingLogged then
            probeMissingLogged = true
            log("probe: " .. probe.name .. " is not in the raid")
        end
        return false
    end

    if probePending ~= nil then
        local waited = clock - probePending.at
        if slotOf == probePending.from and waited < cfg.moveTimeoutMs then return "waiting" end
        local outcome
        if slotOf == probePending.from then outcome = "did not move (waited " .. waited .. "ms)"
        elseif slotOf == probePending.asked then outcome = "landed in the slot asked for"
        else outcome = "landed in slot " .. slotOf .. " (asked for " .. probePending.asked .. ")" end
        log("probe " .. probe.name .. " " .. probePending.from .. " -> asked " .. probePending.asked
            .. ": " .. outcome .. ". Occupant of asked slot before: " .. (probePending.occupant or "none")
            .. ". After: " .. dumpGroups(current, {probePending.from, probePending.asked, slotOf}))
        probePending = nil
        probeIndex = probeIndex + 1
    end

    local asked = probe.slots[probeIndex]
    while asked ~= nil and asked == slotOf do
        log("probe: " .. probe.name .. " is already in slot " .. asked)
        probeIndex = probeIndex + 1
        asked = probe.slots[probeIndex]
    end
    if asked == nil then
        probeDone = true
        log("probe finished; sorting stays off while constants.raidSort.probe.enabled is true")
        return false
    end
    log("probe: moving " .. probe.name .. " from slot " .. slotOf .. " to slot " .. asked
        .. ". Before: " .. dumpGroups(current, {slotOf, asked}))
    probePending = {from = slotOf, asked = asked, occupant = current[asked], at = clock}
    safe("MoveTeamMember", function() api.Team:MoveTeamMember(slotOf, asked) end)
    return "moved"
end

return Debug
