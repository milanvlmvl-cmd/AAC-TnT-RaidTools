-- TnT Raid Tools Main Module
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Ticker = require("AAC-TnT-RaidTools/core/ticker")
local raidtools = require("AAC-TnT-RaidTools/features/raidtools")
local raidsort = require("AAC-TnT-RaidTools/features/raidsort")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")
local panel = require("AAC-TnT-RaidTools/ui/panel")

local TnTRaidTools = {
    name = constants.displayName,
    author = "Wasbeerotb",
    version = constants.version,
    desc = "Raid invites and lead handoff tools"
}

function TnTRaidTools.OnLoad()
    settings.Reset()
    AfkWatch.Reset()
    raidtools.OnLoad()
    raidsort.OnLoad()
    -- one UPDATE callback for the whole addon: the AFK watch first, then the raid sort
    Ticker.Add(AfkWatch.Update)
    Ticker.Add(raidsort.Update)
    Ticker.Start()
    pcall(panel.OnLoad)
end

function TnTRaidTools.OnUnload()
    Ticker.Stop()
    raidsort.OnUnload()
    raidtools.OnUnload()
    panel.OnUnload()
    AfkWatch.Reset()
    settings.Reset()
end

TnTRaidTools.OnSettingToggle = panel.Show

return TnTRaidTools
