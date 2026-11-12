local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local raidtools = require("AAC-TnT-RaidTools/features/raidtools")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")
local ListPanel = require("AAC-TnT-RaidTools/ui/listpanel")
local SortWindow = require("AAC-TnT-RaidTools/ui/sortwindow")
local InviteList = require("AAC-TnT-RaidTools/ui/invitelist")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")

local Panel = {}

local panel -- main panel under the raid window
local sortWindow
local inviteList -- left of the raid window
local editors = {} -- ["Blacklist"] / ["Whitelist"] / ["Lead"] -> ListPanel
local make = Widgets.Make

-- Textbox that writes straight to a string setting.
local function textBox(parent, id, x, y, width, key)
    local box = make("textbox", id, parent, x, y, width, 22, settings.Get(key))
    local function save() settings.Update(key, box:GetText()) end
    for _, event in ipairs(Widgets.textEvents) do
        box:SetHandler(event, save)
    end
    return box
end

local function caption(parent, id, x, y, text)
    return make("label", id, parent, x, y, 90, 18, text)
end

-- Both sections share one layout so the columns line up: a title row (title left, Enabled
-- checkbox right), a one-line description, captions at y + 50, controls at y + 72.

-- Title row: `title` on the left, "Enabled" and its checkbox on the right. onChange(checked) fires on clicks.
local function sectionHeader(id, x, y, width, title, about, enabled, onChange)
    make("label", id .. "_title", panel, x, y, width - 100, 22, title)
    local boxX = x + width - 25
    make("label", id .. "_enabled_label", panel, boxX - 62, y + 2, 56, 22, "Enabled")
    Widgets.Checkbox(id .. "_enable", panel, nil, boxX, y - 2, enabled, onChange)
    make("label", id .. "_about", panel, x, y + 26, width, 18, about)
end

local afkLabel -- "afk ticks:  N / 30"

-- Runs after every AFK check and when the AFK setting changes: the tick label, and the "you are AFK"
-- notices over the invite list and the raid sort window.
local function refreshAfkLabel()
    if afkLabel then afkLabel:SetText("afk ticks:  " .. AfkWatch.Points() .. " / " .. AfkWatch.Limit()) end
    if inviteList then inviteList.RefreshNotice() end
    if sortWindow then sortWindow.RefreshNotice() end
end

-- Left section: invites. The switch turns every invite in the invite list on or off (the list is kept);
-- the name lists are shared by all invites. Each list editor has a PUBLIC / PRIVATE toggle at the top.
local function buildInviteSection(x, y, width)
    sectionHeader("inv", x, y, width, "INVITES", "Anyone who says a keyword is invited.", settings.Get("InvitesEnabled"), function(checked)
        settings.Update("InvitesEnabled", checked)
        if inviteList then inviteList.SetGlobalEnabled(checked) end
        if sortWindow then sortWindow.RefreshNotice() end
    end)
    make("label", "lists_caption", panel, x, y + 50, width, 18, "Name lists (shared by all invites)")
    local col = 0
    for _, kind in ipairs({"Blacklist", "Whitelist"}) do
        local button = make("button", "edit_" .. kind:lower(), panel, x + col * 142, y + 72, 136, 24, string.upper(kind))
        button:SetHandler("OnClick", function()
            panel:Show(false)
            editors[kind].Open()
        end)
        col = col + 1
    end
    make("label", "lists_hint", panel, x, y + 102, width, 18, "Click a list to add or remove names")

    -- pause every invite and the raid sort while you look AFK (no movement for the chosen number of minutes)
    Widgets.Checkbox("afk_disable", panel, "Disable if afk", x, y + 124, settings.Get("DisableInvitesWhenAfk"), function(checked)
        settings.Update("DisableInvitesWhenAfk", checked)
        refreshAfkLabel()
    end)
    local minuteLabels = {}
    for i, minutes in ipairs(constants.afk.minuteOptions) do minuteLabels[i] = minutes .. " mins" end
    Widgets.SettingDropdown(panel, x + 195, y + 124, 85, "AfkMinutes", constants.afk.minuteOptions, minuteLabels, function()
        AfkWatch.Reset() -- the limit changed: count from scratch
        refreshAfkLabel()
    end)
    afkLabel = make("label", "afk_ticks", panel, x + 31, y + 150, width - 31, 18, "")
    refreshAfkLabel()
    AfkWatch.SetListener(refreshAfkLabel)
