local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")

local Widgets = {}
local idPrefix = "tnt_raid_tools"
local textEvents = {"OnChanged", "OnTextChanged", "OnFocusLost", "OnEnterPressed"}
local created = {}
local combos = {} -- combo boxes: freed separately, they may lack some of the handler calls FreeAll makes

Widgets.textEvents = textEvents

-- Click sound of the icon buttons, checkboxes and click areas.
local function useButtonSound(button)
    if button.SetSounds then button:SetSounds(constants.buttonSound) end
end

-- Transparent-or-skinned child button at (x, y) of `anchorTo` inside `parent`, with the click sound
-- (quiet = true: none, the caller plays its own). Freed by FreeAll.
local function makeButton(parent, fullId, anchorTo, x, y, width, height, quiet)
    local button = parent:CreateChildWidget("button", fullId, 0, true)
    button:AddAnchor("TOPLEFT", anchorTo, x, y)
    button:SetExtent(width, height)
    if quiet then
        pcall(function() button:SetSounds("") end)
    else
        useButtonSound(button)
    end
    button:Show(true)
    button:Enable(true)
    created[#created + 1] = button
    return button
end

-- A sound player, done the way WorldSatNav plays its stacked alert sound (helpers/sound.lua): addons
-- get no "play this sound" call, only SetSounds themes, and a window plays its theme when the engine
-- opens it. So a player is a hidden 1x1 window carrying the key. Play silences it while it is hidden
-- (no close sound, and re-showing with the same key fires the open sound again), sets the key and
-- opens it. Make one player per sound that has to overlap with another; Play on two of them in the
-- same call stacks the sounds.
-- Returns {Play(key)}; Play returns true when the window was opened with the key, else false and the
-- reason (the game does not say whether the key was a real theme).
function Widgets.SoundPlayer(id)
    local player = {}
    local fullId = idPrefix .. "_" .. id
    local ok, w = pcall(function() return api.Interface:CreateEmptyWindow(fullId) end)
    if not ok or w == nil then
        function player.Play() return false, "could not create a sound window: " .. tostring(w) end
        return player
    end
    created[#created + 1] = w
    pcall(function()
        w:AddAnchor("TOPLEFT", "UIParent", 0, 0)
        w:SetExtent(1, 1)
        w:SetCloseOnEscape(false)
        w:Show(false)
    end)
    function player.Play(key)
        if key == nil or key == "" then return false, "silent key" end
        if w.SetSounds == nil then return false, "window has no SetSounds" end
        local done, err = pcall(function()
            w:SetSounds("")
            if w:IsVisible() then w:Show(false) end
            w:SetSounds(key)
            w:Show(true)
        end)
        if not done then return false, tostring(err) end
        return true
    end
    return player
end

function Widgets.Make(kind, id, parent, x, y, width, height, text)
    local fullId = idPrefix .. "_" .. id
    local w
    if kind == "textbox" then
        w = W_CTRL.CreateEdit(fullId, parent)
        ApplyTextColor(w, FONT_COLOR.BLACK)
        w:SetCursorColor(0, 0, 0, 1)
    else
        w = parent:CreateChildWidget(kind, fullId, 0, true)
    end
    created[#created + 1] = w
    if kind == "label" then
        w.style:SetColor(FONT_COLOR.BLACK[1], FONT_COLOR.BLACK[2], FONT_COLOR.BLACK[3], 1)
        w.style:SetAlign(ALIGN.LEFT)
        w.style:SetFontSize(14)
    elseif kind == "button" then
        api.Interface:ApplyButtonSkin(w, BUTTON_BASIC.DEFAULT)
    end
    w:SetExtent(width, height)
    w:AddAnchor("TOPLEFT", parent, x, y)
    if text then w:SetText(text) end
    w:Show(true)
    return w
end

-- Parchment background drawable filling a widget.
function Widgets.AddBackground(widget, id, width, height)
    local bg = widget:CreateImageDrawable(idPrefix .. "_" .. id, "background")
    bg:SetTexture(constants.folderPath .. "images/background.png")
    bg:SetExtent(width, height)
    bg:AddAnchor("TOPLEFT", widget, 0, 0)
    bg:Show(true)
    return bg
end

-- Hang `window` directly below `target` (left edges aligned, `gap` pixels apart).
function Widgets.AnchorBelow(window, target, gap)
    window:RemoveAllAnchors()
    window:AddAnchor("TOPLEFT", target, "BOTTOMLEFT", 0, gap)
end

-- Thin solid line (divider). Colour matches the parchment border.
function Widgets.Divider(parent, id, x, y, width, height)
    local line = parent:CreateColorDrawable(0.45, 0.36, 0.16, 0.8, "artwork")
    line:AddAnchor("TOPLEFT", parent, x, y)
    line:SetExtent(width, height)
    line:Show(true)
    return line
end

-- Checkbox ported from WorldSatNav: image drawable for the box, transparent buttons
-- on top of the box and label for clicks. Returns {SetChecked, IsChecked}.
-- onChange(checked) fires on user clicks only. text may be nil/"" for a box with no label.
function Widgets.Checkbox(id, parent, text, x, y, checked, onChange)
    local size = 25
    local textGap = 6 -- space between the box and its text
    local texChecked = constants.folderPath .. "images/checkbox_checked.png"
    local texUnchecked = constants.folderPath .. "images/checkbox_unchecked.png"
    local fullId = idPrefix .. "_" .. id
    local box = {checked = checked == true}

    local overlay = parent:CreateImageDrawable(fullId .. "_box", "artwork")
    overlay:AddAnchor("TOPLEFT", parent, x, y)
    overlay:SetExtent(size, size)
    overlay:Show(true)

    local button = makeButton(parent, fullId .. "_btn", parent, x, y, size, size)

    -- text is optional: with none, only the box is drawn and clicked
    local labelButton
    if text ~= nil and text ~= "" then
        local label = api.Interface:CreateWidget("label", fullId .. "_text", parent)
        label:SetExtent(200, 30)
        label:AddAnchor("TOPLEFT", button, size + textGap, 0)
        label:SetText(text)
        label.style:SetAlign(ALIGN.LEFT)
        label.style:SetFontSize(14)
        label.style:SetColor(0, 0, 0, 1)
        -- GetTextWidth/GetTextHeight are not on every label; fall back to an estimate for size 14 text
        local textWidth = label.GetTextWidth and (label:GetTextWidth() + 4) or (#text * 8 + 4)
        local textHeight = label.GetTextHeight and (label:GetTextHeight() + 4) or 22
        label:SetExtent(textWidth, textHeight)
        label:Show(true)
        created[#created + 1] = label

        -- transparent proxy over the text so clicking it also toggles (and plays the click sound)
        labelButton = makeButton(parent, fullId .. "_textbtn", button, size + textGap, 0, textWidth, textHeight)
    end

    local function render()
        overlay:SetTexture(box.checked and texChecked or texUnchecked)
    end
    render()

    local function onClick()
        box.checked = not box.checked
        render()
        if onChange then onChange(box.checked) end
    end
    button:SetHandler("OnClick", onClick)
    if labelButton then labelButton:SetHandler("OnClick", onClick) end
    button:Raise()
    if labelButton then labelButton:Raise() end

    function box.SetChecked(value)
        box.checked = value == true
        render()
    end
    function box.IsChecked() return box.checked end
    return box
end

-- Dark overlay with centred lines of text, drawn over `parent`. Returns
-- {SetLines({text, ...}), Show(visible), Raise()}; at most maxLines lines. Hidden until Show(true).
function Widgets.Overlay(id, parent, width, height, maxLines)
    local overlay = Widgets.Make("emptywidget", id, parent, 0, 0, width, height)
    local shade = overlay:CreateColorDrawable(0.1, 0.07, 0.03, 0.93, "artwork")
    shade:AddAnchor("TOPLEFT", overlay, 0, 0)
    shade:SetExtent(width, height)
    shade:Show(true)
    local labels = {}
    for i = 1, maxLines do
        local label = Widgets.Make("label", id .. "_text" .. i, overlay, 10, 0, width - 20, 22, "")
        label.style:SetColor(1, 0.95, 0.8, 1)
        pcall(function() label.style:SetAlign(ALIGN.CENTER) end)
        labels[i] = label
    end
    pcall(function() overlay:EnablePick(true) end) -- swallow clicks so what is underneath is inert

    local self = {}
    function self.SetLines(lines)
        local top = height / 2 - (#lines * 24) / 2
        for i, label in ipairs(labels) do
            local text = lines[i]
            label:Show(text ~= nil)
            if text ~= nil then
                label:SetText(text)
                label:RemoveAllAnchors()
                label:AddAnchor("TOPLEFT", overlay, 10, top + (i - 1) * 24)
            end
        end
    end
    function self.Show(visible)
        overlay:Show(visible)
        if visible then overlay:Raise() end
    end
    function self.Raise() overlay:Raise() end
    overlay:Show(false)
    return self
end

-- Invisible button over an area (a label that should react to clicks). Returns the button.
function Widgets.ClickArea(id, parent, x, y, width, height, onClick)
    local button = makeButton(parent, idPrefix .. "_" .. id, parent, x, y, width, height)
    button:SetHandler("OnClick", onClick)
    button:Raise()
    return button
end

-- Clickable picture: an image drawable with a transparent button on top (same trick as the checkbox).
-- `texture` is a file name inside the images folder, e.g. "add.png". Returns {SetTexture(name), Show(visible)}.
-- quiet = true: the button makes no click sound of its own (the click plays its own sounds instead).
function Widgets.IconButton(id, parent, texture, x, y, size, onClick, quiet)
    local fullId = idPrefix .. "_" .. id
    local icon = {}
    -- the picture and the button live in a small holder widget, so hiding the icon is one Show() on a
    -- widget (hiding a bare drawable or a button on someone else's window is not reliable)
    local holder = parent:CreateChildWidget("emptywidget", fullId .. "_holder", 0, true)
    holder:AddAnchor("TOPLEFT", parent, x, y)
    holder:SetExtent(size, size)
    holder:Show(true)
    created[#created + 1] = holder

    local picture = holder:CreateImageDrawable(fullId .. "_img", "artwork")
    picture:AddAnchor("TOPLEFT", holder, 0, 0)
    picture:SetExtent(size, size)
    picture:SetTexture(constants.folderPath .. "images/" .. texture)
    picture:Show(true)

    local button = makeButton(holder, fullId .. "_btn", holder, 0, 0, size, size, quiet)
    button:SetHandler("OnClick", onClick)
    button:Raise()
    holder:Raise() -- above whatever else the parent already holds

    function icon.SetTexture(name)
        picture:SetTexture(constants.folderPath .. "images/" .. name)
    end
    function icon.Show(visible)
        holder:Show(visible)
    end
    return icon
end

-- The value after `current` in `values` (wrapping around); the first one when current is not listed.
function Widgets.Cycle(current, values)
    for i, value in ipairs(values) do
        if value == current then return values[i % #values + 1] end
    end
    return values[1]
end

-- Button that cycles through `values` on every click, showing the current one in capitals.
-- get() returns the current value (nil shows no text), set(value) stores the new one.
function Widgets.CycleButton(parent, id, x, y, width, values, get, set)
    local current = get()
    local button = Widgets.Make("button", id, parent, x, y, width, 22, current and string.upper(current) or "")
    button:SetHandler("OnClick", function()
        local nextValue = Widgets.Cycle(get(), values)
        set(nextValue)
        button:SetText(string.upper(nextValue))
    end)
    return button
end

-- Cycle button bound to a setting.
function Widgets.SettingCycleButton(parent, id, x, y, width, key, values)
    return Widgets.CycleButton(parent, id, x, y, width, values,
        function() return settings.Get(key) end,
        function(value) settings.Update(key, value) end)
end

-- Checkbox bound to a boolean setting.
function Widgets.SettingCheckbox(id, parent, text, x, y, key)
    return Widgets.Checkbox(id, parent, text, x, y, settings.Get(key), function(checked)
        settings.Update(key, checked)
    end)
end

-- Dropdown (game combo box, same call as the automatic_raid_roles addon) bound to a setting.
-- `values` are the stored setting values (in order), `labels` the texts shown for them.
-- onChange(value) fires after the setting is saved.
function Widgets.SettingDropdown(parent, x, y, width, key, values, labels, onChange)
    local combo = W_CTRL.CreateComboBox(parent)
    combo:AddAnchor("TOPLEFT", parent, x, y)
    combo:SetExtent(width, 24)
    combo.dropdownItem = labels
    local current = settings.Get(key)
    for i, value in ipairs(values) do
        if value == current then combo:Select(i) end
    end
    function combo:SelectedProc()
        local value = values[self:GetSelectedIndex()]
        if value == nil then return end
        settings.Update(key, value)
        if onChange then onChange(value) end
    end
    combos[#combos + 1] = combo
    return combo
end

-- Two sounds at once (keyA on one player, keyB on another, started in the same call).
-- `keys` is {keyA, keyB}. Returns whether each one was started.
local stackPlayers
function Widgets.PlayStacked(keys)
    if stackPlayers == nil then
        stackPlayers = {Widgets.SoundPlayer("stack1"), Widgets.SoundPlayer("stack2")}
    end
    local a = stackPlayers[1].Play(keys[1])
    local b = stackPlayers[2].Play(keys[2])
    return a, b
end

-- Free every widget made through Make(), newest first.
function Widgets.FreeAll()
    stackPlayers = nil -- their windows are in `created` and freed below
    for i = #combos, 1, -1 do
        local combo = combos[i]
        combo.SelectedProc = nil
        pcall(function() combo:Show(false) end)
        pcall(function() api.Interface:Free(combo) end)
        combos[i] = nil
    end
    for i = #created, 1, -1 do
        local w = created[i]
        w:ReleaseHandler("OnClick")
        pcall(function() w:ReleaseHandler("OnWheelUp") end)
        pcall(function() w:ReleaseHandler("OnWheelDown") end)
        for _, event in ipairs(textEvents) do
            w:ReleaseHandler(event)
        end
        pcall(function() w:SetSounds("") end) -- no close sound while being freed (sound windows stay open)
        w:Show(false)
        api.Interface:Free(w)
        created[i] = nil
    end
end

return Widgets
