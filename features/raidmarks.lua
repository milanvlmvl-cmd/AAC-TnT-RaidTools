-- Raid overhead marks ("signs" 1..12) by player name.
-- stolen from addon "Pickle Police Raid" by "Mazrim",
-- Setting a sign uses one of two routes:
--   1. Direct:   SetOverHeadMarker("teamN", sign) on api.Unit or X2Unit, when the client has it.
--   2. Raid Info menu (fallback): right-click the member's row -> "Sign" -> "Sign N".
-- Reading a sign uses api.Unit:GetOverHeadMarkerUnitId(sign), which is documented in api.lua.
--
-- Every game call goes through the safe helpers below, so a missing or changed client
-- function returns nil / false instead of raising an error.
local api = require("api")
local Matching = require("AAC-TnT-RaidTools/core/matching")

local Marks = {}

-- Fall back to clicking the Raid Info Sign menu when there is no direct setter.
-- Set to false to test the direct setter only.
Marks.UseSignMenu = true

local SIGN_COUNT = 12        -- signs 1..12
local RAID_SIZE = 50         -- raid slots team1..team50
local PARTY_SIZE = 5         -- Raid Info shows the raid as parties of 5 rows
local DELETE_ALL_ROW = 13    -- the Sign submenu ends with "Delete All" after the 12 signs
local MAX_MENU_ROWS = 20     -- how far to look for "Sign" in the right-click menu

-- ---------------------------------------------------------------------------
-- Safe access helpers
-- ---------------------------------------------------------------------------

-- object[name], or nil if that errors.
local function field(object, name)
    local ok, value = pcall(function() return object and object[name] end)
    if ok then return value end
    return nil
end

-- object:method(...) inside pcall. Returns false when the method is missing,
-- otherwise pcall's results (ok, result...).
local function call(object, method, ...)
    local fn = field(object, method)
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end

-- object:method(...) result, or nil when the call is missing or fails.
local function read(object, method, ...)
    local ok, value = call(object, method, ...)
    if ok then return value end
    return nil
end

local function isVisible(widget)
    return read(widget, "IsVisible") == true
end

-- ---------------------------------------------------------------------------
-- Raid members and sign holders
-- ---------------------------------------------------------------------------

-- Unit ids come back as numbers or strings; compare them as strings. 0 / "" mean "nobody".
local function normalizedId(id)
    if type(id) == "string" and id ~= "" then return id end
    if type(id) == "number" and id > 0 then return tostring(id) end
    return nil
end

local function nameKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Matching.normalizeName(name)
end

local function teamUnit(slot)
    return "team" .. slot
end

local function isRaidSlot(slot)
    return slot ~= nil and slot >= 1 and slot <= RAID_SIZE and slot % 1 == 0
end

local function nameKeyAt(slot)
    return nameKey(read(api.Unit, "UnitName", teamUnit(slot)))
end

local function unitId(unit)
    return normalizedId(read(api.Unit, "GetUnitId", unit))
end

-- Raid slot (1..50) of `name`, or nil. Your own slot counts too: Raid Info rows and
-- SetOverHeadMarker work with "teamN", not "player".
local function findSlot(name)
    local wanted = nameKey(name)
    if not wanted then return nil end
    -- fast path: the team API's index, confirmed against the name in that slot
    local slot = tonumber(read(api.Team, "GetMemberIndexByName", name))
    if isRaidSlot(slot) and nameKeyAt(slot) == wanted then return slot end
    -- slow path: scan every slot
    for i = 1, RAID_SIZE do
        if nameKeyAt(i) == wanted then return i end
    end
    return nil
end

-- Unit id currently holding `sign`, or nil when the sign is free.
local function signHolder(sign)
    return normalizedId(read(api.Unit, "GetOverHeadMarkerUnitId", sign))
end

local function isValidSign(sign)
    return sign ~= nil and sign >= 1 and sign <= SIGN_COUNT and sign % 1 == 0
end

-- ---------------------------------------------------------------------------
-- Route 1: direct SetOverHeadMarker
-- ---------------------------------------------------------------------------

-- The table that has SetOverHeadMarker, and its name for logs. Looked up on every
-- call (cheap), so it is never stale.
local function directSetter()
    if type(field(api.Unit, "SetOverHeadMarker")) == "function" then return api.Unit, "api.Unit" end
    ---@diagnostic disable-next-line: undefined-global
    local x2 = X2Unit
    if type(field(x2, "SetOverHeadMarker")) == "function" then return x2, "X2Unit" end
    return nil
