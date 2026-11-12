local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local settings = require("AAC-TnT-RaidTools/core/settings")
local trace = require("AAC-TnT-RaidTools/core/trace")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Roster = require("AAC-TnT-RaidTools/core/roster")
local SortPlan = require("AAC-TnT-RaidTools/core/sortplan")
local Authority = require("AAC-TnT-RaidTools/core/authority")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")
local Roles = require("AAC-TnT-RaidTools/features/roles")
local PlayerStore = require("AAC-TnT-RaidTools/features/playerstore")
local Debug = require("AAC-TnT-RaidTools/features/raidsort_debug")

-- When enabled, keeps the raid ordered (layout depends on the sort style, see core/sortplan.lua),
-- each group sorted by gear score (highest first). It re-reads the raid every few seconds (a gear
-- score or class is only readable while a member is in range) and soon after someone joins or
-- leaves, then moves one member at a time. Moving onto an occupied slot swaps the two, so each move
-- is confirmed in the roster before the next is planned.
local RaidSort = {}

local cfg = constants.raidSort

local live = false
local timer = 0 -- ms until the next run
local clock = 0 -- ms since load, advanced by Update
local movesThisRun = 0
-- A move is a swap when the target slot is occupied, and the game applies it a moment later.
-- Until the roster shows the member in their new slot the move is "pending": no further move is
-- sent, because planning from the stale layout would repeat it and could undo the swap.
local pending = nil -- {name, from, to, at}
local halted = false -- a move never took effect (and retrying did not help): stop until the roster changes
local queued = nil -- a planned move waiting out cfg.sendDelayMs before it is sent: {name, from, to}
local failedMoves = 0 -- consecutive moves that never showed up in the roster; reset when one does
local loggedRoster = nil -- roster signature last written to the trace (nil: write it again)
local knownNames = nil -- roster signature as of the last join/leave seen

-- last readable value per player name, used while they are out of range
local gearCache, classCache, skillCache = {}, {}, {}

-- Sort trace lines (moves, roster changes, stops) are only written while debug logging is on.
local log = trace.Logger("raidsort")
-- API calls can be missing in this game build or fail for out-of-range units: protected, each
-- distinct failure logged once.
local safe = Guard.New(log)

local function resetRun()
    halted, movesThisRun, pending, failedMoves, queued = false, 0, nil, 0, nil
end

