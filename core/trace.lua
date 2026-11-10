local api = require("api")

-- Rolling debug trace written to AAC-TnT-RaidTools/debug.lua (path is relative to the addons
-- folder) so it can be read from disk when chat output is not visible.
local Trace = {}

local MAX_LINES = 150
local PATH = "AAC-TnT-RaidTools/debug.lua"
local lines = {}
local counter = 0

function Trace.Add(text)
    counter = counter + 1
    lines[#lines + 1] = counter .. " " .. tostring(text)
    if #lines > MAX_LINES then table.remove(lines, 1) end
    pcall(function() api.File:Write(PATH, {lines = lines}) end)
end

return Trace
