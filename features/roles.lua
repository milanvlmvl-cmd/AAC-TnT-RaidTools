local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local Guard = require("AAC-TnT-RaidTools/core/guard")

-- What the raid sort knows about one player: class, skillsets, gear score and the role they imply.
-- Every game call is protected (see core/guard.lua): calls fail for units that are out of range.
local Roles = {}

local cfg = constants.raidSort
local safe = Guard.Silent

local roleByClass = {} -- lowercase class name -> "tank" | "healer" (explicit class lists)
for _, name in ipairs(cfg.healerClasses) do roleByClass[name:lower()] = "healer" end
for _, name in ipairs(cfg.tankClasses) do roleByClass[name:lower()] = "tank" end -- tank wins a tie

-- Name players know for a skillset id: the game's internal name run through
-- cfg.skillsetDisplayNames (unknown internal names are kept as they are).
function Roles.SkillsetName(id)
    local internal = safe("GetSkillsetNameById", function() return api.Ability:GetSkillsetNameById(id) end)
    if type(internal) ~= "string" or internal == "" then return nil end
    return cfg.skillsetDisplayNames[internal:lower()] or internal
end

-- The skillset ids in a unit info table (its `class` table, keys 1..3 or "1".."3"), or nil when
-- there are none.
function Roles.IdsFromInfo(info)
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

-- The player's skillset ids, or nil when the unit cannot be read (out of range).
function Roles.ReadSkillsetIds(unit)
    local unitId = safe("GetUnitId", function() return api.Unit:GetUnitId(unit) end)
    if unitId == nil then return nil end
    return Roles.IdsFromInfo(safe("GetUnitInfoById", function() return api.Unit:GetUnitInfoById(unitId) end))
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
        local name = Roles.SkillsetName(id)
        if name ~= nil then names[#names + 1] = name:lower() end
    end
    if hasAnySkill(names, cfg.tankSkillsets) then return "tank" end
    if hasAnySkill(names, cfg.healerSkillsets) and not hasAnySkill(names, cfg.healerExcludedSkillsets) then
        return "healer"
    end
    return nil
end

-- Role and how it was decided: the explicit class lists first, then the player's skillsets.
function Roles.Decide(className, skillIds)
    local fromClass = roleByClass[(className or ""):lower()]
    if fromClass ~= nil then return fromClass, "class" end
    if skillIds ~= nil then
        local fromSkills = roleFromSkillsets(skillIds)
        if fromSkills ~= nil then return fromSkills, "skills" end
    end
    return "other", "none"
end

-- A class name from what the game gives back: a string, or a table holding one.
function Roles.ClassName(value)
    if type(value) == "table" then value = value.name or value.className or value.class_name end
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function Roles.ReadClass(unit)
    return Roles.ClassName(safe("GetUnitClassName", function() return api.Ability:GetUnitClassName(unit) end))
end

-- Gear score as a positive number, or nil (unknown / out of range). Handles a plain number or a
-- table with a gear score field, as PlayerDB does.
local GEAR_KEYS = {"gearScore", "gear_score", "gearscore", "total", "score", "value"}
function Roles.ToGearScore(value)
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

function Roles.ReadGearScore(unit)
    return Roles.ToGearScore(safe("UnitGearScore", function() return api.Unit:UnitGearScore(unit) end))
end

return Roles
