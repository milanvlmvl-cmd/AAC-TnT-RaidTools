local api = require("api")
local Matching = require("AAC-TnT-RaidTools/core/matching")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local trace = require("AAC-TnT-RaidTools/core/trace")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")

-- Chat-driven tools: auto invites, lead pass and the "/debug" whisper command.
local RaidTools = {}

local live = false

function RaidTools.Log(text)
    trace.Add(text)
end

-- Extra trace lines, only while debug logging is on.
local function debug(text)
    if settings.Get("DebugChat") then RaidTools.Log("[debug] " .. text) end
end

-- Build the config table Matching.check expects from an invite.
local function inviteConfig(invite)
    return {
        channel = invite.Channel,
        match = invite.Match,
        phrase = invite.Phrase,
        -- the name lists are shared; each invite picks public, private or disabled for each
        whitelistEnabled = invite.WhitelistMode ~= "disabled",
        blacklistEnabled = invite.BlacklistMode ~= "disabled",
        whitelist = Matching.lookup(settings.Get(settings.ActiveListKey("Whitelist", invite.WhitelistMode))),
        blacklist = Matching.lookup(settings.Get(settings.ActiveListKey("Blacklist", invite.BlacklistMode))),
    }
end

local function isInTeam(name)
    local index = api.Team:GetMemberIndexByName(name)
    return index ~= nil and index ~= 0
end

-- Returns true when the message was taken by an invite (so the lead pass must not also see it).
local function handleInvites(channelId, speakerName, message)
    if not settings.Get("InvitesEnabled") then
        debug("invites skipped: global invites switch is off")
        return false
    end
    if AfkWatch.Blocks() then
        debug("invites skipped: you are AFK")
        return false
    end
    local debugging = settings.Get("DebugChat")
    for index, invite in ipairs(settings.Get("Invites")) do -- stored list, read only (normalised on load / by the editor)
        -- cheap check first: every chat line in every channel passes through here, so unless debugging
        -- only invites whose phrase matches get the full check (which writes a trace line)
        if invite.Active == false then
            debug("invite " .. index .. " skipped: switched off (Zzz)")
        elseif debugging or Matching.matchesPhrase(message, invite.Phrase, invite.Match) then
            local config = inviteConfig(invite)
            local ok, reason = Matching.check({name = speakerName, text = message}, channelId, config, config.blacklist, config.whitelist)
            if ok then
                if not Authority.CanManage() then
                    debug("invite " .. index .. ": matched, but you are not raid lead")
                    return true
                end
                if isInTeam(speakerName) then
                    -- not taken: the same words may still be the lead pass keyword
                    debug("invite " .. index .. ": matched, but " .. speakerName .. " is already in the raid")
                    return false
                end
                RaidTools.Log("Inviting " .. speakerName)
                api.Team:InviteToTeam(speakerName, false)
                return true -- one invite per message even if several invites match
            end
            debug("invite " .. index .. " skipped: " .. reason)
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
    if not settings.Get("LeadEnabled") or not Matching.channelAllowed(channelId, settings.Get("LeadChannel")) then return end
    if not Matching.matchesPhrase(message, settings.Get("LeadPhrase"), "equals") then return end
    if settings.Get("LeadWhitelistEnabled") then
        local allowed = Matching.lookup(settings.Get("LeadWhitelist"))
        if not allowed[Matching.normalizeName(speakerName)] then return end
    end
    passLead(speakerName)
end

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
    if Matching.normalizeName(message) ~= "/debug" then return false end
    local me = ownName()
    if me == nil or Matching.normalizeName(speakerName) ~= Matching.normalizeName(me) then return false end
    local on = not settings.Get("DebugChat")
    settings.Update("DebugChat", on)
    trace.Announce("debug", "debug log " .. (on and "ON" or "OFF"))
    return true
end

local function onChat(...)
    local channelId, _, _, speakerName, message = ...
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

-- api.On keeps one callback per event, so another addon using CHAT_MESSAGE can replace ours.
function RaidTools.OnLoad()
    api.On("CHAT_MESSAGE", onChat)
    RaidTools.Log("chat listener registered (debug log " .. (settings.Get("DebugChat") and "ON" or "OFF") .. ")")
    live = true
end

function RaidTools.OnUnload()
    live = false
    api.On("CHAT_MESSAGE", function() return end)
end

return RaidTools
