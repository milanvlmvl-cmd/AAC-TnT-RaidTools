-- TnT Raid Tools Main Module
local constants = require("AAC-TnT-RaidTools/core/constants")
local Logic = require("AAC-TnT-RaidTools/logic")
local settings = require("AAC-TnT-RaidTools/core/settings")
local raidtools = require("AAC-TnT-RaidTools/features/raidtools")
local raidsort = require("AAC-TnT-RaidTools/features/raidsort")
local panel = require("AAC-TnT-RaidTools/ui/panel")
local trace = require("AAC-TnT-RaidTools/core/trace")

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
    -- every Logic.check writes one line to the trace file
    Logic.trace = trace.Add
    raidtools.OnLoad()
    raidsort.OnLoad()
    local ok, err = pcall(panel.OnLoad)
    raidtools.Log(ok and "panel built" or ("panel failed: " .. tostring(err)))
end

function TnTRaidTools.OnUnload()
    Logic.trace = nil
    raidsort.OnUnload()
    raidtools.OnUnload()
    panel.OnUnload()
    settings.Reset()
end

TnTRaidTools.OnSettingToggle = panel.Show

return TnTRaidTools
