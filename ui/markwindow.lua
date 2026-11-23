local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local MarkControl = require("AAC-TnT-RaidTools/features/markcontrol")

-- Mark control window, hung below the raid sort window. Like the sort window it collapses to a
-- header bar (title + Enabled checkbox) while the feature is off.
local MarkWindow = {}

-- above: the window to hang below (the raid sort window). openEditor(): shows the allowed names editor.
function MarkWindow.Create(root, above, openEditor)
    local dims = constants.markPanel
    local x = 10
    local innerWidth = dims.width - 2 * x

    local window = Widgets.Make("emptywidget", "marks", root, 0, 0, dims.width, dims.height)
    Widgets.AnchorBelow(window, above, dims.gap)
    local background = Widgets.AddBackground(window, "marks_bg", dims.width, dims.height)
    local body = Widgets.Make("emptywidget", "marks_body", window, 0, dims.headerHeight, dims.width, dims.height - dims.headerHeight)

    -- keyword row
    Widgets.Make("label", "marks_cap_keyword", body, x, 6, 70, 18, "Keyword")
    local keyword = Widgets.Make("textbox", "marks_phrase", body, x + 75, 2, 120, 22, settings.Get("MarkPhrase"))

    -- how to use it, follows the keyword
    local hints = {}
    for i = 1, 4 do
        hints[i] = Widgets.Make("label", "marks_hint" .. i, body, x, 30 + (i - 1) * 18, innerWidth, 18, "")
    end
    local function refreshHints()
        local kw = settings.Get("MarkPhrase")
        hints[1]:SetText("Raid chat, within " .. constants.marks.rangeM .. "m:")
        hints[2]:SetText(kw .. " = first free sign,  " .. kw .. " 1-9")
        hints[3]:SetText(kw .. " x  /  " .. kw .. " star  /  " .. kw .. " heart")
        hints[4]:SetText(kw .. " " .. constants.marks.clearWord .. " or same sign again = remove")
    end
    local function saveKeyword()
        settings.Update("MarkPhrase", keyword:GetText())
        refreshHints()
    end
    for _, event in ipairs(Widgets.textEvents) do
        keyword:SetHandler(event, saveKeyword)
    end
    refreshHints()

    -- restrict self marking to the names in its list
    Widgets.Checkbox("marks_allow", body, "Only listed names", x, 106, settings.Get("MarkWhitelistEnabled"), function(checked)
        settings.Update("MarkWhitelistEnabled", checked)
    end)
    local edit = Widgets.Make("button", "marks_edit", body, x + 190, 107, 90, 24, "EDIT LIST")
    edit:SetHandler("OnClick", openEditor)

    -- signs need raid lead; covers the whole window, header included
    local notice = Widgets.Overlay("marks_notice", window, dims.width, dims.height, 2)
    local enabled = settings.Get("MarkEnabled")
    local function refreshNotice()
        local paused = Authority.IsPaused()
        notice.SetLines(paused and {"MARKS PAUSED", "you are not raid lead"} or {})
        notice.Show(enabled and paused)
    end
    Authority.Subscribe(function() refreshNotice() end)

    local function applyEnabled(on)
        enabled = on
        local height = on and dims.height or dims.headerHeight
        window:SetExtent(dims.width, height)
        background:SetExtent(dims.width, height)
        body:Show(on)
        refreshNotice()
    end

    Widgets.Make("label", "marks_title", window, x, 8, 150, 22, "MARK CONTROL")
    local boxX = dims.width - x - 25
    Widgets.Make("label", "marks_enabled_label", window, boxX - 62, 10, 56, 22, "Enabled")
    Widgets.Checkbox("marks_enabled", window, nil, boxX, 6, enabled, function(checked)
        MarkControl.SetEnabled(checked)
        applyEnabled(checked)
    end)
    applyEnabled(enabled)
    return {RefreshNotice = refreshNotice}
end

return MarkWindow
