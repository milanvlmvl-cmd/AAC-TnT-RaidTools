local api = require("api")
local Logic = require("AAC-TnT-RaidTools/logic")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local trace = require("AAC-TnT-RaidTools/core/trace")

local RaidTools = {}

local live = false

function RaidTools.Log(text)
    trace.Add(text)
end

-- Build the config table Logic.eligible expects from the flat settings keys.
local function inviteConfig(index)
    local key = "Invite" .. index
    return {
        enabled = settings.Get(key .. "Enabled"),
        channel = settings.Get(key .. "Channel"),
        match = settings.Get(key .. "Match"),
        phrase = settings.Get(key .. "Phrase"),
        -- the name lists are shared; each invite picks public, private or disabled for each
        whitelistEnabled = settings.ListMode("Whitelist", index) ~= "disabled",
        blacklistEnabled = settings.ListMode("Blacklist", index) ~= "disabled",
        whitelist = Logic.lookup(settings.Get(settings.ActiveListKey("Whitelist", index))),
        blacklist = Logic.lookup(settings.Get(settings.ActiveListKey("Blacklist", index))),
    }
end

local function isInTeam(name)
    local index = api.Team:GetMemberIndexByName(name)
    return index ~= nil and index ~= 0
end

local function debug(text)
    if settings.Get("DebugChat") then RaidTools.Log("[debug] " .. text) end
end

local function handleInvites(channelId, speakerName, message)
    local debugging = settings.Get("DebugChat")
    for index = 1, constants.inviteSlots do
        -- cheap check first: every chat line in every channel passes through here
        if settings.Get("Invite" .. index .. "Enabled") then
            local config = inviteConfig(index)
            local ok, reason = Logic.check({name = speakerName, text = message}, channelId, config, config.blacklist, config.whitelist)
            if ok then
                if isInTeam(speakerName) then
                    debug("invite " .. index .. ": matched, but " .. speakerName .. " is already in the raid")
                    return
                end
                RaidTools.Log("Inviting " .. speakerName)
                api.Team:InviteToTeam(speakerName, false)
                return true -- one invite per message even if both phrases match
            elseif debugging then
                debug("invite " .. index .. " skipped: " .. reason)
            end
        elseif debugging then
            debug("invite " .. index .. " skipped: Enabled checkbox is off")
        end
    end
    return false
end

local function passLead(name)
    local index = api.Team:GetMemberIndexByName(name)
    if not index or index == 0 then
        RaidTools.Log("Speaker is not in the raid: " .. name)
        return false
    end
    return api.Team:MakeTeamOwner("team" .. index) ~= false
end

local function handleLeadPass(channelId, speakerName, message)
    if not settings.Get("LeadEnabled") or not Logic.channelAllowed(channelId, settings.Get("LeadChannel")) then return end
    if not Logic.matchesPhrase(message, settings.Get("LeadPhrase"), "equals") then return end
    if settings.Get("LeadWhitelistEnabled") then
        local allowed = Logic.lookup(settings.Get("LeadWhitelist"))
        if not allowed[Logic.normalizeName(speakerName)] then return end
    end
    passLead(speakerName)
end

local firstEventLogged = false

-- Your own character name, for the whisper-to-self debug command.
local function ownName()
    local name = api.Unit:UnitName("player")
    if name == nil then
        local info = api.Unit:GetUnitInfoById(api.Unit:GetUnitId("player"))
        name = info and info.name
    end
    return name
end

-- "/debug" whispered by yourself toggles the extra debug trace. Returns true when handled.
local function handleDebugCommand(channelId, speakerName, message)
    if channelId ~= constants.channels.whisper then return false end
    if Logic.normalizeName(message) ~= "/debug" then return false end
    local me = ownName()
    if me == nil or Logic.normalizeName(speakerName) ~= Logic.normalizeName(me) then return false end
    local on = not settings.Get("DebugChat")
    settings.Update("DebugChat", on)
    RaidTools.Log("debug log " .. (on and "ON" or "OFF"))
    api.Log:Info("[" .. constants.displayName .. "] debug log " .. (on and "ON" or "OFF"))
    return true
end

local function onChat(...)
    local channelId, speakerId, extra, speakerName, message = ...
    RaidTools.Log("CHAT_MESSAGE channelId " .. tostring(channelId) .. " speakerName " .. tostring(speakerName) .. " message " .. tostring(message))
    if settings.Get("DebugChat") then
        -- the game's Lua has no global `select`, so read the arguments through a table
        local args = {...}
        local parts = {}
        for i = 1, 8 do parts[i] = i .. "=" .. tostring(args[i]) end
        RaidTools.Log("[debug] CHAT_MESSAGE live=" .. tostring(live) .. " " .. table.concat(parts, " | "))
    end
    if not live then 
        debug("ignored: not live")
        return 
    end
    if not speakerName or type(message) ~= "string" then
        debug("ignored: speaker name or message text is missing (arg order may differ)")
        return
    end
    if handleDebugCommand(channelId, speakerName, message) then return end
    if handleInvites(channelId, speakerName, message) then return end
    handleLeadPass(channelId, speakerName, message)
end

-- Two delivery paths are wired up: api.On (what Actually_Useable_X_Up uses, confirmed to
-- deliver in this game build) and a hidden window's OnEvent (WorldSatNav/PlayerDB pattern).
-- Whichever delivers first becomes the only source we act on, so nothing is handled twice.
-- api.On keeps one callback per event, so another addon using CHAT_MESSAGE can replace ours.
local eventWindow
local activeSource

function RaidTools.OnLoad()
    firstEventLogged = false
    activeSource = nil
    rawLogged = 0
    api.On("CHAT_MESSAGE", onChat)
    RaidTools.Log("chat listeners registered: api.On + window (debug log " .. (settings.Get("DebugChat") and "ON" or "OFF") .. ")")
    live = true
end

function RaidTools.OnUnload()
    live = false
    api.On("CHAT_MESSAGE", nil)
end

return RaidTools
