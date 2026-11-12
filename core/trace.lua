local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")

-- Rolling debug trace written to AAC-TnT-RaidTools/debug.lua (path is relative to the addons
-- folder) so it can be read from disk when chat output is not visible.
local Trace = {}

local MAX_LINES = 150
local PATH = "AAC-TnT-RaidTools/debug.lua"
local lines = {}
local counter = 0

-- Nothing is written unless debug logging is on (whisper "/debug" to yourself to toggle it).
local function enabled()
    local ok, on = pcall(function() return settings.Get("DebugChat") end)
    return ok and on == true
end

function Trace.Add(text)
    if not enabled() then return end
    counter = counter + 1
    lines[#lines + 1] = counter .. " " .. tostring(text)
    if #lines > MAX_LINES then table.remove(lines, 1) end
    pcall(function() api.File:Write(PATH, {lines = lines}) end)
end

-- A log function that prefixes every line with "[tag] ".
function Trace.Logger(tag)
    local prefix = "[" .. tag .. "] "
    return function(text) Trace.Add(prefix .. text) end
end

-- Trace line plus a chat line, for state changes the player should see (not only while debugging).
function Trace.Announce(tag, text)
    Trace.Add("[" .. tag .. "] " .. text)
    pcall(function() api.Log:Info("[" .. constants.displayName .. "] " .. text) end)
end

return Trace
