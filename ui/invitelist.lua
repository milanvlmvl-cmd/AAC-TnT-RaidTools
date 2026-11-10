local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local Widgets = require("AAC-TnT-RaidTools/ui/widgets")
local trace = require("AAC-TnT-RaidTools/core/trace")

-- The invite list: a window on the left of the raid window holding any number of invites as cards.
-- A "+" button in the top left corner of the raid panel adds one. Each card has a header (an icon
-- that collapses / expands it, title, X to delete it) and a body with the keyword, channel,
-- matching type and the blacklist / whitelist modes.
--
-- Only as many cards as fit are built (a small pool that is re-bound to whichever invites are in
-- view), so there is no limit on the number of invites. Scrolling moves one card at a time: the
-- arrows, the mouse wheel, and a bar on the right that shows where you are in the list.
local InviteList = {}

local function cycle(current, values)
    for i, value in ipairs(values) do
        if value == current then return values[i % #values + 1] end
    end
    return values[1]
end

function InviteList.Create(root)
    local dims = constants.invitePanel
    local x = 8
    local cardWidth = dims.width - dims.scrollWidth
    local viewTop = dims.headerHeight
    local viewHeight = dims.height - dims.headerHeight - 6
    local headerH, bodyH, gap = dims.cardHeaderHeight, dims.cardBodyHeight, dims.cardGap

    local window = Widgets.Make("emptywidget", "invites", root, 0, 0, dims.width, dims.height)
    window:RemoveAllAnchors()
    window:AddAnchor("TOPRIGHT", root, "TOPLEFT", -dims.gap, 0)
    Widgets.AddBackground(window, "invites_bg", constants.folderPath .. "images/background.png", dims.width, dims.height)
    Widgets.Make("label", "invites_title", window, 10, 8, 200, 22, "INVITES")
    -- one label per line: the label widget does not wrap text by itself
    local emptyLines = {}
    for i, text in ipairs({"No invites yet.", "Press + in the top left corner", "of the raid panel to add one."}) do
        emptyLines[i] = Widgets.Make("label", "invites_empty" .. i, window, 10, viewTop + 10 + (i - 1) * 20, dims.width - 20, 20, text)
    end

    -- shown over the whole window while the global "Invites enabled" switch is off
    local overlay = Widgets.Overlay("invites_off", window, dims.width, dims.height, 2)
    overlay.SetLines({"INVITES DISABLED", "while Global enable is toggled off"})

    local self = {}
    local first = 1 -- index of the invite shown at the top
    local pool = {} -- cards, re-used for whichever invites are in view
    local layout -- defined below

    local function invites() return settings.Get("Invites") end

    -- Change one field of invite i and save (nothing is written when the value is the same).
    local function setField(i, field, value)
        local list = settings.GetInvites()
        if list[i] == nil or list[i][field] == value then return end
        list[i][field] = value
        settings.SetInvites(list)
    end

    local function cardHeight(invite)
        return headerH + (invite.Collapsed and 0 or bodyH)
    end

    -- The first invite index from which everything after it still fits in the window (the furthest
    -- the list can scroll).
    local function maxFirst()
        local list = invites()
        local used = 0
        local index = #list + 1
        while index > 1 do
            local height = cardHeight(list[index - 1])
            if used > 0 and used + height + gap > viewHeight then break end
            used = used + height + gap
            index = index - 1
        end
        return math.max(index, 1)
    end

    local function buildCard(k)
        local id = "inv" .. k
        local card = {index = 0}
        card.widget = Widgets.Make("emptywidget", id, window, 0, 0, cardWidth, headerH)
        local w = card.widget
        Widgets.Divider(w, id .. "_top", 6, 0, cardWidth - 12, 1)

        -- header: collapse / show icon, title, remove icon
        card.toggle = Widgets.IconButton(id .. "_toggle", w, "collapse.png", x, 5, 25, function()
            local invite = invites()[card.index]
            if invite == nil then return end
            setField(card.index, "Collapsed", not invite.Collapsed)
            layout()
        end)
        -- clicking the Zzz icon or the title switches the invite on / off
        local function toggleActive()
            local invite = invites()[card.index]
            if invite == nil then return end
            setField(card.index, "Active", invite.Active == false)
            layout()
        end
        card.zzz = Widgets.IconButton(id .. "_zzz", w, "zzz_off.png", 38, 5, 25, toggleActive)
        card.title = Widgets.Make("label", id .. "_title", w, 68, 9, 165, 22)
        Widgets.ClickArea(id .. "_title_click", w, 68, 5, 165, 26, toggleActive)
        card.remove = Widgets.IconButton(id .. "_remove", w, "remove.png", cardWidth - 33, 5, 25, function()
            local list = settings.GetInvites()
            if list[card.index] == nil then return end
            table.remove(list, card.index)
            settings.SetInvites(list)
            layout()
        end)

        -- body (hidden while collapsed)
        card.body = Widgets.Make("emptywidget", id .. "_body", w, 0, headerH, cardWidth, bodyH)
        local body = card.body
        Widgets.Make("label", id .. "_cap_keyword", body, x, 4, 84, 18, "Keyword")
        Widgets.Make("label", id .. "_cap_channel", body, x + 88, 4, 84, 18, "Channel")
        Widgets.Make("label", id .. "_cap_match", body, x + 176, 4, 90, 18, "Matching type")
        card.phrase = Widgets.Make("textbox", id .. "_phrase", body, x, 24, 84, 22, "")
        local function savePhrase()
            local text = card.phrase:GetText()
            setField(card.index, "Phrase", text)
            card.title:SetText("INVITE " .. card.index .. (text ~= "" and ("  -  " .. text) or ""))
        end
        for _, event in ipairs(Widgets.textEvents) do card.phrase:SetHandler(event, savePhrase) end

        local function cycleButton(suffix, bx, by, bw, field, values)
            local button = Widgets.Make("button", id .. suffix, body, bx, by, bw, 22, "")
            button:SetHandler("OnClick", function()
                local current = (invites()[card.index] or {})[field]
                local nextValue = cycle(current, values)
                setField(card.index, field, nextValue)
                button:SetText(string.upper(nextValue))
            end)
            return button
        end
        card.channel = cycleButton("_channel", x + 88, 24, 84, "Channel", constants.channelOrder)
        card.match = cycleButton("_match", x + 176, 24, 84, "Match", constants.matches)
        Widgets.Make("label", id .. "_blacklist_label", body, x, 60, 100, 22, "Blacklist mode:")
        card.blacklist = cycleButton("_blacklist", x + 100, 58, 130, "BlacklistMode", constants.listModes)
        Widgets.Make("label", id .. "_whitelist_label", body, x, 90, 100, 22, "Whitelist mode:")
        card.whitelist = cycleButton("_whitelist", x + 100, 88, 130, "WhitelistMode", constants.listModes)
        return card
    end

    -- Show invite i on a card.
    local function bind(card, i, invite)
        card.index = i -- first, so anything the widgets fire while being filled goes to the right invite
        card.toggle.SetTexture(invite.Collapsed and "expand.png" or "collapse.png") -- the icon shows what a click does
        local phrase = invite.Phrase
        card.title:SetText("INVITE " .. i .. (phrase ~= "" and ("  -  " .. phrase) or ""))
        -- a switched off invite: bright Zzz and a greyed title; an active one: faded Zzz and a normal title
        local active = invite.Active ~= false
        card.zzz.SetTexture(active and "zzz_off.png" or "zzz.png")
        if active then card.title.style:SetColor(0, 0, 0, 1) else card.title.style:SetColor(0.45, 0.4, 0.32, 1) end
        card.phrase:SetText(phrase)
        card.channel:SetText(string.upper(invite.Channel))
        card.match:SetText(string.upper(invite.Match))
        card.blacklist:SetText(string.upper(invite.BlacklistMode))
        card.whitelist:SetText(string.upper(invite.WhitelistMode))
        card.body:Show(not invite.Collapsed)
    end

    -- ---- scroll bar: arrows, and a thumb showing the position -------------------------------
    local barX = dims.width - dims.scrollWidth + 1
    local arrow = dims.scrollWidth - 2
    local trackTop = viewTop + arrow + 2
    local trackHeight = viewHeight - 2 * (arrow + 2)
    local up, down -- arrow icons, created below once scrollBy exists
    Widgets.Divider(window, "invites_track", barX + arrow / 2 - 1, trackTop, 2, trackHeight)
    local thumbWidth = 8
    local thumbX = barX + (arrow - thumbWidth) / 2
    local thumb = Widgets.Make("emptywidget", "invites_thumb", window, thumbX, trackTop, thumbWidth, 20)
    local thumbFill = thumb:CreateColorDrawable(0.45, 0.36, 0.16, 0.9, "artwork")
    thumbFill:AddAnchor("TOPLEFT", thumb, 0, 0)

    local function updateBar(visible)
        local total, top = #invites(), maxFirst()
        local scrollable = top > 1
        up.Show(scrollable)
        down.Show(scrollable)
        thumb:Show(scrollable)
        if not scrollable then return end
        local height = math.max(14, math.floor(trackHeight * visible / math.max(total, 1)))
        local travel = trackHeight - height
        local y = trackTop + math.floor(travel * (first - 1) / math.max(top - 1, 1))
        thumb:SetExtent(thumbWidth, height)
        thumbFill:SetExtent(thumbWidth, height)
        thumb:RemoveAllAnchors()
        thumb:AddAnchor("TOPLEFT", window, thumbX, y)
    end

    -- Place the cards that fit, from invite `first` down; hide the rest of the pool.
    layout = function()
        local list = invites()
        first = math.min(math.max(first, 1), maxFirst())
        for _, line in ipairs(emptyLines) do line:Show(#list == 0) end
        local y, used = 0, 0
        for i = first, #list do
            local invite = list[i]
            local height = cardHeight(invite)
            if used > 0 and y + height > viewHeight then break end
            used = used + 1
            if pool[used] == nil then pool[used] = buildCard(used) end
            local card = pool[used]
            bind(card, i, invite)
            card.widget:SetExtent(cardWidth, height)
            card.widget:RemoveAllAnchors()
            card.widget:AddAnchor("TOPLEFT", window, 0, viewTop + y)
            card.widget:Show(true)
            y = y + height + gap
        end
        for k = used + 1, #pool do pool[k].widget:Show(false) end
        updateBar(used)
        if not settings.Get("InvitesEnabled") then overlay.Raise() end -- cards made later must not end up above it
    end

    local function scrollBy(step)
        first = first + step
        layout()
    end
    up = Widgets.IconButton("invites_up", window, "scroll_up.png", barX, viewTop, arrow, function() scrollBy(-1) end)
    down = Widgets.IconButton("invites_down", window, "scroll_down.png", barX, viewTop + viewHeight - arrow, arrow, function() scrollBy(1) end)
    -- mouse wheel over the window (not every widget type receives wheel events, so this is best effort)
    pcall(function() window:SetHandler("OnWheelUp", function() scrollBy(-1) end) end)
    pcall(function() window:SetHandler("OnWheelDown", function() scrollBy(1) end) end)

    -- "+" in the top left corner of the raid panel
    local addButton = Widgets.IconButton("invite_add", root, "add.png", 6, 6, 26, function()
        local list = settings.GetInvites()
        list[#list + 1] = settings.NewInvite()
        settings.SetInvites(list)
        trace.Add("[invites] + pressed, now " .. #list .. " invites")
        first = math.huge -- clamped to the end, so the new invite is in view
        layout()
    end)

    -- Called when the global switch changes (and once at the start).
    function self.SetGlobalEnabled(enabled)
        overlay.Show(not enabled)
        trace.Add("[invites] global switch " .. (enabled and "on" or "off") .. ": + button " .. (enabled and "shown" or "hidden"))
        addButton.Show(enabled) -- no adding invites while they are globally disabled
    end
    self.window = window

    layout()
    self.SetGlobalEnabled(settings.Get("InvitesEnabled"))
    return self
end

return InviteList
