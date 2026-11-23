local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Matching = require("AAC-TnT-RaidTools/core/matching")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Notify = require("AAC-TnT-RaidTools/core/notify")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local Marks = require("AAC-TnT-RaidTools/features/raidmarks")
local Roles = require("AAC-TnT-RaidTools/features/roles")

-- Self marking: a raid member says the keyword in raid chat and gets an overhead sign
-- (see constants.marks for the forms). Asking again for the sign you carry, or "<keyword> clear",
-- removes it (the game toggles a sign off when the same sign is applied again). Requests are queued and sent one at a time from Update,
-- because the Raid Info sign menu route cannot handle two at once, and a sign the server has not
-- applied yet would otherwise look free to the next "first free sign" request.
--
-- Deliberately not paused by the INVITES switch or by AFK: it must keep working while the lead is away.
local MarkControl = {}

local cfg = constants.marks
local safe = Guard.Silent

local clock = 0 -- ms since Reset, advanced by Update
local timer = 0 -- ms until the next queued request may be sent
local queue = {} -- {name, key, sign}, oldest first
local reserved = {} -- sign -> {key, untilMs}: handed out, maybe not visible on the server yet

local function signName(sign)
    return cfg.signNames[sign] or tostring(sign)
end

local function reservation(sign)
    local entry = reserved[sign]
    if entry and entry.untilMs > clock then return entry end
    return nil
end

local function reserve(sign, key)
    -- a player holds one sign: drop their older reservation
    for other, entry in pairs(reserved) do
        if entry.key == key then reserved[other] = nil end
    end
    reserved[sign] = {key = key, untilMs = clock + cfg.reserveMs}
end

local function hasReservation(key)
    for sign, entry in pairs(reserved) do
        if entry.key == key and reservation(sign) then return true end
    end
    return false
end

-- First sign in `order` for which taken(sign) is false, or nil when all are taken.
function MarkControl.PickFree(order, taken)
    for _, sign in ipairs(order) do
        if not taken(sign) then return sign end
    end
    return nil
end

local function isMe(key)
    return Matching.normalizeName(safe("UnitName", function() return api.Unit:UnitName("player") end)) == key
end

-- Within cfg.rangeM of you. A distance the game cannot read (unit not loaded) counts as out of range.
local function inRange(key, slot)
    if isMe(key) then return true end
    local distance = safe("UnitDistance", function() return api.Unit:UnitDistance("team" .. slot) end)
    return type(distance) == "number" and distance <= cfg.rangeM
end

-- Who may self mark. Each ticked restriction is a way in: with both ticked, being listed OR in your
-- guild is enough; with neither, everyone may. listed() / inGuild() are only called when needed.
function MarkControl.Allowed(listOnly, guildOnly, listed, inGuild)
    if not listOnly and not guildOnly then return true end
    return (listOnly and listed()) or (guildOnly and inGuild()) or false
end

-- In your guild. Nobody matches while you have no guild, or when their guild cannot be read.
local function sameGuild(key, slot)
    if isMe(key) then return true end
    local mine = Roles.ReadGuild("player")
    return mine ~= nil and Roles.ReadGuild("team" .. slot) == mine
end

local function dropReservations(key)
    for sign, entry in pairs(reserved) do
        if entry.key == key then reserved[sign] = nil end
    end
end

-- The not yet sent request of a player, and its index in the queue.
local function queuedFor(key)
    for i, job in ipairs(queue) do
        if job.key == key then return job, i end
    end
    return nil
end

