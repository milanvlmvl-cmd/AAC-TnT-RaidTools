local Matching = require("AAC-TnT-RaidTools/core/matching")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")

-- Add/remove editor for a name array setting (used for the blacklist and whitelist).
local ListPanel = {}

local ROWS_PER_PAGE = 8
local ROW_HEIGHT = 28
local ROWS_Y = 108 -- first name row

-- opts: id (widget id prefix), title, hint, onClose, and either
--   settingKey                       a single list, or
--   keys = {public = k1, private = k2}   two lists, with a PUBLIC / PRIVATE toggle at the top.
-- hint is a string, or a function(mode) returning the description for the list being edited.
-- With `keys` the title reads "<title>  -  PUBLIC RAIDS" and follows the toggle.
-- Open() shows the editor.
function ListPanel.Create(parent, opts)
    local self = {}
    local dims = constants.panel
    local id = opts.id
    local mode = "public" -- which of opts.keys is being edited (remembered between opens)
    local page = 1
    local rows = {}

    local window = Widgets.Make("emptywidget", id, parent, 0, 0, dims.width, dims.editorHeight)
    Widgets.AnchorBelow(window, parent, dims.gap)
    Widgets.AddBackground(window, id .. "_bg", dims.width, dims.editorHeight)
    window:Show(false)

    local function currentKey()
        if opts.keys then return opts.keys[mode] end
        return opts.settingKey
    end
    local function entries() return settings.GetList(currentKey()) end
    local function pageCount(list) return math.max(1, math.ceil(#list / ROWS_PER_PAGE)) end

    local title = Widgets.Make("label", id .. "_title", window, 10, 8, 330, 24, opts.title)
    local close = Widgets.Make("button", id .. "_close", window, 490, 8, 100, 22, "BACK")
    local modeButton
    if opts.keys then
        modeButton = Widgets.Make("button", id .. "_mode", window, 340, 8, 140, 22)
    end
    -- what the list being edited is for (follows the toggle)
    local hint = Widgets.Make("label", id .. "_hint", window, 10, 36, 580, 18)
    local input = Widgets.Make("textbox", id .. "_input", window, 10, 62, 400, 22)
    local add = Widgets.Make("button", id .. "_add", window, 420, 62, 100, 22, "ADD")
    Widgets.Make("label", id .. "_input_hint", window, 10, 86, 580, 18, "Type a name and press ADD. Separate several names with commas.")
    local footerY = ROWS_Y + ROWS_PER_PAGE * ROW_HEIGHT + 4
    local prev = Widgets.Make("button", id .. "_prev", window, 10, footerY, 80, 22, "PREV")
    local nextPage = Widgets.Make("button", id .. "_next", window, 96, footerY, 80, 22, "NEXT")
    local pageLabel = Widgets.Make("label", id .. "_page", window, 190, footerY, 300, 22)

    local function refresh()
        if modeButton then
            modeButton:SetText(string.upper(mode) .. " RAIDS")
            title:SetText(opts.title .. "  -  " .. string.upper(mode) .. " RAIDS")
        end
        hint:SetText(type(opts.hint) == "function" and opts.hint(mode) or opts.hint)
        local list = entries()
        page = math.min(page, pageCount(list))
        for slot = 1, ROWS_PER_PAGE do
            local name = list[(page - 1) * ROWS_PER_PAGE + slot]
            rows[slot].label:SetText(name or "")
            rows[slot].label:Show(name ~= nil)
            rows[slot].remove:Show(name ~= nil)
        end
        pageLabel:SetText("Page " .. page .. " / " .. pageCount(list) .. "  (" .. #list .. " names)")
    end

    local function addNames()
        local list = entries()
        local seen = Matching.lookup(list)
        local changed = false
        for _, name in ipairs(Matching.splitNames(input:GetText())) do
            local nameKey = Matching.normalizeName(name)
            if not seen[nameKey] then
                list[#list + 1] = name
                seen[nameKey] = true
                changed = true
            end
        end
        if changed then
            settings.Update(currentKey(), list)
            page = pageCount(list) -- jump to the page holding the newest entry
        end
        input:SetText("")
        refresh()
    end

    local function removeAt(slot)
        local list = entries()
        local index = (page - 1) * ROWS_PER_PAGE + slot
        if list[index] == nil then return end
        table.remove(list, index)
        settings.Update(currentKey(), list)
        refresh()
    end

    for slot = 1, ROWS_PER_PAGE do
        local y = ROWS_Y + (slot - 1) * ROW_HEIGHT
        local label = Widgets.Make("label", id .. "_row" .. slot, window, 20, y, 400, 22)
        local remove = Widgets.Make("button", id .. "_remove" .. slot, window, 420, y, 100, 22, "REMOVE")
        remove:SetHandler("OnClick", function() removeAt(slot) end)
        rows[slot] = {label = label, remove = remove}
    end

    add:SetHandler("OnClick", addNames)
    input:SetHandler("OnEnterPressed", addNames)
    prev:SetHandler("OnClick", function()
        page = math.max(1, page - 1)
        refresh()
    end)
    nextPage:SetHandler("OnClick", function()
        page = math.min(pageCount(entries()), page + 1)
        refresh()
    end)

    if modeButton then
        modeButton:SetHandler("OnClick", function()
            mode = mode == "public" and "private" or "public"
            page = 1
            refresh()
        end)
    end

    function self.Open()
        page = 1
        input:SetText("")
        refresh()
        window:Show(true)
        window:Raise()
    end

    function self.Close()
        window:Show(false)
        if opts.onClose then opts.onClose() end
    end
    close:SetHandler("OnClick", self.Close)

    return self
end

return ListPanel
