local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")
local raidsort = require("AAC-TnT-RaidTools/features/raidsort")

-- Raid sort window on the right side of the raid window. Like the invite windows it collapses to
-- a header bar (title + Enabled checkbox) while the feature is off.
local SortWindow = {}

local function groupList(groups)
    local parts = {}
    for _, group in ipairs(groups) do parts[#parts + 1] = tostring(group) end
    return table.concat(parts, ", ")
end

function SortWindow.Create(root)
    local dims = constants.sortPanel
    local sort = constants.raidSort
    local x = 10

    local window = Widgets.Make("emptywidget", "sort", root, 0, 0, dims.width, dims.height)
    window:RemoveAllAnchors()
    window:AddAnchor("TOPLEFT", root, "TOPRIGHT", dims.gap, 0)
    local background = Widgets.AddBackground(window, "sort_bg", constants.folderPath .. "images/background.png", dims.width, dims.height)

    local body = Widgets.Make("emptywidget", "sort_body", window, 0, dims.headerHeight, dims.width, dims.height - dims.headerHeight)
    local recheck = "Re-checked every " .. math.floor(sort.recheckMs / 1000) .. "s and on join/leave"
    local styleLines = {
        [1] = {
            "Tanks:  groups " .. groupList(sort.tankGroups),
            "Healers:  groups " .. groupList(sort.healerGroups),
            "Others:  groups " .. groupList(sort.otherGroups),
            "Others: " .. table.concat(sort.otherSkillsetOrder, ", "),
            "Each sorted by gear score, highest first",
            recheck,
        },
        [2] = {
            "Each group: 1 tank, 3 others, 1 healer",
            "Highest gear score fills the first group",
            "A group with no tank gets an other instead",
            "A short group keeps its healer in the",
            "bottom slot (other players help push)",
            recheck,
        },
    }
    local labels = {}
    for i = 1, 6 do
        labels[i] = Widgets.Make("label", "sort_line" .. i, body, x, 6 + (i - 1) * 22, dims.width - 2 * x, 20, styleLines[1][i])
    end
    local function applyStyle(style)
        for i, label in ipairs(labels) do label:SetText(styleLines[style][i]) end
    end

    -- bottom row: sort style toggle
    local style = settings.Get("RaidSortStyle")
    local styleY = 6 + 6 * 22 + 8
    Widgets.Make("label", "sort_style_label", body, x, styleY + 2, 90, 22, "Sort style:")
    local styleButton = Widgets.Make("button", "sort_style", body, x + 100, styleY, 130, 22, "STYLE " .. style)
    styleButton:SetHandler("OnClick", function()
        style = style % #constants.sortStyles + 1
        styleButton:SetText("STYLE " .. style)
        applyStyle(style)
        raidsort.SetStyle(style)
    end)
    applyStyle(style)

    local function applyEnabled(enabled)
        local height = enabled and dims.height or dims.headerHeight
        window:SetExtent(dims.width, height)
        background:SetExtent(dims.width, height)
        body:Show(enabled)
    end

    Widgets.Make("label", "sort_title", window, x, 8, 150, 22, "RAID SORT")
    local boxX = dims.width - x - 25
    Widgets.Make("label", "sort_enabled_label", window, boxX - 62, 10, 56, 22, "Enabled")
    Widgets.Checkbox("sort_enabled", window, nil, boxX, 6, settings.Get("RaidSortEnabled"), function(checked)
        raidsort.SetEnabled(checked)
        applyEnabled(checked)
    end)
    applyEnabled(settings.Get("RaidSortEnabled"))
    return window
end

return SortWindow
