local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")

local Widgets = {}
local idPrefix = "tnt_raid_tools"
local textEvents = {"OnChanged", "OnTextChanged", "OnFocusLost", "OnEnterPressed"}
local created = {}

Widgets.textEvents = textEvents

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
function Widgets.AddBackground(widget, id, texture, width, height)
    local bg = widget:CreateImageDrawable(idPrefix .. "_" .. id, "background")
    bg:SetTexture(texture)
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
    local sound = "auction_put_up"
    local texChecked = constants.folderPath .. "images/checkbox_checked.png"
    local texUnchecked = constants.folderPath .. "images/checkbox_unchecked.png"
    local fullId = idPrefix .. "_" .. id
    local box = {checked = checked == true}

    local overlay = parent:CreateImageDrawable(fullId .. "_box", "artwork")
    overlay:AddAnchor("TOPLEFT", parent, x, y)
    overlay:SetExtent(size, size)
    overlay:Show(true)

    local button = parent:CreateChildWidget("button", fullId .. "_btn", 0, true)
    button:AddAnchor("TOPLEFT", parent, x, y)
    button:SetExtent(size, size)
    if button.SetSounds then button:SetSounds(sound) end
    button:Show(true)
    button:Enable(true)
    created[#created + 1] = button

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
        labelButton = parent:CreateChildWidget("button", fullId .. "_textbtn", 0, true)
        labelButton:AddAnchor("TOPLEFT", button, size + textGap, 0)
        labelButton:SetExtent(textWidth, textHeight)
        if labelButton.SetSounds then labelButton:SetSounds(sound) end
        labelButton:Show(true)
        labelButton:Enable(true)
        created[#created + 1] = labelButton
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
    local button = parent:CreateChildWidget("button", idPrefix .. "_" .. id, 0, true)
    button:AddAnchor("TOPLEFT", parent, x, y)
    button:SetExtent(width, height)
    if button.SetSounds then button:SetSounds("auction_put_up") end
    button:Show(true)
    button:Enable(true)
    created[#created + 1] = button
    button:SetHandler("OnClick", onClick)
    button:Raise()
    return button
end

-- Clickable picture: an image drawable with a transparent button on top (same trick as the checkbox).
-- `texture` is a file name inside the images folder, e.g. "add.png". Returns {SetTexture(name), Show(visible)}.
function Widgets.IconButton(id, parent, texture, x, y, size, onClick)
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

    local button = holder:CreateChildWidget("button", fullId .. "_btn", 0, true)
    button:AddAnchor("TOPLEFT", holder, 0, 0)
    button:SetExtent(size, size)
    if button.SetSounds then button:SetSounds("auction_put_up") end
    button:Show(true)
    button:Enable(true)
    created[#created + 1] = button
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

-- Checkbox bound to a boolean setting.
function Widgets.SettingCheckbox(id, parent, text, x, y, key)
    return Widgets.Checkbox(id, parent, text, x, y, settings.Get(key), function(checked)
        settings.Update(key, checked)
    end)
end

-- Free every widget made through Make(), newest first.
function Widgets.FreeAll()
    for i = #created, 1, -1 do
        local w = created[i]
        w:ReleaseHandler("OnClick")
        pcall(function() w:ReleaseHandler("OnWheelUp") end)
        pcall(function() w:ReleaseHandler("OnWheelDown") end)
        for _, event in ipairs(textEvents) do
            w:ReleaseHandler(event)
        end
        w:Show(false)
        api.Interface:Free(w)
        created[i] = nil
    end
end

return Widgets
