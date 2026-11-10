local Logic = require("tnt_raid_tools/logic")
local addon = {
    name = "TnT Raid Tools",
    author = "Wasbeerotb",
    version = "0.1.0",
    desc = "Raid invites and lead handoff tools"
}

local api, settings, panel, widgets, live
local call, get = Logic.call, Logic.get
local addonId = "tnt_raid_tools"

local function log(text)
    call(get(api, "Log"), "Info", "[" .. addon.name .. "] " .. text)
end

local function defaults()
    return {
        phrases = {
            {phrase = "x", channel = "all", match = "equals", enabled = false, whitelistEnabled = false, blacklistEnabled = false, whitelist = {}, blacklist = {}},
            {phrase = "x2", channel = "all", match = "equals", enabled = false, whitelistEnabled = false, blacklistEnabled = false, whitelist = {}, blacklist = {}}
        },
        lead = {phrase = "lead", channel = "all", enabled = false, whitelistEnabled = false, whitelist = {}}
    }
end

local function loadSettings()
    local getSettings = get(api, "GetSettings")
    local ok, saved = false, nil
    if type(getSettings) == "function" then ok, saved = pcall(getSettings, addonId) end
    settings = ok and type(saved) == "table" and saved or defaults()
    settings.phrases = type(settings.phrases) == "table" and settings.phrases or {}
    local base = defaults()
    for i = 1, 2 do
        settings.phrases[i] = settings.phrases[i] or base.phrases[i]
        settings.phrases[i].phrase = settings.phrases[i].phrase or base.phrases[i].phrase
        settings.phrases[i].channel = settings.phrases[i].channel or base.phrases[i].channel
        settings.phrases[i].match = settings.phrases[i].match or base.phrases[i].match
        settings.phrases[i].blacklistEnabled = settings.phrases[i].blacklistEnabled == true
        settings.phrases[i].whitelist = settings.phrases[i].whitelist or {}
        settings.phrases[i].blacklist = settings.phrases[i].blacklist or {}
    end
    settings.lead = settings.lead or base.lead
    settings.lead.phrase = settings.lead.phrase or base.lead.phrase
    settings.lead.channel = settings.lead.channel or base.lead.channel
    settings.lead.whitelist = settings.lead.whitelist or {}
end

local function saveSettings()
    local save = get(api, "SaveSettings")
    if type(save) == "function" then pcall(save) end
end

local function dispose()
    if not widgets then return end
    for i = #widgets, 1, -1 do
        local w = widgets[i]
        for _, event in ipairs({"OnClick", "OnChanged"}) do call(w, "ReleaseHandler", event) end
        call(w, "Show", false)
        call(get(api, "Interface"), "Free", w)
    end
    widgets, panel = nil, nil
end

