local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local trace = require("AAC-TnT-RaidTools/core/trace")
local SortPlan = require("AAC-TnT-RaidTools/core/sortplan")

-- When enabled, keeps the raid ordered: tanks in groups 1 and 6, healers in 5 and 10, everyone
-- else in 2, 3, 4, 7, 8, 9, each group sorted by gear score (highest first). It re-reads the raid
-- every few seconds (a gear score or class is only readable while a member is in range) and soon
-- after someone joins or leaves, then moves one member at a time. Moving onto an occupied slot swaps the two, so each move is
-- confirmed in the roster before the next is planned.
local RaidSort = {}

local cfg = constants.raidSort

local live = false
local timer = 0 -- ms until the next run
local clock = 0 -- ms since load, advanced by UPDATE
local movesThisRun = 0
-- A move is a swap when the target slot is occupied, and the game applies it a moment later.
-- Until the roster shows the member in their new slot the move is "pending": no further move is
-- sent, because planning from the stale layout would repeat it and could undo the swap.
local pending = nil -- {name, from, to, at}
local halted = false -- a move never took effect: stop until the roster changes
local rosterSignature = nil

-- last readable value per player name, used while they are out of range
local gearCache, classCache, skillCache = {}, {}, {}

local roleByClass = {} -- lowercase class name -> "tank" | "healer" (explicit class lists)

local function log(text)
    trace.Add("[raidsort] " .. text)
end

-- API calls can be missing in this game build (IsPartyRaid is) or fail for out-of-range units.
-- Run them protected, log each distinct failure once, and return nil instead of raising.
local loggedFailures = {}
local function safe(label, fn)
    local ok, value = pcall(fn)
    if ok then return value end
    local message = label .. " failed: " .. tostring(value)
    if not loggedFailures[message] then
        loggedFailures[message] = true
        log(message)
    end
    return nil
end

local function buildRoleLookup()
    roleByClass = {}
    for _, name in ipairs(cfg.healerClasses) do roleByClass[name:lower()] = "healer" end
    for _, name in ipairs(cfg.tankClasses) do roleByClass[name:lower()] = "tank" end -- tank wins a tie
end

-- Name players know for a skillset id: the game's internal name run through
-- cfg.skillsetDisplayNames (unknown internal names are kept as they are).
local function skillsetName(id)
    local internal = safe("GetSkillsetNameById", function() return api.Ability:GetSkillsetNameById(id) end)
    if type(internal) ~= "string" or internal == "" then return nil end
    return cfg.skillsetDisplayNames[internal:lower()] or internal
end