-- clear = true: take `sign` off the player instead of putting it on.
local function enqueue(name, key, sign, clear)
    local _, index = queuedFor(key)
    if index then table.remove(queue, index) end -- newest request of a player wins (one per player)
    queue[#queue + 1] = {name = name, key = key, sign = sign, clear = clear}
    if clear then dropReservations(key) else reserve(sign, key) end
end

-- Take back a request that was not sent yet. Returns true when there was one.
local function cancelQueued(key)
    local job, index = queuedFor(key)
    if not job then return false end
    table.remove(queue, index)
    if not job.clear then dropReservations(key) end
    return true
end

-- Called for every chat line (from features/raidtools.lua). Ignores anything that is not a valid
-- request from an allowed raid member in range while you are raid lead.
function MarkControl.HandleChat(channelId, speakerName, message)
    if not settings.Get("MarkEnabled") then return end
    if not Matching.channelAllowed(channelId, cfg.channel) then return end
    local request = Matching.parseMarkRequest(message, settings.Get("MarkPhrase"))
    if request == nil then return end
    local key = Matching.normalizeName(speakerName)
    if key == "" then return end
    local slot = Marks.Slot(speakerName)
    if slot == nil or not inRange(key, slot) then return end
    if not MarkControl.Allowed(settings.Get("MarkWhitelistEnabled"), settings.Get("MarkGuildOnly"),
        function() return Matching.lookup(settings.Get("MarkWhitelist"))[key] == true end,
        function() return sameGuild(key, slot) end) then
        return
    end
    if not Authority.IsLead() then return end

    local pending = queuedFor(key)
    local current = Marks.Get(speakerName)
    -- "Auto heart" owns the heart: it cannot be asked for, cleared or handed out as a free sign
    local heart = settings.Get("MarkAutoHeart") and cfg.autoHeart.sign or nil
    if request == heart then return end

    if request == "clear" then
        -- a sign still waiting in the queue is simply taken back; otherwise remove the one they carry
        if pending and not pending.clear then
            cancelQueued(key)
        elseif current ~= nil and current ~= heart then
            enqueue(speakerName, key, current, true)
        end
        return
    end

    if request == "free" then
        if current ~= nil or hasReservation(key) then return end -- already marked
        local sign = MarkControl.PickFree(cfg.freeOrder, function(s)
            return s == heart or reservation(s) ~= nil or not Marks.IsFree(s)
        end)
        if sign == nil then return end -- all 12 signs in use
        enqueue(speakerName, key, sign)
        return
    end

    -- a numbered / named sign: asking again for the one they carry (or are about to get) removes it.
    -- Asking twice while the first one still waits in the queue cancels both (no change).
    if pending and pending.sign == request then
        cancelQueued(key)
    elseif current == request then
        enqueue(speakerName, key, request, true)
    else
        enqueue(speakerName, key, request)
    end
end

-- Called every frame with the milliseconds since the last one (registered with the Ticker in main.lua).
function MarkControl.Update(dt)
    if type(dt) ~= "number" then return end
    clock = clock + dt
    timer = timer - dt
    if #queue == 0 or timer > 0 then return end
    if not settings.Get("MarkEnabled") then
        queue = {}
        return
    end
    local job = table.remove(queue, 1)
    timer = cfg.queueDelayMs
    local label = "sign " .. signName(job.sign)
    if job.clear then
        -- Marks.Clear re-checks the holder, so a sign that is already gone is not toggled back on
        local ok, done, why = pcall(Marks.Clear, job.name, job.sign)
        if ok and done then
            Notify.Chat(label .. " cleared from " .. job.name)
        else
            Notify.Chat("clearing " .. label .. " from " .. job.name .. " failed: " .. tostring(ok and why or done))
        end
        return
    end
    local ok, done, why = pcall(Marks.Set, job.name, job.sign)
    if ok and done then
        Notify.Chat(label .. " -> " .. job.name)
    else
        reserved[job.sign] = nil
        Notify.Chat(label .. " for " .. job.name .. " failed: " .. tostring(ok and why or done))
    end
end

-- Queue `sign` for `name` from code (Auto heart), through the same one-at-a-time queue as chat requests.
function MarkControl.Assign(name, sign)
    local key = Matching.normalizeName(name)
    if key == "" then return end
    enqueue(name, key, sign)
end

-- true while `sign` was handed out a moment ago (queued, or sent but maybe not on the server yet).
function MarkControl.Pending(sign)
    return reservation(sign) ~= nil
end

-- Enabled checkbox: drop anything still waiting when switched off.
function MarkControl.SetEnabled(enabled)
    settings.Update("MarkEnabled", enabled)
    if not enabled then queue, reserved = {}, {} end
end

function MarkControl.Reset()
    clock, timer, queue, reserved = 0, 0, {}, {}
end

return MarkControl
