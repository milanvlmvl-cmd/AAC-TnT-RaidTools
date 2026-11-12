local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")

-- One chat line for state changes the player should see (AFK, raid tools paused / active).
local Notify = {}

function Notify.Chat(text)
    pcall(function() api.Log:Info("[" .. constants.displayName .. "] " .. text) end)
end

return Notify