-- The player's three skillset ids (the unit info's `class` table, keys "1".."3"), or nil when the
-- unit cannot be read (out of range).
local function readSkillsetIds(unit)
    local unitId = safe("GetUnitId", function() return api.Unit:GetUnitId(unit) end)
    if unitId == nil then return nil end
    local info = safe("GetUnitInfoById", function() return api.Unit:GetUnitInfoById(unitId) end)
    local classTable = type(info) == "table" and info.class or nil
    if type(classTable) ~= "table" then return nil end
    local ids = {}
    for i = 1, 3 do
        local id = classTable[i] or classTable[tostring(i)]
        if id ~= nil then ids[#ids + 1] = id end
    end
    if #ids == 0 then return nil end
    return ids
end

local function hasAnySkill(names, words)
    for _, name in ipairs(names) do
        for _, word in ipairs(words) do
            if name:find(word:lower(), 1, true) ~= nil then return true end
        end
    end
    return false
end

-- "tank" / "healer" / nil from a player's skillset ids: a tank skillset makes a tank; else a healer
-- skillset makes a healer unless the player also has an excluded (damage) skillset.
local function roleFromSkillsets(ids)
    local names = {}
    for _, id in ipairs(ids) do
        local name = skillsetName(id)
        if name ~= nil then names[#names + 1] = name:lower() end
    end
    if hasAnySkill(names, cfg.tankSkillsets) then return "tank" end
    if hasAnySkill(names, cfg.healerSkillsets) and not hasAnySkill(names, cfg.healerExcludedSkillsets) then
        return "healer"
    end
    return nil
end

-- Role and how it was decided: the explicit class lists first, then the player's skillsets.
local function decideRole(className, skillIds)
    local fromClass = roleByClass[(className or ""):lower()]
    if fromClass ~= nil then return fromClass, "class" end
    if skillIds ~= nil then
        local fromSkills = roleFromSkillsets(skillIds)
        if fromSkills ~= nil then return fromSkills, "skills" end
    end
    return "other", "none"
end

-- Gear score as a positive number, or nil (unknown / out of range). Handles a plain number or a
-- table with a gear score field, as PlayerDB does.
local GEAR_KEYS = {"gearScore", "gear_score", "gearscore", "total", "score", "value"}
local function toGearScore(value)
    if type(value) == "table" then
        for _, key in ipairs(GEAR_KEYS) do
            local found = tonumber(value[key])
            if found ~= nil and found > 0 then return found end
        end
        return nil
    end
    local number = tonumber(value)
    if number == nil or number <= 0 then return nil end
    return number
end

local function readClass(unit)
    local class = safe("GetUnitClassName", function() return api.Ability:GetUnitClassName(unit) end)
    if type(class) == "table" then class = class.name or class.className or class.class_name end
    if type(class) == "string" and class ~= "" then return class end
    return nil
end

-- Everyone in the raid as {name, slot, class, role, gs}. A class or gear score that cannot be read
-- (out of range, API failure) falls back to the last readable value for that player, and then to
-- class "unknown" (role "other") and gear score 0, so nobody is ever left out of the plan.
local function readRoster()
    local members = {}
    local playerSlot = safe("GetTeamPlayerIndex", function() return api.Team:GetTeamPlayerIndex() end)
    for slot = 1, cfg.maxMembers do
        local unit = (slot == playerSlot) and "player" or ("team" .. slot)
        local name = safe("UnitName", function() return api.Unit:UnitName(unit) end)
        if type(name) == "string" and name ~= "" then
            local class = readClass(unit)
            if class ~= nil then classCache[name] = class end
            local gs = toGearScore(safe("UnitGearScore", function() return api.Unit:UnitGearScore(unit) end))
            if gs ~= nil then gearCache[name] = gs end
            local knownClass = classCache[name]
            local skillIds = readSkillsetIds(unit)
            if skillIds ~= nil then skillCache[name] = skillIds end
            local role, source = decideRole(knownClass, skillCache[name])
            members[#members + 1] = {
                name = name, slot = slot, unit = unit,
                class = knownClass or "unknown",
                role = role, roleSource = source,
                gs = gearCache[name] or 0,
            }
        end
    end
    return members
end

-- Whether we are in a raid (not a party). IsPartyRaid is missing in this game build, so fall back
-- to IsPartyTeam, and if neither exists assume a raid.
local raidCheckLogged = false
local function inRaid()
    local team = api.Team
    local method, invert
    if type(team.IsPartyRaid) == "function" then method = "IsPartyRaid"
    elseif type(team.IsPartyTeam) == "function" then method, invert = "IsPartyTeam", true end
    if method == nil then
        if not raidCheckLogged then raidCheckLogged = true; log("no IsPartyRaid/IsPartyTeam in this build; assuming raid") end
        return true
    end
    local result = safe(method, function() return team[method](team) end)
    if result == nil then return true end -- could not tell: do not block the sort
    if invert then return not result end
    return result and true or false
end

local function signatureOf(members)
    local parts = {}
    for _, m in ipairs(members) do parts[#parts + 1] = m.name end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function describe(m)
    return m.name .. "(" .. m.class .. "/" .. m.role .. (m.roleSource == "skills" and "[skills]" or "")
        .. " gs=" .. m.gs .. " slot=" .. m.slot .. ")"
end

local probeIndex, probeDone, probePending, probeMissingLogged = 1, false, nil, false

local function resetRun()
    halted, movesThisRun, pending = false, 0, nil
end

-- ---------------------------------------------------------------------------------------------
-- Dump mode: one file per raid member describing their class and skillsets (see constants.dump)
-- ---------------------------------------------------------------------------------------------
local dumped = {} -- player name -> true, once their file is written for this enable

-- Plain copy of a game table that file serialisation can handle: functions dropped, userdata and
-- other types turned into text, depth limited.
local function copyPlain(value, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind == "table" then
        if (depth or 0) >= 5 then return "<table too deep>" end
        local copy = {}
        for key, item in pairs(value) do
            local itemKind = type(item)
            if itemKind ~= "function" then
                local keyKind = type(key)
                local plainKey = (keyKind == "string" or keyKind == "number") and key or tostring(key)
                copy[plainKey] = copyPlain(item, (depth or 0) + 1)
            end
        end
        return copy
    end
    if value == nil then return nil end
    return tostring(value)
end

local function fileNameFor(name)
    return (name:gsub("[^%w_%-]", "_"))
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
    -- the three skillset ids live in the unit info's `class` table, keys "1".."3"
    local classTable = (type(infoById) == "table" and infoById.class) or (type(info) == "table" and info.class) or nil
    local ids, names = {}, {}
    if type(classTable) == "table" then
        for i = 1, 3 do
            local id = classTable[i] or classTable[tostring(i)]
            ids[i] = id
            names[i] = id ~= nil and safe("GetSkillsetNameById", function() return api.Ability:GetSkillsetNameById(id) end) or nil
        end
    end
    record.skillsetIds = ids
    record.skillsetNames = names -- the game's internal names
    local display = {}
    for i = 1, 3 do display[i] = ids[i] ~= nil and skillsetName(ids[i]) or nil end
    record.skillsetDisplayNames = display -- after the lookup in constants.raidSort.skillsetDisplayNames
    if ids[1] ~= nil and ids[2] ~= nil and ids[3] ~= nil then
        record.classFromSkillsetIds = safe("GetClassNameFromSkillsetIds", function()
            return api.Ability:GetClassNameFromSkillsetIds(ids[1], ids[2], ids[3])
        end)
    end
    record.unitInfoById = copyPlain(infoById)
    record.unitInfo = copyPlain(info)

    local path = cfg.dump.folder .. "/" .. fileNameFor(member.name) .. ".dat"
    local ok = safe("File:Write", function() api.File:Write(path, record) return true end)
    log("dump " .. member.name .. ": class " .. tostring(record.className) .. ", skillset ids "
        .. tostring(ids[1]) .. "," .. tostring(ids[2]) .. "," .. tostring(ids[3]) .. " (" .. tostring(names[1])
        .. "," .. tostring(names[2]) .. "," .. tostring(names[3]) .. ") -> " .. path .. (ok and "" or " WRITE FAILED"))
    dumped[member.name] = true
end

-- Write a file for every member that does not have one yet this enable (out-of-range members are
-- picked up on a later pass once they can be read).
local function dumpRoster(members)
    local written = 0
    for _, member in ipairs(members) do
        if not dumped[member.name] then
            dumpMember(member)
            written = written + 1
        end
    end
    if written > 0 then log("dump: wrote " .. written .. " player files to " .. cfg.dump.folder) end
end

local function resetProbe()
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

-- Probe: move one character to each configured slot, one at a time, and log what the game did.
-- Returns "moved" / "waiting" / false like runOnce.
local function runProbe(current)
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

-- One pass: read the raid and make at most one move. Returns "moved" after sending a move,
-- "waiting" while the previous move has not shown up in the roster yet, false otherwise.
local function runOnce()
    if not inRaid() then return false end
    local members = readRoster()
    local signature = signatureOf(members)
    if signature ~= rosterSignature then
        rosterSignature = signature
        resetRun()
        local parts = {}
        for _, m in ipairs(members) do parts[#parts + 1] = describe(m) end
        log("roster changed: " .. table.concat(parts, " "))
    end
    if cfg.dump and cfg.dump.enabled then
        dumpRoster(members)
        return false -- no sorting while dumping
    end
    if halted then return false end

    local current = {}
    for _, m in ipairs(members) do current[m.slot] = m.name end

    if pending ~= nil then
        if current[pending.to] == pending.name then
            pending = nil -- the swap went through; plan the next move from the new layout
        elseif clock - pending.at < cfg.moveTimeoutMs then
            return "waiting"
        else
            halted = true
            log("stopping: " .. pending.name .. " did not move from slot " .. pending.from .. " to " .. pending.to
                .. " within " .. cfg.moveTimeoutMs .. "ms (are you the raid leader?)")
            pending = nil
            return false
        end
    end

    if cfg.probe and cfg.probe.enabled then return runProbe(current) end

    local desired = SortPlan.Build(members, cfg)
    local from, to = SortPlan.NextMove(current, desired, cfg.maxMembers, cfg.groupSize)
    if from == nil then
        if movesThisRun > 0 then log("raid sorted after " .. movesThisRun .. " moves") end
        movesThisRun = 0
        return false
    end
    if movesThisRun >= cfg.maxMovesPerRun then
        halted = true
        log("stopping: reached " .. cfg.maxMovesPerRun .. " moves in one run")
        return false
    end

    movesThisRun = movesThisRun + 1
    local mover, displaced = current[from], current[to]
    log("move " .. mover .. " slot " .. from .. " -> " .. to
        .. (displaced and (" (swaps with " .. displaced .. ")") or " (free slot)") .. " #" .. movesThisRun)
    -- done when the mover is in the slot we asked for (we only ask for the topmost free slot of a
    -- group or an occupied slot, so that is where the game puts them)
    pending = {name = mover, from = from, to = to, at = clock}
    safe("MoveTeamMember", function() api.Team:MoveTeamMember(from, to) end)
    return "moved"
end

local function onUpdate(dt)
    if not live then return end
    clock = clock + dt
    if not settings.Get("RaidSortEnabled") then return end
    timer = timer - dt
    if timer > 0 then return end
    local result = safe("raid sort pass", runOnce)
    if result == "moved" then timer = cfg.moveDelayMs
    elseif result == "waiting" then timer = cfg.pollMs
    else timer = cfg.recheckMs end
end

-- Someone joined or left: re-check soon, and allow a halted sort to try again.
local function onTeamChanged()
    if not live then return end
    resetRun()
    if timer > cfg.settleMs then timer = cfg.settleMs end
end

function RaidSort.OnLoad()
    live = true
    timer = cfg.settleMs
    rosterSignature = nil
    dumped = {}
    resetRun()
    resetProbe()
    buildRoleLookup()
    api.On("UPDATE", onUpdate)
    api.On("TEAM_MEMBERS_CHANGED", onTeamChanged)
    log("raid sort ready (enabled=" .. tostring(settings.Get("RaidSortEnabled")) .. ")")
end

function RaidSort.OnUnload()
    live = false
    api.On("UPDATE", function() return end)
    api.On("TEAM_MEMBERS_CHANGED", function() return end)
end

-- Called when the Enabled checkbox changes: run at the next update instead of waiting.
function RaidSort.SetEnabled(enabled)
    settings.Update("RaidSortEnabled", enabled)
    resetRun()
    resetProbe()
    dumped = {}
    timer = 0
    log("raid sort " .. (enabled and "enabled" or "disabled"))
end

return RaidSort
