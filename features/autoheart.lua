local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Matching = require("AAC-TnT-RaidTools/core/matching")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Roster = require("AAC-TnT-RaidTools/core/roster")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local Roles = require("AAC-TnT-RaidTools/features/roles")
local Marks = require("AAC-TnT-RaidTools/features/raidmarks")
local MarkControl = require("AAC-TnT-RaidTools/features/markcontrol")

-- "Auto heart" (part of mark control): every few seconds look at the healers who have Songcraft
-- within range, read their healing power, and keep the heart on the one with the most. The heart only
-- moves when someone beats the current holder by more than switchMargin, so small swings (buffs)
-- do not bounce it around. Like the rest of mark control it is not paused by AFK.
local AutoHeart = {}

local cfg = constants.marks.autoHeart
local rangeM = constants.marks.rangeM
local safe = Guard.Silent

local elapsed = 0
local status = "" -- one line for the mark control window
local listener = nil

local function setStatus(text)
    if text == status then return end
    status = text
    if listener then pcall(listener, status) end
end

-- Who should get the heart. candidates: {name, key, heal}; holderKey: key of the candidate carrying
-- the heart now (nil when none of them does). Returns the candidate to give it to, or nil to leave
-- it where it is.
function AutoHeart.Pick(candidates, holderKey, margin)
    local best, holder = nil, nil
    for _, c in ipairs(candidates) do
        if best == nil or c.heal > best.heal then best = c end
        if c.key == holderKey then holder = c end
    end
    if best == nil or best == holder then return nil end
    if holder and best.heal <= holder.heal * (1 + margin) then return nil end
    return best
end

local function inRange(unit)
    if unit == "player" then return true end
    local distance = safe("UnitDistance", function() return api.Unit:UnitDistance(unit) end)
    return type(distance) == "number" and distance <= rangeM
end

-- Healers with the skillset within range whose healing power can be read.
local function readCandidates()
    local list = {}
    Roster.Each(function(_, unit, name)
        if not inRange(unit) then return end
        local ids = Roles.ReadSkillsetIds(unit)
        if ids == nil or not Roles.HasSkillset(ids, cfg.skillset) then return end
        if Roles.Decide(Roles.ReadClass(unit), ids) ~= "healer" then return end
        local heal = Roles.ReadStat(unit, cfg.statKey)
        if heal == nil then return end
        list[#list + 1] = {name = name, key = Matching.normalizeName(name), heal = heal}
    end, safe)
    return list
end

local function scan()
    if not settings.Get("MarkEnabled") or not settings.Get("MarkAutoHeart") then
        setStatus("")
        return
    end
    if not Authority.IsLead() then
        setStatus("Auto heart: waiting for raid lead")
        return
    end
    if MarkControl.Pending(cfg.sign) then return end -- a heart move is still on its way

    local candidates = readCandidates()
    local holder = nil
    for _, c in ipairs(candidates) do
        if Marks.Get(c.name) == cfg.sign then holder = c end
    end
    local pick = AutoHeart.Pick(candidates, holder and holder.key, cfg.switchMargin)
    if pick then MarkControl.Assign(pick.name, cfg.sign) end

    local shown = pick or holder
    if shown then
        setStatus("Heart: " .. shown.name .. "  (healing " .. math.floor(shown.heal) .. ", "
            .. #candidates .. " in range)")
    elseif #candidates == 0 then
        setStatus("Auto heart: no " .. cfg.skillset .. " healer in range")
    end
end

-- Called every frame with the milliseconds since the last one (registered with the Ticker in main.lua).
function AutoHeart.Update(dt)
    if type(dt) ~= "number" then return end
    elapsed = elapsed + dt
    if elapsed < cfg.scanMs then return end
    elapsed = 0
    scan()
end

-- Check box changed: look again on the next frame.
function AutoHeart.SetEnabled(enabled)
    settings.Update("MarkAutoHeart", enabled)
    elapsed = cfg.scanMs
    if not enabled then setStatus("") end
end

function AutoHeart.Status()
    return status
end

-- fn(statusText) runs whenever the status line changes; nil removes it. Only one listener is kept.
function AutoHeart.SetListener(fn)
    listener = fn
end

function AutoHeart.Reset()
    elapsed, status = 0, ""
end

return AutoHeart
