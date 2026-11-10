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
    local lines = {
        "Tanks:  groups " .. groupList(sort.tankGroups),
        "Healers:  groups " .. groupList(sort.healerGroups),
        "Others:  groups " .. groupList(sort.otherGroups),
        "Others: " .. table.concat(sort.otherSkillsetOrder, ", "),
        "Each sorted by gear score, highest first",
        "Re-checked every " .. math.floor(sort.recheckMs / 1000) .. "s and on join/leave",
    }
    for i, text in ipairs(lines) do
        Widgets.Make("label", "sort_line" .. i, body, x, 6 + (i - 1) * 22, dims.width - 2 * x, 20, text)
    end

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
