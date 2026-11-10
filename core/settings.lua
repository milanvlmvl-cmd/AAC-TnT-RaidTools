local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local Logic = require("AAC-TnT-RaidTools/logic")

local Settings = {}
local addonName = constants.addonName

local settings = nil

local function copyList(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    return copy
end

-- Flat keys, same pattern as WorldSatNav. Name lists are arrays; all lists are arrays.
local defaultSettings = {
    -- Invite phrases (1..inviteSlots). Each has its own on/off for the shared lists below.
    Invite1Enabled = false,
    Invite1Phrase = "x",
    Invite1Channel = "all",
    Invite1Match = "equals",
    Invite1BlacklistMode = "disabled", -- "public" | "private" | "disabled": which shared list this invite checks (none when disabled)
    Invite1WhitelistMode = "disabled",

    Invite2Enabled = false,
    Invite2Phrase = "x2",
    Invite2Channel = "all",
    Invite2Match = "equals",
    Invite2BlacklistMode = "disabled",
    Invite2WhitelistMode = "disabled",

    -- Name lists (arrays), shared by both invites. One list per raid type.
    BlacklistPublic = {},
    BlacklistPrivate = {},
    WhitelistPublic = {},
    WhitelistPrivate = {},

    -- Diagnostics
    DebugChat = false, -- extra trace lines for every chat event; toggled by whispering "/debug" to yourself

    -- Lead pass
    LeadPhrase = "lead",
    LeadChannel = "whisper", -- whisper | guild | raid
    LeadEnabled = false,
    LeadWhitelistEnabled = false,
    LeadWhitelist = {}, -- array of names allowed to take lead (old comma string migrates on load)
}

local function EnsureSettingsLoaded()
    if settings == nil then
        settings = Settings.LoadSettings()
    end
    return settings
end

function Settings.KeyExists(key)
    return key ~= nil and defaultSettings[key] ~= nil
end

function Settings.Is(key, value)
    return Settings.Get(key) == value
end

function Settings.Get(key)
    if not Settings.KeyExists(key) then
        return nil
    end
    local value = EnsureSettingsLoaded()[key]
    if value == nil then
        return defaultSettings[key]
    end
    return value
end

-- Mode of an invite's blacklist or whitelist: "public", "private" or "disabled".
function Settings.ListMode(kind, inviteIndex)
    return Settings.Get("Invite" .. inviteIndex .. kind .. "Mode")
end

-- Setting key of the list an invite uses for kind "Blacklist" or "Whitelist", chosen by that
-- invite's own mode. nil when the mode is "disabled" (the list is not used).
function Settings.ActiveListKey(kind, inviteIndex)
    local mode = Settings.ListMode(kind, inviteIndex)
    if mode == "private" then return kind .. "Private" end
    if mode == "public" then return kind .. "Public" end
    return nil
end

-- Array settings: always get a copy, change it, then Update() with the new array
-- (Update compares by reference, so editing the stored table in place would not save).
function Settings.GetList(key)
    local value = Settings.Get(key)
    return type(value) == "table" and copyList(value) or {}
end

function Settings.Update(key, value)
    if not Settings.KeyExists(key) then
        return false
    end
    local loaded = EnsureSettingsLoaded()
    if loaded[key] ~= value then
        loaded[key] = value
        api.SaveSettings()
    end
    return true
end

function Settings.LoadSettings()
    local loaded = api.GetSettings(addonName)
    if type(loaded) ~= "table" then
        loaded = {}
    end
    -- Fill missing keys in memory only. Real values persist on the first Update(),
    -- so a failed load can never overwrite a user's file with defaults.
    for k, v in pairs(defaultSettings) do
        if loaded[k] == nil then
            loaded[k] = type(v) == "table" and copyList(v) or v
        elseif type(v) == "table" and type(loaded[k]) == "string" then
            -- migrate old comma separated string to an array
            loaded[k] = Logic.splitNames(loaded[k])
        end
    end
    -- the per-invite Blacklist/Whitelist "Enabled" checkboxes became a "disabled" mode:
    -- an old unchecked box turns the mode to disabled, then the stale key is dropped
    for index = 1, constants.inviteSlots do
        for _, kind in ipairs({"Blacklist", "Whitelist"}) do
            local oldKey = "Invite" .. index .. kind .. "Enabled"
            if loaded[oldKey] ~= nil then
                if loaded[oldKey] == false then loaded["Invite" .. index .. kind .. "Mode"] = "disabled" end
                loaded[oldKey] = nil
            end
        end
    end
    -- lead pass no longer offers "all"; move an old saved value to the default
    local validLeadChannel = false
    for _, name in ipairs(constants.leadChannelOrder) do
        if loaded.LeadChannel == name then validLeadChannel = true end
    end
    if not validLeadChannel then loaded.LeadChannel = defaultSettings.LeadChannel end
    return loaded
end

-- Drop cached table (call on unload so a reload re-reads from disk).
function Settings.Reset()
    settings = nil
end

return Settings
