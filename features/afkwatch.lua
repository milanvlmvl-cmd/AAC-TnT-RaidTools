local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local Notify = require("AAC-TnT-RaidTools/core/notify")
local settings = require("AAC-TnT-RaidTools/core/settings")

-- The game exposes no AFK flag, so AFK is guessed from movement. Every cfg.intervalMs your own world
-- position (only yours, not raid members') is compared with the previous reading: staying within
-- cfg.tolerance on x, y and z adds a point, a bigger move resets the points to 0. At
-- limit() points (the AfkMinutes setting) the player counts as AFK. With "Disable if afk" ticked,
-- AfkWatch.Blocks() then pauses the invites and the raid sort.
local AfkWatch = {}

local cfg = constants.afk

-- Points needed to count as AFK: the chosen minutes divided by the check interval.
local function limit()
    return math.floor(settings.Get("AfkMinutes") * 60000 / cfg.intervalMs)
end

local state = nil -- your last reading: {x, y, z, points, afk}
local elapsed = 0 -- ms since the last check
local listener = nil -- called after every check (the config panel's "afk ticks" label)

-- One reading for one player. `state` is nil for the first reading. Returns the new state and an
-- event: "afk" when the points just reached the limit, "back" when an AFK player moved, else nil.
function AfkWatch.Step(state, x, y, z)
    if state == nil then
        return {x = x, y = y, z = z, points = 0, afk = false}, nil
    end
    local still = math.abs(x - state.x) <= cfg.tolerance
        and math.abs(y - state.y) <= cfg.tolerance
        and math.abs(z - state.z) <= cfg.tolerance
    local event = nil
    local points, afk = state.points, state.afk
    if still then
        local max = limit()
        points = math.min(points + 1, max) -- stays at the limit while AFK
        if points >= max and not afk then
            afk, event = true, "afk"
        end
    else
        if afk then event = "back" end
        points, afk = 0, false
    end
    return {x = x, y = y, z = z, points = points, afk = afk}, event
end

local function readPosition(unit)
    local ok, x, y, z = pcall(function() return api.Unit:UnitWorldPosition(unit) end)
    if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
    return nil
end

local function check()
    local x, y, z = readPosition("player")
    if x == nil then
        state = nil -- position unreadable (loading screen?): start over instead of carrying old points
        return
    end
    local event
    state, event = AfkWatch.Step(state, x, y, z)
    if event == "afk" then
        Notify.Chat("You are AFK (" .. state.points .. " points, no movement for about "
            .. math.floor(state.points * cfg.intervalMs / 1000) .. "s)")
    elseif event == "back" then
        Notify.Chat("You moved again, no longer AFK")
    end
end

-- Called with the milliseconds since the last frame (registered with the Ticker in main.lua).
function AfkWatch.Update(dt)
    if type(dt) ~= "number" then return end
    elapsed = elapsed + dt
    if elapsed < cfg.intervalMs then return end
    elapsed = 0
    check()
    if listener then pcall(listener) end
end

function AfkWatch.IsAfk()
    return state ~= nil and state.afk
end

-- true while invites and raid sort must stand still: you are AFK and "Disable if afk" is ticked.
function AfkWatch.Blocks()
    return settings.Get("DisableInvitesWhenAfk") == true and AfkWatch.IsAfk()
end

-- Current points (0 .. Limit()).
function AfkWatch.Points()
    return state and state.points or 0
end

function AfkWatch.Limit()
    return limit()
end

-- fn() runs after every check; pass nil to remove it. Only one listener is kept.
function AfkWatch.SetListener(fn)
    listener = fn
end

function AfkWatch.Reset()
    state, elapsed = nil, 0
end

return AfkWatch
