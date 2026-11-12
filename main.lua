-- TnT Raid Tools Main Module
local constants = require("AAC-TnT-RaidTools/core/constants")
local Matching = require("AAC-TnT-RaidTools/core/matching")
local settings = require("AAC-TnT-RaidTools/core/settings")
local trace = require("AAC-TnT-RaidTools/core/trace")
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

trace.Add("main.lua loaded")

function TnTRaidTools.OnLoad()
    raidtools.Log("Starting version " .. TnTRaidTools.version)
    settings.Reset()
    -- every Matching.check writes one line to the trace file
    Matching.trace = trace.Add
    AfkWatch.Reset()
    raidtools.OnLoad()
    raidsort.OnLoad()
    -- one UPDATE callback for the whole addon: the AFK watch first, then the raid sort
    Ticker.Add(AfkWatch.Update)
    Ticker.Add(raidsort.Update)
    Ticker.Start()
    local ok, err = pcall(panel.OnLoad)
    raidtools.Log(ok and "panel built" or ("panel failed: " .. tostring(err)))
end

function TnTRaidTools.OnUnload()
    Matching.trace = nil
    Ticker.Stop()
    raidsort.OnUnload()
    raidtools.OnUnload()
    panel.OnUnload()
    AfkWatch.Reset()
    settings.Reset()
end

TnTRaidTools.OnSettingToggle = panel.Show

return TnTRaidTools