end

local function setDirect(setter, setterName, slot, sign)
    local ok, result = call(setter, "SetOverHeadMarker", teamUnit(slot), sign)
    if not ok or result == false then
        return false, setterName .. ":SetOverHeadMarker refused (" .. tostring(result) .. ")."
    end
    return true, "Requested via " .. setterName .. "."
end

-- ---------------------------------------------------------------------------
-- Route 2: Raid Info right-click menu -> Sign -> Sign N
-- ---------------------------------------------------------------------------

-- The Raid Info window. UIC and ADDON are client globals (listed at the top of api.lua).
local function raidInfoWindow()
    ---@diagnostic disable-next-line: undefined-global
    local uic, addon = UIC, ADDON
    local id = field(uic, "RAID_MANAGER")
    return id and read(addon, "GetContent", id)
end

-- The Raid Info row for a raid slot: window.party[p].member[m], plus its name label.
local function raidInfoRow(window, slot)
    local party = field(field(window, "party"), math.ceil(slot / PARTY_SIZE))
    local row = field(field(party, "member"), (slot - 1) % PARTY_SIZE + 1)
    return row, field(row, "nameLabel")
end

-- Menu row text, trimmed ("" when unreadable).
local function caption(button)
    local text = read(button, "GetText")
    if type(text) ~= "string" or #text > 128 then return "" end
    return text:match("^%s*(.-)%s*$")
end

-- The "Sign" entry in an open right-click menu.
local function signEntryIn(menu)
    if not isVisible(menu) then return nil end
    local buttons = field(menu, "buttons")
    for i = 1, MAX_MENU_ROWS do
        local button = field(buttons, i)
        if not button then break end
        if caption(button) == "Sign" then return button end
    end
    return nil
end

-- The right-click menu can hang off the row or off its name label; check both.
local function findSignEntry(row, label)
    return signEntryIn(read(row, "GetAttachedWidget")) or signEntryIn(read(label, "GetAttachedWidget"))
end

-- The submenu that the "Sign" entry opens.
local function signSubmenu(signEntry)
    local child = field(signEntry, "childPopup")
    if isVisible(child) then return child end
    return read(signEntry, "GetAttachedWidget")
end

-- Checks the submenu is exactly "Sign 1".."Sign 12" + "Delete All", so we never click
-- the wrong row, then returns the button for `sign`.
local function signButtonIn(submenu, sign)
    if not isVisible(submenu) then return nil, "Sign submenu closed" end
    local buttons = field(submenu, "buttons")
    for i = 1, SIGN_COUNT do
        local text = caption(field(buttons, i))
        if text ~= "Sign" and text ~= "Sign " .. i and text ~= tostring(i) then
            return nil, "Sign submenu layout differs at row " .. i
        end
    end
    if caption(field(buttons, DELETE_ALL_ROW)) ~= "Delete All" or field(buttons, DELETE_ALL_ROW + 1) ~= nil then
        return nil, "Sign submenu layout end differs"
    end
    return field(buttons, sign)
end

-- Right-click the row. Raid Info puts that action on row.Click; older layouts use eventWindow.OnClick.
local function rightClickRow(row)
    local widget, method = row, "Click"
    if type(field(row, method)) ~= "function" then
        widget, method = field(row, "eventWindow"), "OnClick"
        if type(field(widget, method)) ~= "function" then
            return false, "Raid Info exposes neither row.Click nor eventWindow.OnClick."
        end
    end
    local ok, result = call(widget, method, "RightButton")
    if not ok or result == false then return false, "Raid Info right-click failed." end
    return true
end

-- Hover / click the "Sign" entry so its submenu shows.
local function openSignSubmenu(signEntry)
    if isVisible(signSubmenu(signEntry)) then return true end
    local method = type(field(signEntry, "OnClick")) == "function" and "OnClick" or "OnEnter"
    local ok, result = call(signEntry, method)
    if not ok or result == false then return false, "The Sign submenu could not be opened." end
    return true
end

