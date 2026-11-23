-- TnT Raid Tools Main Module
local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Ticker = require("AAC-TnT-RaidTools/core/ticker")
local raidtools = require("AAC-TnT-RaidTools/features/raidtools")
local raidsort = require("AAC-TnT-RaidTools/features/raidsort")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")
local MarkControl = require("AAC-TnT-RaidTools/features/markcontrol")
local AutoHeart = require("AAC-TnT-RaidTools/features/autoheart")
local panel = require("AAC-TnT-RaidTools/ui/panel")

local TnTRaidTools = {
    name = constants.displayName,
    author = "Wasbeerotb",
    version = constants.version,
    desc = "Raid invites and lead handoff tools"
}

local function log(text)
    pcall(function() api.Log:Info("[" .. constants.displayName .. "] " .. text) end)
end

function TnTRaidTools.OnLoad()
    settings.Reset()
    AfkWatch.Reset()
    MarkControl.Reset()
    AutoHeart.Reset()
    raidtools.OnLoad()
    raidsort.OnLoad()
    -- one UPDATE callback for the whole addon: the AFK watch first, then the raid sort, then the marks
    Ticker.Add(AfkWatch.Update)
    Ticker.Add(raidsort.Update)
    Ticker.Add(AutoHeart.Update)
    Ticker.Add(MarkControl.Update)
    Ticker.Start()
    local ok, err = pcall(panel.OnLoad)
    if not ok then log("panel failed: " .. tostring(err)) end
end

function TnTRaidTools.OnUnload()
    Ticker.Stop()
    raidsort.OnUnload()
    raidtools.OnUnload()
    panel.OnUnload()
    MarkControl.Reset()
    AutoHeart.Reset()
    AfkWatch.Reset()
    settings.Reset()
end

TnTRaidTools.OnSettingToggle = panel.Show

return TnTRaidTools
