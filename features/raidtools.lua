local api = require("api")
local Matching = require("AAC-TnT-RaidTools/core/matching")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")

-- Chat-driven tools: auto invites and lead pass.
local RaidTools = {}

local live = false

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
    if not settings.Get("InvitesEnabled") or AfkWatch.Blocks() then return false end
    for _, invite in ipairs(settings.Get("Invites")) do -- stored list, read only (normalised on load / by the editor)
        -- cheap check first: every chat line in every channel passes through here, so only invites
        -- whose phrase matches get the full check
        if invite.Active ~= false and Matching.matchesPhrase(message, invite.Phrase, invite.Match) then
            local config = inviteConfig(invite)
            local ok = Matching.check({name = speakerName, text = message}, channelId, config, config.blacklist, config.whitelist)
            if ok then
                if not Authority.CanManage() then return true end
                -- already in the raid: not taken, the same words may still be the lead pass keyword
                if isInTeam(speakerName) then return false end
                api.Team:InviteToTeam(speakerName, false)
                return true -- one invite per message even if several invites match
            end
        end
    end
    return false
end

local function passLead(name)
    local index = api.Team:GetMemberIndexByName(name)
    if not index or index == 0 then return false end
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

local function onChat(...)
    local channelId, _, _, speakerName, message = ...
    if not live then return end
    if not speakerName or type(message) ~= "string" then return end
    if handleInvites(channelId, speakerName, message) then return end
    handleLeadPass(channelId, speakerName, message)
end

-- api.On keeps one callback per event, so another addon using CHAT_MESSAGE can replace ours.
function RaidTools.OnLoad()
    api.On("CHAT_MESSAGE", onChat)
    live = true
end

function RaidTools.OnUnload()
    live = false
    api.On("CHAT_MESSAGE", function() return end)
end

return RaidTools
