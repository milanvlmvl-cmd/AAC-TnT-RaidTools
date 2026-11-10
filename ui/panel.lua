local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local raidtools = require("AAC-TnT-RaidTools/features/raidtools")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")
local ListPanel = require("AAC-TnT-RaidTools/ui/listpanel")
local SortWindow = require("AAC-TnT-RaidTools/ui/sortwindow")

local Panel = {}

local panel -- main panel under the raid window
local sortWindow
local inviteWindows = {} -- [1] left of the raid window, [2] right of it
local editors = {} -- ["Blacklist"] / ["Whitelist"] / ["Lead"] -> ListPanel
local make = Widgets.Make
local checkbox = Widgets.SettingCheckbox

local function cycle(current, values)
    for i, value in ipairs(values) do
        if value == current then return values[i % #values + 1] end
    end
    return values[1]
end

-- Button that cycles through values and stores the result in a setting.
local function cycleButton(parent, id, x, y, width, key, values)
    local button = make("button", id, parent, x, y, width, 22, string.upper(settings.Get(key)))
    button:SetHandler("OnClick", function()
        local nextValue = cycle(settings.Get(key), values)
        settings.Update(key, nextValue)
        button:SetText(string.upper(nextValue))
    end)
    return button
end

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

-- "<Kind> mode:  [PUBLIC]" for one invite. One button cycles Public / Private / Disabled and
-- picks which shared list that invite uses; Disabled means the list is not applied.
local function buildModeRow(parent, index, kind, x, y)
    local id = "p" .. index .. "_" .. kind:lower() .. "_mode"
    make("label", id .. "_label", parent, x, y + 2, 100, 22, kind .. " mode:")
    cycleButton(parent, id, x + 100, y, 130, "Invite" .. index .. kind .. "Mode", constants.listModes)
end

-- Own window with the parchment background. Invite 1 hangs off the top-left edge of the raid
-- window; Invite 2 (given `previous`, the Invite 1 window) sits directly below it, so it moves
-- up and down as Invite 1 collapses or expands. Being children of `root` they show and hide
-- with the raid window.
-- The header (title + Enabled checkbox) is always visible. The rest lives in `body`, which is
-- hidden, along with the extra window height, while the invite is not enabled.
local function createInviteWindow(root, index, previous)
    local dims = constants.invitePanel
    local x = 10
    local key = "Invite" .. index
    local id = "p" .. index
    local bodyHeight = dims.height - dims.headerHeight

    local window = make("emptywidget", "invite" .. index, root, 0, 0, dims.width, dims.height)
    window:RemoveAllAnchors()
    if previous == nil then
        window:AddAnchor("TOPRIGHT", root, "TOPLEFT", -dims.gap, 0)
    else
        window:AddAnchor("TOPLEFT", previous, "BOTTOMLEFT", 0, dims.gap)
    end
    local background = Widgets.AddBackground(window, id .. "_bg", constants.folderPath .. "images/background.png", dims.width, dims.height)

    -- body: everything below the header (y values below are relative to the body)
    local body = make("emptywidget", id .. "_body", window, 0, dims.headerHeight, dims.width, bodyHeight)
    caption(body, id .. "_cap_keyword", x, 8, "Keyword")
    caption(body, id .. "_cap_channel", x + 95, 8, "Channel")
    caption(body, id .. "_cap_match", x + 190, 8, "Matching type")
    textBox(body, id .. "_keyword", x, 28, 90, key .. "Phrase")
    cycleButton(body, id .. "_channel", x + 95, 28, 90, key .. "Channel", constants.channelOrder)
    cycleButton(body, id .. "_match", x + 190, 28, 90, key .. "Match", constants.matches)
    buildModeRow(body, index, "Blacklist", x, 62)
    buildModeRow(body, index, "Whitelist", x, 92)

    local function applyEnabled(enabled)
        local height = enabled and dims.height or dims.headerHeight
        window:SetExtent(dims.width, height)
        background:SetExtent(dims.width, height)
        body:Show(enabled)
    end

    -- header: title, and the Enabled checkbox in the top right corner with its label to the left
    make("label", id .. "_title", window, x, 8, 150, 22, "INVITE " .. index)
    local boxX = dims.width - x - 25
    make("label", id .. "_enabled_label", window, boxX - 62, 10, 56, 22, "Enabled")
    Widgets.Checkbox(id .. "_enabled", window, nil, boxX, 6, settings.Get(key .. "Enabled"), function(checked)
        settings.Update(key .. "Enabled", checked)
        applyEnabled(checked)
    end)
    applyEnabled(settings.Get(key .. "Enabled"))
    return window
end

-- Left section: one button per shared list. The editor it opens has a PUBLIC / PRIVATE toggle
-- at the top to pick which of the two lists is edited.
local function buildListSection(x, y)
    make("label", "lists_title", panel, x, y, 200, 22, "NAME LISTS")
    local col = 0
    for _, kind in ipairs({"Blacklist", "Whitelist"}) do
        local button = make("button", "edit_" .. kind:lower(), panel, x + col * 142, y + 28, 136, 24, string.upper(kind))
        button:SetHandler("OnClick", function()
            panel:Show(false)
            editors[kind].Open()
        end)
        col = col + 1
    end
    make("label", "lists_hint", panel, x, y + 60, 280, 18, "Click a list to add or remove names")
end

-- Right section: lead pass (hand raid lead to whoever says the keyword).
local function buildLeadSection(x, y, width)
    make("label", "lead_title", panel, x, y, 150, 22, "LEAD PASS")
    local boxX = x + width - 25
    make("label", "lead_enabled_label", panel, boxX - 62, y + 2, 56, 22, "Enabled")
    checkbox("lead_enable", panel, nil, boxX, y - 2, "LeadEnabled")

    caption(panel, "lead_cap_keyword", x, y + 28, "Keyword")
    caption(panel, "lead_cap_channel", x + 95, y + 28, "Channel")
    textBox(panel, "lead_phrase", x, y + 48, 90, "LeadPhrase")
    cycleButton(panel, "lead_channel", x + 95, y + 48, 90, "LeadChannel", constants.leadChannelOrder)

    -- text-less checkbox (restrict lead pass to the list) with the list button right next to it
    checkbox("lead_allow", panel, nil, x, y + 76, "LeadWhitelistEnabled")
    local edit = make("button", "lead_edit", panel, x + 33, y + 78, 140, 24, "LEAD PASS LIST")
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
    -- own window below the raid window; the raid window itself is not resized or modified
    panel = make("emptywidget", "panel", root, 0, 0, dims.width, dims.mainHeight)
    Widgets.AnchorBelow(panel, root, dims.gap)
    Widgets.AddBackground(panel, "bg", constants.folderPath .. "images/background.png", dims.width, dims.mainHeight)

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
        hint = "When the checkbox next to LEAD PASS LIST is ticked, only these players can take lead.",
    })

    inviteWindows[1] = createInviteWindow(root, 1)
    inviteWindows[2] = createInviteWindow(root, 2, inviteWindows[1])
    sortWindow = SortWindow.Create(root) -- right side of the raid window

    -- header bar (debug logging is toggled by whispering "/debug" to yourself, see raidtools.lua)
    make("label", "heading", panel, 10, 8, 300, 24, "TnT RAID TOOLS")
    Widgets.Divider(panel, "divider_header", 10, 36, dims.width - 20, 2)

    local half = dims.width / 2
    buildListSection(10, 48)
    Widgets.Divider(panel, "divider_columns", half - 1, 48, 2, dims.mainHeight - 60)
    buildLeadSection(half + 10, 48, half - 20)
end

function Panel.Show()
    if panel then panel:Show(true) end
end

function Panel.OnUnload()
    Widgets.FreeAll()
    panel = nil
    inviteWindows = {}
    sortWindow = nil
    editors = {}
end

return Panel