local function addWidget(w)
    if w then widgets[#widgets + 1] = w end
    return w
end

local function make(kind, id, parent, x, y, width, height, text)
    local ok, w
    if kind == "textbox" and W_CTRL and type(W_CTRL.CreateEdit) == "function" then
        ok, w = pcall(W_CTRL.CreateEdit, addonId .. "_" .. id, parent)
    else
        local create = get(parent, "CreateChildWidget")
        if type(create) ~= "function" then return nil end
        ok, w = pcall(create, parent, kind, addonId .. "_" .. id, 0, true)
    end
    if not ok or not w then return nil end
    addWidget(w)
    call(w, "SetExtent", width, height)
    call(w, "AddAnchor", "TOPLEFT", parent, x, y)
    if text then call(w, "SetText", text) end
    call(w, "Show", true)
    return w
end

local function textValue(w)
    local ok, value = call(w, "GetText")
    return ok and type(value) == "string" and value or ""
end

local function cycle(current, values)
    for i, value in ipairs(values) do
        if value == current then return values[i % #values + 1] end
    end
    return values[1]
end

local function setToggle(button, label, value)
    if button then
        call(button, "SetText", label .. (value and ": ON" or ": OFF"))
    end
end

local function bindText(widget, fn)
    if not widget then return end
    for _, event in ipairs({"OnChanged", "OnTextChanged", "OnFocusLost", "OnEnterPressed"}) do
        pcall(function() call(widget, "SetHandler", event, fn) end)
    end
end

local channels = {"all", "nation", "faction", "guild", "whisper"}
local matches = {"equals", "includes", "starts"}

local function inviteWhitelist(config)
    for _, name in ipairs(config.whitelist) do
        call(get(api, "Team"), "InviteToTeam", name, false)
    end
end

local function buildPanel()
    widgets = {}
    local getContent = get(ADDON, "GetContent")
    local ok, root = false, nil
    if type(getContent) == "function" then ok, root = pcall(getContent, ADDON, UIC.RAID_MANAGER) end
    if not ok or not root then
        log("Raid manager content was unavailable.")
        return
    end
    local widthOk, width = call(root, "GetWidth")
    width = widthOk and tonumber(width) or 620
    call(root, "SetExtent", math.max(width, 620), 720)
    panel = make("emptywidget", "panel", root, 10, 340, 600, 360)
    if not panel then return end
    make("label", "heading", panel, 10, 8, 580, 24, "TnT RAID TOOLS  |  click blue controls to change settings")
    local y = 34
    for index = 1, 2 do
        local config = settings.phrases[index]
        make("label", "p" .. index .. "_label", panel, 10, y, 70, 22, "INVITE " .. index)
        local phrase = make("textbox", "p" .. index .. "_phrase", panel, 82, y, 150, 22, config.phrase)
        local channel = make("button", "p" .. index .. "_channel", panel, 240, y, 100, 22, string.upper(config.channel))
        local match = make("button", "p" .. index .. "_match", panel, 348, y, 100, 22, string.upper(config.match))
        local enable = make("button", "p" .. index .. "_enable", panel, 10, y + 27, 105, 22)
        local allow = make("button", "p" .. index .. "_allow", panel, 121, y + 27, 125, 22)
        local block = make("button", "p" .. index .. "_block", panel, 252, y + 27, 125, 22)
        local invite = make("button", "p" .. index .. "_invite", panel, 383, y + 27, 125, 22, "INVITE LIST")
        setToggle(enable, "ACTIVE", config.enabled)
        setToggle(allow, "WHITELIST", config.whitelistEnabled)
        setToggle(block, "BLACKLIST", config.blacklistEnabled)
        call(channel, "SetHandler", "OnClick", function()
            config.channel = cycle(config.channel, channels); call(channel, "SetText", config.channel); saveSettings()
        end)
        call(match, "SetHandler", "OnClick", function()
            config.match = cycle(config.match, matches); call(match, "SetText", config.match); saveSettings()
        end)
        call(enable, "SetHandler", "OnClick", function()
            config.enabled = not config.enabled; setToggle(enable, "ACTIVE", config.enabled); saveSettings()
        end)
        call(allow, "SetHandler", "OnClick", function()
            config.whitelistEnabled = not config.whitelistEnabled; setToggle(allow, "WHITELIST", config.whitelistEnabled); saveSettings()
        end)
        call(block, "SetHandler", "OnClick", function()
            config.blacklistEnabled = not config.blacklistEnabled; setToggle(block, "BLACKLIST", config.blacklistEnabled); saveSettings()
        end)
        local white = make("textbox", "p" .. index .. "_white", panel, 10, y + 55, 240, 22, table.concat(config.whitelist, ", "))
        local black = make("textbox", "p" .. index .. "_black", panel, 252, y + 55, 256, 22, table.concat(config.blacklist, ", "))
        bindText(phrase, function() config.phrase = textValue(phrase); saveSettings() end)
        bindText(white, function() config.whitelist = Logic.splitNames(textValue(white)); saveSettings() end)
        bindText(black, function() config.blacklist = Logic.splitNames(textValue(black)); saveSettings() end)
        call(invite, "SetHandler", "OnClick", function() inviteWhitelist(config) end)
        make("label", "p" .. index .. "_hint", panel, 10, y + 80, 500, 18, "Whitelist names                         Blacklist names (toggle above)")
        y = y + 105
    end
    local lead = settings.lead
    make("label", "lead_label", panel, 10, y, 90, 22, "LEAD PASS")
    local phrase = make("textbox", "lead_phrase", panel, 102, y, 150, 22, lead.phrase)
    local channel = make("button", "lead_channel", panel, 260, y, 100, 22, string.upper(lead.channel))
    local enable = make("button", "lead_enable", panel, 10, y + 27, 105, 22)
    local allow = make("button", "lead_allow", panel, 121, y + 27, 125, 22)
    setToggle(enable, "ACTIVE", lead.enabled)
    setToggle(allow, "WHITELIST", lead.whitelistEnabled)
    local white = make("textbox", "lead_white", panel, 260, y + 27, 248, 22, table.concat(lead.whitelist, ", "))
    make("label", "lead_hint", panel, 260, y + 52, 248, 18, "Allowed names, comma-separated")
    call(channel, "SetHandler", "OnClick", function()
        lead.channel = cycle(lead.channel, channels); call(channel, "SetText", lead.channel); saveSettings()
    end)
    call(enable, "SetHandler", "OnClick", function()
        lead.enabled = not lead.enabled; setToggle(enable, "ACTIVE", lead.enabled); saveSettings()
    end)
    call(allow, "SetHandler", "OnClick", function()
        lead.whitelistEnabled = not lead.whitelistEnabled; setToggle(allow, "WHITELIST", lead.whitelistEnabled); saveSettings()
    end)
    bindText(phrase, function() lead.phrase = textValue(phrase); saveSettings() end)
    bindText(white, function() lead.whitelist = Logic.splitNames(textValue(white)); saveSettings() end)
end

local function onChat(channelId, _, _, speakerName, message)
    if not live or not settings or not speakerName or type(message) ~= "string" then return end
    for _, config in ipairs(settings.phrases) do
        local blacklist = Logic.lookup(config.blacklist)
        local whitelist = Logic.lookup(config.whitelist)
        if Logic.eligible({name = speakerName, text = message}, channelId, config, blacklist, whitelist) then
            log("Inviting " .. speakerName)
            call(get(api, "Team"), "InviteToTeam", speakerName, false)
        end
    end
    local lead = settings.lead
    local leadWhitelist = Logic.lookup(lead.whitelist)
    local sender = Logic.normalizeName(speakerName)
    if lead.enabled and Logic.channelAllowed(channelId, lead.channel)
        and Logic.matchesPhrase(message, lead.phrase, "equals")
        and (not lead.whitelistEnabled or leadWhitelist[sender]) then
        Logic.passLead(get(api, "Team"), speakerName, log)
    end
end

function addon.OnLoad()
    live = false
    api = require("api")
    loadSettings()
    live = true
    buildPanel()
    local subscribe = get(api, "On")
    if type(subscribe) == "function" then pcall(subscribe, "CHAT_MESSAGE", onChat) end
end

function addon.OnSettingToggle()
    if panel then call(panel, "Show", true) end
end

function addon.OnUnload()
    live = false
    dispose()
    api, settings = nil, nil
end

return addon