-- Everyone in the raid as {name, slot, unit, class, role, roleSource, color, rank, gs}. A class or gear
-- score that cannot be read (out of range, API failure) falls back to the last readable value for that
-- player (or, with "Save GS+Class", the one saved on disk), and then to class "unknown" (role
-- "other") and a fake gear score equal to the name length (far below any real score, so unknowns sort
-- last in a steady order), so nobody is ever left out of the plan.
local function readRoster()
    local members = {}
    local saveGsClass = settings.Get("RaidSortSaveGsClass")
    Roster.Each(function(slot, unit, name)
        local class = Roles.ReadClass(unit)
        if class ~= nil then classCache[name] = class end
        local gs = Roles.ReadGearScore(unit)
        if gs ~= nil then gearCache[name] = gs end
        if saveGsClass then
            -- still missing after the live read and the in-memory cache: try the player's file once
            if classCache[name] == nil or gearCache[name] == nil then
                local diskClass, diskGs = PlayerStore.Lookup(name)
                if classCache[name] == nil and diskClass ~= nil then classCache[name] = diskClass end
                if gearCache[name] == nil and diskGs ~= nil then gearCache[name] = diskGs end
            end
            PlayerStore.Observe(name, class, gs) -- only real reads count, not cached or disk values
        end
        local knownClass = classCache[name]
        local skillIds = Roles.ReadSkillsetIds(unit)
        if skillIds ~= nil then skillCache[name] = skillIds end
        local role, source = Roles.Decide(knownClass, skillCache[name])
        -- last resort, only when neither class nor skillsets can be read: the role colour the
        -- player picked in the raid window (GetRole's id, mapped by cfg.roleColors)
        local colorId = safe("GetRole", function() return api.Team:GetRole(slot) end)
        if source == "none" and knownClass == nil and skillCache[name] == nil then
            local fromColor = cfg.roleColors[colorId]
            if fromColor ~= nil then role, source = fromColor, "color" end
        end
        members[#members + 1] = {
            name = name, slot = slot, unit = unit,
            class = knownClass or "unknown",
            role = role, roleSource = source, color = colorId,
            rank = Roles.OtherRank(skillCache[name]),
            gs = gearCache[name] or #name, -- unknown: fake a tiny score from the name length, stable across joins/leaves
        }
    end, safe)
    if #members <= 1 then PlayerStore.NewRaid() end -- alone: the raid is over
    return members
end

-- Whether we are in a raid (not a party). IsPartyRaid is missing in this game build, so fall back
-- to IsPartyTeam, and if neither exists assume a raid.
local raidCheckLogged = false
local function inRaid()
    local team = api.Team
    local method, invert
    if type(team.IsPartyRaid) == "function" then method = "IsPartyRaid"
    elseif type(team.IsPartyTeam) == "function" then method, invert = "IsPartyTeam", true end
    if method == nil then
        if not raidCheckLogged then raidCheckLogged = true; log("no IsPartyRaid/IsPartyTeam in this build; assuming raid") end
        return true
    end
    local result = safe(method, function() return team[method](team) end)
    if result == nil then return true end -- could not tell: do not block the sort
    if invert then return not result end
    return result and true or false
end

local function signatureOf(members)
    local names = {}
    for i, m in ipairs(members) do names[i] = m.name end
    return Roster.Join(names)
end

local function describe(m)
    return m.name .. "(" .. m.class .. "/" .. m.role
        .. ((m.roleSource == "skills" or m.roleSource == "color") and ("[" .. m.roleSource .. "]") or "")
        .. " color=" .. tostring(m.color) .. " gs=" .. m.gs .. " slot=" .. m.slot .. ")"
end

-- Confirm or fail the move sent earlier. Returns "waiting" while it may still show up, "halt" when
-- the sort must stop, or nil when there is nothing left to wait for (planning can go on).
local function checkPending(current)
    if pending == nil then return nil end
    if current[pending.to] == pending.name then
        pending = nil -- the swap went through; plan the next move from the new layout
        failedMoves = 0
        return nil
    end
    if clock - pending.at < cfg.moveTimeoutMs then return "waiting" end
    local failed = pending
    pending = nil
    failedMoves = failedMoves + 1
    local text = failed.name .. " did not move from slot " .. failed.from .. " to " .. failed.to
        .. " within " .. cfg.moveTimeoutMs .. "ms"
    if Authority.IsLead() and failedMoves <= cfg.maxRetries then
        -- we do have lead, so the move was lost or the layout changed under us: plan again
        -- from the roster as it is now (the next pass re-reads it)
        log(text .. "; you are lead, rebuilding the plan (retry " .. failedMoves .. "/" .. cfg.maxRetries .. ")")
        return "waiting"
    end
    halted = true
    log("stopping: " .. text .. (Authority.IsLead() and (" (" .. cfg.maxRetries .. " retries failed)") or " (you are not raid lead)"))
    return "halt"
end

-- One pass: read the raid and plan at most one move. Returns "queued" after planning a move (sent by
-- sendQueued), "moved" (debug probe only), "waiting" while the previous move has not shown up in the
-- roster yet, false otherwise.
local function runOnce()
    if not inRaid() then
        PlayerStore.NewRaid()
        return false
    end
    if not Authority.CanManage() then
        -- not raid lead: no sorting, but still scan so "Save GS+Class" keeps recording
        if settings.Get("RaidSortSaveGsClass") then readRoster() end
        return false
    end
    local members = readRoster()
    local signature = signatureOf(members)
    if signature ~= loggedRoster then
        if loggedRoster ~= nil and signature ~= knownNames then
            -- someone joined or left without the team event reaching us: settle first
            knownNames = signature
            loggedRoster = signature
            resetRun()
            timer = cfg.settleMs
            log("roster changed without an event; waiting " .. cfg.settleMs .. "ms to settle")
            return false
        end
        knownNames = signature
        loggedRoster = signature
        resetRun()
        local parts = {}
        for _, m in ipairs(members) do parts[#parts + 1] = describe(m) end
        log("roster changed: " .. table.concat(parts, " "))
    end
    if cfg.dump.enabled then
        Debug.DumpRoster(members)
        return false -- no sorting while dumping
    end
    if halted then return false end

    local current = {}
    for _, m in ipairs(members) do current[m.slot] = m.name end

    local state = checkPending(current)
    if state == "waiting" then return "waiting" end
    if state == "halt" then return false end

    if cfg.probe.enabled then return Debug.RunProbe(current, clock) end

    local desired
    if settings.Get("RaidSortStyle") == constants.sortStyle.party then
        desired = SortPlan.BuildStyle2(members, cfg)
    else
        desired = SortPlan.Build(members, cfg)
    end
    local from, to, why = SortPlan.NextMove(current, desired, cfg.maxMembers, cfg.groupSize)
    if from == nil then
        if movesThisRun > 0 then log("raid sorted after " .. movesThisRun .. " moves") end
        movesThisRun = 0
        return false
    end
    if movesThisRun >= cfg.maxMovesPerRun then
        halted = true
        log("stopping: reached " .. cfg.maxMovesPerRun .. " moves in one run")
        return false
    end

    movesThisRun = movesThisRun + 1
    local mover, displaced = current[from], current[to]
    log("move " .. mover .. " slot " .. from .. " -> " .. to
        .. (displaced and (" (swaps with " .. displaced .. ")") or " (free slot)")
        .. (why and (" [" .. why .. "]") or "") .. " #" .. movesThisRun)
    -- sent after cfg.sendDelayMs, see sendQueued
    queued = {name = mover, from = from, to = to}
    return "queued"
end

-- Sends the move planned by runOnce. It is done when the mover is in the slot we asked for (we only
-- ask for the topmost free slot of a group or an occupied slot, so that is where the game puts them).
local function sendQueued()
    local move = queued
    queued = nil
    pending = {name = move.name, from = move.from, to = move.to, at = clock}
    safe("MoveTeamMember", function() api.Team:MoveTeamMember(move.from, move.to) end)
end

-- Called every frame with the milliseconds since the last one (registered with the Ticker in main.lua).
function RaidSort.Update(dt)
    if not live then return end
    clock = clock + dt
    if not settings.Get("RaidSortEnabled") then return end
    -- The invites switch is the global switch of the addon: while it is off (or you are AFK with
    -- "Disable if afk" ticked) nothing is sorted, and nothing is left half sent for when it comes back.
    if not settings.Get("InvitesEnabled") or AfkWatch.Blocks() then
        queued, pending = nil, nil
        return
    end
    timer = timer - dt
    if timer > 0 then return end
    if queued ~= nil then
        sendQueued()
        timer = cfg.moveDelayMs
        return
    end
    local result = safe("raid sort pass", runOnce)
    if result == "queued" then timer = cfg.sendDelayMs
    elseif result == "moved" then timer = cfg.moveDelayMs
    elseif result == "waiting" then timer = cfg.pollMs
    else timer = cfg.recheckMs end
end

-- Someone joined or left: restart the settle wait (every further join/leave restarts it again) and
-- allow a halted sort to try again. Events that leave the set of names unchanged (the game may
-- also fire this for moves within the raid) are ignored so they do not delay the sort.
local function onTeamChanged()
    if not live then return end
    local names = Roster.Signature(safe)
    if names == knownNames then return end
    if not names:find(",", 1, true) then PlayerStore.NewRaid() end -- left or disbanded: next raid saves again
    knownNames = names
    resetRun()
    timer = cfg.settleMs
end

function RaidSort.OnLoad()
    live = true
    timer = cfg.settleMs
    loggedRoster = nil
    knownNames = nil
    PlayerStore.Reset()
    Debug.ResetDump()
    Debug.ResetProbe()
    resetRun()
    api.On("TEAM_MEMBERS_CHANGED", onTeamChanged)
    log("raid sort ready (enabled=" .. tostring(settings.Get("RaidSortEnabled")) .. ")")
end

function RaidSort.OnUnload()
    live = false
    api.On("TEAM_MEMBERS_CHANGED", function() return end)
end

-- Called when the Enabled checkbox changes: run at the next update instead of waiting.
function RaidSort.SetEnabled(enabled)
    settings.Update("RaidSortEnabled", enabled)
    resetRun()
    Debug.ResetProbe()
    Debug.ResetDump()
    loggedRoster = nil -- log the roster again on the next pass
    timer = 0
    log("raid sort " .. (enabled and "enabled" or "disabled"))
end

-- Called when the "Save GS+Class" checkbox changes: re-read the raid at the next update.
function RaidSort.SetSaveGsClass(enabled)
    settings.Update("RaidSortSaveGsClass", enabled)
    PlayerStore.ForgetChecked()
    timer = 0
    log("save gs+class " .. (enabled and "on" or "off"))
end

-- Called when the sort style changes: re-plan at the next update.
function RaidSort.SetStyle(style)
    settings.Update("RaidSortStyle", style)
    resetRun()
    timer = 0
    log("raid sort style " .. tostring(style))
end

return RaidSort