end

-- Right section: lead pass (hand raid lead to whoever says the keyword).
local function buildLeadSection(x, y, width)
    sectionHeader("lead", x, y, width, "LEAD PASS", "Gives raid lead to whoever says the keyword.", settings.Get("LeadEnabled"), function(checked)
        settings.Update("LeadEnabled", checked)
    end)
    caption(panel, "lead_cap_keyword", x, y + 50, "Keyword")
    caption(panel, "lead_cap_channel", x + 95, y + 50, "Channel")
    textBox(panel, "lead_phrase", x, y + 72, 90, "LeadPhrase")
    Widgets.SettingCycleButton(panel, "lead_channel", x + 95, y + 72, 90, "LeadChannel", constants.leadChannelOrder)

    -- restrict lead pass to the names in its list
    Widgets.Checkbox("lead_allow", panel, "Only listed names", x, y + 100, settings.Get("LeadWhitelistEnabled"), function(checked)
        settings.Update("LeadWhitelistEnabled", checked)
    end)
    local edit = make("button", "lead_edit", panel, x + 190, y + 101, 90, 24, "EDIT LIST")
    edit:SetHandler("OnClick", function()
        panel:Show(false)
        editors.Lead.Open()
    end)
end

function Panel.OnLoad()
    local root = ADDON:GetContent(UIC.RAID_MANAGER)
    if root == nil then
        raidtools.Log("Raid manager content was unavailable.")
        return
    end
    local dims = constants.panel
    Authority.Reset() -- the windows below subscribe to lead changes
    -- own window below the raid window; the raid window itself is not resized or modified
    panel = make("emptywidget", "panel", root, 0, 0, dims.width, dims.mainHeight)
    Widgets.AnchorBelow(panel, root, dims.gap)
    Widgets.AddBackground(panel, "bg", dims.width, dims.mainHeight)

    for _, kind in ipairs({"Blacklist", "Whitelist"}) do
        editors[kind] = ListPanel.Create(root, {
            id = kind:lower(), title = kind:upper(), onClose = Panel.Show,
            keys = {public = kind .. "Public", private = kind .. "Private"},
            hint = function(mode)
                local used = "Used by invites whose " .. kind .. " mode is " .. mode:upper() .. "."
                if kind == "Blacklist" then return "These players are never invited. " .. used end
                return "Only these players are invited. " .. used
            end,
        })
    end

    editors.Lead = ListPanel.Create(root, {
        id = "lead", title = "LEAD PASS  -  allowed names", settingKey = "LeadWhitelist", onClose = Panel.Show,
        hint = "When \"Only listed names\" is ticked, only these players can take lead.",
    })

    inviteList = InviteList.Create(root) -- left side of the raid window, with the + button
    sortWindow = SortWindow.Create(root) -- right side of the raid window

    -- header bar (debug logging is toggled by whispering "/debug" to yourself, see raidtools.lua)
    make("label", "heading", panel, 10, 8, 300, 24, "TnT RAID TOOLS")
    Widgets.Divider(panel, "divider_header", 10, 36, dims.width - 20, 2)

    local half = dims.width / 2
    make("label", "version", panel, dims.width - 70, 10, 60, 20, "v" .. constants.version)
    buildInviteSection(10, 48, half - 20)
    Widgets.Divider(panel, "divider_columns", half - 1, 48, 2, dims.mainHeight - 60)
    buildLeadSection(half + 10, 48, half - 20)
end

function Panel.Show()
    if panel then panel:Show(true) end
end

function Panel.OnUnload()
    Authority.Reset() -- drop the window listeners before the widgets are freed
    AfkWatch.SetListener(nil)
    Widgets.FreeAll()
    afkLabel = nil
    panel = nil
    inviteList = nil
    sortWindow = nil
    editors = {}
end

return Panel