-- Open row -> right-click menu -> Sign submenu. Returns the open Sign entry.
local function openSignMenu(window, row, label, slot)
    if type(read(window, "IsVisible")) ~= "boolean" then
        return nil, "Raid Info could not be read. Open and close it once, then retry."
    end
    if field(row, "memberIndex") ~= slot or field(row, "target") ~= teamUnit(slot) then
        return nil, "Raid Info row does not match team slot " .. slot .. "."
    end
    if findSignEntry(row, label) then return nil, "Close the open Sign menu and retry." end

    local clicked, why = rightClickRow(row)
    if not clicked then return nil, why end
    local signEntry = findSignEntry(row, label)
    if not signEntry then return nil, "Right-clicking the Raid Info row did not open a Sign menu." end

    local opened, reason = openSignSubmenu(signEntry)
    if not opened then return nil, reason end
    return signEntry
end

-- The button for `sign` in whichever open menu (row's or label's) has a valid Sign submenu.
local function findSignButton(row, label, sign)
    local menus = {read(row, "GetAttachedWidget"), read(label, "GetAttachedWidget")}
    local reason = "Sign menu not found"
    for i = 1, 2 do -- not ipairs: menus[1] may be nil
        local signEntry = signEntryIn(menus[i])
        if signEntry then
            local button
            button, reason = signButtonIn(signSubmenu(signEntry), sign)
            if button then return button end
        end
    end
    return nil, reason
end

local function setViaSignMenu(slot, sign)
    local window = raidInfoWindow()
    local row, label = raidInfoRow(window, slot)
    local signEntry, why = openSignMenu(window, row, label, slot)
    if not signEntry then return false, why end

    local button, reason = findSignButton(row, label, sign)
    local onClick = field(button, "OnClick")
    if type(onClick) ~= "function" then
        return false, button and ("Sign " .. sign .. " action unavailable.") or (tostring(reason) .. ".")
    end
    local ok, result = pcall(onClick, button)
    if not ok or result == false then return false, "Clicking Sign " .. sign .. " failed." end
    return true, "Requested via Raid Info sign menu."
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- Raid slot (1..50) of `name`, or nil when they are not in the raid.
function Marks.Slot(name)
    return findSlot(name)
end

-- true when nobody carries `sign` (1..12) right now.
function Marks.IsFree(sign)
    return signHolder(sign) == nil
end

-- Sign number (1..12) currently on `name`, or nil.
function Marks.Get(name)
    local slot = findSlot(name)
    local id = slot and unitId(teamUnit(slot))
    if not id then return nil end
    for sign = 1, SIGN_COUNT do
        if signHolder(sign) == id then return sign end
    end
    return nil
end

-- Put `sign` (1..12) on `name`. Returns ok, message. You must be raid leader.
-- The server applies it a moment later; confirm with Marks.Get.
-- Applying the sign a unit already carries removes it; that is skipped unless `reapply` is true
-- (Marks.Clear uses it on purpose).
function Marks.Set(name, sign, reapply)
    sign = tonumber(sign)
    if not isValidSign(sign) then return false, "Sign must be 1-12." end
    local slot = findSlot(name)
    if not slot then return false, "Cannot find " .. tostring(name) .. " in the raid." end
    local id = unitId(teamUnit(slot))
    if not id then return false, "Cannot identify " .. tostring(name) .. "." end
    if not reapply and signHolder(sign) == id then return true, "Already has sign " .. sign .. "." end

    local setter, setterName = directSetter()
    if setter then return setDirect(setter, setterName, slot, sign) end
    if not Marks.UseSignMenu then return false, "No SetOverHeadMarker and the sign menu fallback is off." end
    return setViaSignMenu(slot, sign)
end

-- Remove `sign` from `name` by applying it again. Does nothing (returns true) when they no
-- longer carry it, so a late clear never toggles a sign back on.
function Marks.Clear(name, sign)
    if Marks.Get(name) ~= tonumber(sign) then return true, "Does not carry sign " .. tostring(sign) .. "." end
    return Marks.Set(name, sign, true)
end

-- Which route Set will use, for logging.
function Marks.Route()
    local _, setterName = directSetter()
    if setterName then return setterName .. ":SetOverHeadMarker" end
    if not Marks.UseSignMenu then return "none (no SetOverHeadMarker, sign menu fallback off)" end
    if type(read(raidInfoWindow(), "IsVisible")) == "boolean" then return "Raid Info sign menu" end
    return "none (open Raid Info once)"
end

return Marks
