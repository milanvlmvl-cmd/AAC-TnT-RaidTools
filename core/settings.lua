local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local Matching = require("AAC-TnT-RaidTools/core/matching")

local Settings = {}
local addonName = constants.addonName

local settings = nil

local function copyList(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    return copy
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

-- A new invite with the default values.
function Settings.NewInvite()
    return {Phrase = "x", Channel = "all", Match = "equals", BlacklistMode = "disabled", WhitelistMode = "disabled", Collapsed = false, Active = true}
end

-- Fill missing or invalid fields of an invite (from the file, or migrated) with the defaults.
local function normalizeInvite(entry)
    local invite = Settings.NewInvite()
    if type(entry) == "table" then
        if type(entry.Phrase) == "string" then invite.Phrase = entry.Phrase end
        if contains(constants.channelOrder, entry.Channel) then invite.Channel = entry.Channel end
        if contains(constants.matches, entry.Match) then invite.Match = entry.Match end
        if contains(constants.listModes, entry.BlacklistMode) then invite.BlacklistMode = entry.BlacklistMode end
        if contains(constants.listModes, entry.WhitelistMode) then invite.WhitelistMode = entry.WhitelistMode end
        invite.Collapsed = entry.Collapsed == true
        invite.Active = entry.Active ~= false -- missing (older saves) means active
    end
    return invite
end

-- Flat keys, same pattern as WorldSatNav. Name lists are arrays; all lists are arrays.
local defaultSettings = {
    -- Invite phrases: any number, each {Phrase, Channel, Match, BlacklistMode, WhitelistMode, Collapsed, Active}.
    -- Modes are "public" | "private" | "disabled": which shared list the invite checks (none when disabled).
    -- Always read a copy with GetInvites and write the whole list back with SetInvites.
    Invites = {},
    InvitesEnabled = true, -- global switch: when off, no invite sends anything (the list itself is kept)
    DisableInvitesWhenAfk = false, -- while you count as AFK (see constants.afk) no invite sends anything
    AfkMinutes = 2, -- minutes without movement before you count as AFK: one of constants.afk.minuteOptions

    -- Name lists (arrays), shared by both invites. One list per raid type.
    BlacklistPublic = {},
    BlacklistPrivate = {},
    WhitelistPublic = {},
    WhitelistPrivate = {},

    -- Raid sort
    RaidSortEnabled = false,
    RaidSortStyle = 2, -- 1 = "Class": tanks / healers / others in their own groups, 2 = "Party": each group 1 tank, 3 others, 1 healer

    RaidSortSaveGsClass = false, -- save a scanned player's real gear score + class to the players folder, and use it when they cannot be read

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

-- Copy of the invite list (safe to edit), and writing a whole edited list back.
function Settings.GetInvites()
    local list = {}
    local stored = Settings.Get("Invites")
    for i, invite in ipairs(type(stored) == "table" and stored or {}) do
        list[i] = normalizeInvite(invite)
    end
    return list
end

-- Move switched-off (Zzz) invites below the active ones, keeping the order inside each group.
-- Sorts `list` in place; returns the number of active invites and whether anything moved.
function Settings.SortInvites(list)
    local active, off = {}, {}
    for _, invite in ipairs(list) do
        if invite.Active == false then off[#off + 1] = invite else active[#active + 1] = invite end
    end
    local moved = false
    for i, invite in ipairs(active) do
        if list[i] ~= invite then moved = true end
        list[i] = invite
    end
    for i, invite in ipairs(off) do
        if list[#active + i] ~= invite then moved = true end
        list[#active + i] = invite
    end
    return #active, moved
end

-- Active invites are always kept at the top of the stored list (first match wins, so this does not
-- change which invite fires: switched-off ones never match). Returns the number of active invites.
function Settings.SetInvites(list)
    local active = Settings.SortInvites(list)
    Settings.Update("Invites", list)
    return active
end

-- Setting key of the list an invite uses for kind "Blacklist" or "Whitelist", given that invite's
-- mode ("public", "private" or "disabled"). nil when the mode is "disabled" (the list is not used).
function Settings.ActiveListKey(kind, mode)
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
            loaded[k] = Matching.splitNames(loaded[k])
        end
    end
    for i, invite in ipairs(loaded.Invites) do loaded.Invites[i] = normalizeInvite(invite) end
    -- a saved value that is no longer a valid choice goes back to the default
    if not contains(constants.leadChannelOrder, loaded.LeadChannel) then loaded.LeadChannel = defaultSettings.LeadChannel end
    if not contains(constants.afk.minuteOptions, loaded.AfkMinutes) then loaded.AfkMinutes = defaultSettings.AfkMinutes end
    if not contains(constants.sortStyles, loaded.RaidSortStyle) then loaded.RaidSortStyle = defaultSettings.RaidSortStyle end
    return loaded
end

-- Drop cached table (call on unload so a reload re-reads from disk).
function Settings.Reset()
    settings = nil
end

return Settings
