-- Pure raid layout planning (no game API): decides which slot each member should be in, and
-- the next single move that gets the raid closer to that layout.
local SortPlan = {}

-- Slot numbers of the given groups, in group order. Group g holds slots (g-1)*size+1 .. g*size.
local function slotsOf(groups, size)
    local slots = {}
    for _, group in ipairs(groups) do
        for k = 1, size do slots[#slots + 1] = (group - 1) * size + k end
    end
    return slots
end
SortPlan.SlotsOf = slotsOf

-- Highest gear score first; equal (or unknown) scores fall back to name so the order is stable.
local function byGearScore(a, b)
    local ga, gb = a.gs or 0, b.gs or 0
    if ga ~= gb then return ga > gb end
    return a.name < b.name
end

-- Others: by skillset rank first (members without a rank go last), then gear score, then name.
local function byRankThenGearScore(a, b)
    local ra, rb = a.rank or math.huge, b.rank or math.huge
    if ra ~= rb then return ra < rb end
    return byGearScore(a, b)
end

-- Lays the (already sorted) others out one skillset bucket per run of groups, leaving one empty
-- group between buckets. Only done when every bucket fits that way inside the other groups;
-- returns true when it placed everyone, false (placing nothing) when there is not enough room.
local function spaceOut(others, slots, cfg, desired)
    local size = cfg.groupSize
    local buckets, last = {}, nil
    for _, m in ipairs(others) do
        local key = m.rank or math.huge
        if key ~= last then buckets[#buckets + 1] = {}; last = key end
        local bucket = buckets[#buckets]
        bucket[#bucket + 1] = m
    end
    local groupsNeeded = math.max(#buckets - 1, 0)
    for _, bucket in ipairs(buckets) do groupsNeeded = groupsNeeded + math.ceil(#bucket / size) end
    if groupsNeeded > #cfg.otherGroups then return false end
    local group = 0 -- groups used so far, counting gaps
    for _, bucket in ipairs(buckets) do
        for i, m in ipairs(bucket) do
            local index = (group + math.floor((i - 1) / size)) * size + (i - 1) % size + 1
            desired[slots[index]] = m.name
        end
        group = group + math.ceil(#bucket / size) + 1
    end
    return true
end

-- members: list of {name, role = "tank" | "healer" | "other", gs = number or nil, rank = number or nil}
-- rank (lower = earlier) sub-sorts the others before gear score; tanks and healers ignore it.
-- cfg: tankGroups, healerGroups, otherGroups, groupSize, maxMembers,
-- gapBetweenRoles (leave an empty group between skillset buckets of the others when there is room)
-- Returns desired: slot -> member name.
-- Tanks fill their groups, healers theirs, everyone else (plus any tank/healer overflow) the
-- other groups; if those run out the remaining free slots are used, so nobody is left unplaced.
function SortPlan.Build(members, cfg)
    local tanks, healers, others = {}, {}, {}
    for _, m in ipairs(members) do
        if m.role == "tank" then tanks[#tanks + 1] = m
        elseif m.role == "healer" then healers[#healers + 1] = m
        else others[#others + 1] = m end
    end
    table.sort(tanks, byGearScore)
    table.sort(healers, byGearScore)

    local desired = {}
    local function fill(list, slots)
        local rest = {}
        for i, m in ipairs(list) do
            if slots[i] then desired[slots[i]] = m.name else rest[#rest + 1] = m end
        end
        return rest
    end
    local tankOverflow = fill(tanks, slotsOf(cfg.tankGroups, cfg.groupSize))
    local healerOverflow = fill(healers, slotsOf(cfg.healerGroups, cfg.groupSize))
    for _, m in ipairs(tankOverflow) do others[#others + 1] = m end
    for _, m in ipairs(healerOverflow) do others[#others + 1] = m end
    table.sort(others, byRankThenGearScore)

    local slots = slotsOf(cfg.otherGroups, cfg.groupSize)
    local spaced = cfg.gapBetweenRoles and spaceOut(others, slots, cfg, desired)
    local rest = spaced and {} or fill(others, slots)
    local slot = 1
    for _, m in ipairs(rest) do
        while desired[slot] ~= nil do slot = slot + 1 end
        desired[slot] = m.name
    end
    return desired
end

-- Style 2: every group is 1 tank, 3 others, 1 healer (in that order, top to bottom). Tanks, healers
-- and others are each sorted by gear score and handed out group by group, so group 1 gets the
-- highest of each. A group with no tank (or healer) left fills that place with the next other.
-- Tanks / healers beyond the number of groups go back into the others. A group short of people is
-- packed from its top slot, except that its healer stays in the bottom slot of the group (leaving
-- a gap above them); NextMove gets them there by borrowing helper players, see pushAnchor.
function SortPlan.BuildStyle2(members, cfg)
    local size = cfg.groupSize
    local groups = math.ceil(cfg.maxMembers / size)
    local tanks, healers, others = {}, {}, {}
    for _, m in ipairs(members) do
        if m.role == "tank" then tanks[#tanks + 1] = m
        elseif m.role == "healer" then healers[#healers + 1] = m
        else others[#others + 1] = m end
    end
    table.sort(tanks, byGearScore)
    table.sort(healers, byGearScore)
    local needed = math.min(groups, math.ceil(#members / size))
    for i = needed + 1, #tanks do others[#others + 1] = tanks[i]; tanks[i] = nil end
    for i = needed + 1, #healers do others[#others + 1] = healers[i]; healers[i] = nil end
    table.sort(others, byGearScore)

    local nextOther = 1
    local function popOther()
        local m = others[nextOther]
        if m ~= nil then nextOther = nextOther + 1 end
        return m
    end
    local desired = {}
    for g = 1, groups do
        local picks = {tanks[g] or popOther()}
        for _ = 1, size - 2 do picks[#picks + 1] = popOther() end
        local healer = healers[g]
        if healer == nil then picks[#picks + 1] = popOther() end
        local slot = (g - 1) * size
        for _, m in ipairs(picks) do
            slot = slot + 1
            desired[slot] = m.name
        end
        if healer ~= nil then
            -- a short group keeps its healer in the bottom slot, a full one has them right after the others
            desired[slot + 1 < g * size and g * size or slot + 1] = healer.name
        end
    end
    return desired
end

local function groupOf(slot, size)
    return math.ceil(slot / size)
end

-- Topmost free slot of a group (nil when the group is full).
local function topFreeSlot(current, group, size)
    for slot = (group - 1) * size + 1, group * size do
        if current[slot] == nil then return slot end
    end
    return nil
end

-- How the game applies MoveTeamMember(from, to), as observed:
--   * into a different group that has a free slot: the member lands in that group's TOPMOST free
--     slot (not necessarily `to`);
--   * onto an occupied slot (target group full): the two members swap;
--   * within a group: an occupied target swaps, an empty target takes the topmost free slot.
-- Used by the planner's tests; the planner only ever asks for moves where `to` is that topmost free
-- slot or an occupied slot, so it does not depend on the exact rule for empty targets.
function SortPlan.Apply(current, from, to, size)
    size = size or 5
    local mover = current[from]
    if mover == nil then return end
    local target = to
    if current[to] == nil then target = topFreeSlot(current, groupOf(to, size), size) or to end
    if current[target] == nil then
        current[from] = nil
        current[target] = mover
    else
        current[from], current[target] = current[target], current[from]
    end
end

-- Groups whose desired layout has a member in the bottom slot and a gap above them ("anchored"
-- groups, see BuildStyle2). Returns group -> true.
local function anchoredGroups(desired, groups, size)
    local anchored = {}
    for g = 1, groups do
        local last = g * size
        if desired[last] ~= nil then
            for s = last - size + 1, last - 1 do
                if desired[s] == nil then anchored[g] = true; break end
            end
        end
    end
    return anchored
end

-- Phase 0. Moving a member into a group with free slots puts them in the TOPMOST free slot, so the
-- bottom slot of a group with a gap cannot be asked for directly. Instead, once everyone who belongs
-- to the anchored group is in it, borrow players from other groups to fill the free slots above the
-- bottom one (each lands in the topmost free slot); when only the bottom slot is left free, the
-- anchored member moves there. The helpers go home afterwards through the normal group phase.
-- Only done when enough helpers exist, otherwise the anchored member is left where compaction puts them.
local function pushAnchor(current, desired, slotOf, wantGroup, anchored, groups, size, maxSlot)
    for g = 1, groups do
        if anchored[g] then
            local last = g * size
            local anchor = desired[last]
            local anchorSlot = slotOf[anchor]
            if current[last] == nil and anchorSlot ~= nil and groupOf(anchorSlot, size) == g then
                local ready, bodyWanted, helpers = true, 0, 0
                for s = last - size + 1, last - 1 do
                    if desired[s] ~= nil then
                        bodyWanted = bodyWanted + 1
                        local at = slotOf[desired[s]]
                        if at == nil or groupOf(at, size) ~= g then ready = false end
                    end
                    local occupant = current[s]
                    if occupant ~= nil and wantGroup[occupant] ~= g then helpers = helpers + 1 end
                end
                if ready then
                    local need = (size - 1) - (bodyWanted + 1) -- helpers that must stand above the anchored member
                    local free = topFreeSlot(current, g, size)
                    if free == last then
                        return anchorSlot, last, "push " .. anchor .. " to the bottom slot"
                    end
                    -- first member (lowest slot) of another settled group that is not itself anchored
                    local candidates, first = 0, nil
                    for slot = 1, maxSlot do
                        local name = current[slot]
                        local group = groupOf(slot, size)
                        if name ~= nil and group ~= g and wantGroup[name] == group and not anchored[group] then
                            candidates = candidates + 1
                            first = first or slot
                        end
                    end
                    if helpers + candidates >= need and first ~= nil then
                        return first, free, "borrow " .. current[first] .. " as a helper for " .. anchor
                    end
                end
            end
        end
    end
    return nil
end

-- current: slot -> member name. Returns fromSlot, toSlot of the next single move (and, for the
-- helper moves, a third value describing why), or nil when the raid already matches `desired`.
-- Planned in phases so the game's placement rules cannot trip it:
--   1. get everyone into their desired GROUP: into a group with a free slot (target = its topmost
--      free slot), else swap with someone in that group who does not belong there;
--   2. compact each group upward (move a member into the topmost free slot above them);
--   3. order each group by swapping occupied slots (exact, no free-slot placement involved).
-- Every move either puts a member in the right group, closes a gap, or fixes one position, and
-- never undoes earlier progress, so the sequence always finishes.
function SortPlan.NextMove(current, desired, maxSlot, size)
    size = size or 5
    local groups = math.ceil(maxSlot / size)
    local slotOf, wantSlot, wantGroup = {}, {}, {}
    for slot, name in pairs(current) do slotOf[name] = slot end
    for slot, name in pairs(desired) do
        wantSlot[name] = slot
        wantGroup[name] = groupOf(slot, size)
    end

    -- members to place, in desired order so the result is deterministic
    local order = {}
    for slot = 1, maxSlot do
        local name = desired[slot]
        if name ~= nil and slotOf[name] ~= nil then order[#order + 1] = name end
    end

    local anchored = anchoredGroups(desired, groups, size)
    -- 0. get anchored (bottom slot, gap above) members into place with helpers
    local pushFrom, pushTo, pushWhy = pushAnchor(current, desired, slotOf, wantGroup, anchored, groups, size, maxSlot)
    if pushFrom ~= nil then return pushFrom, pushTo, pushWhy end

    -- 1a. into a group that has room
    for _, name in ipairs(order) do
        if groupOf(slotOf[name], size) ~= wantGroup[name] then
            local free = topFreeSlot(current, wantGroup[name], size)
            if free ~= nil then return slotOf[name], free end
        end
    end
    -- 1b. target group is full: swap with a member that does not belong there, preferably one that
    -- wants the mover's current group (fixes both at once)
    for _, name in ipairs(order) do
        local fromGroup = groupOf(slotOf[name], size)
        if fromGroup ~= wantGroup[name] then
            local best, fallback
            for slot = (wantGroup[name] - 1) * size + 1, wantGroup[name] * size do
                local other = current[slot]
                if other ~= nil and wantGroup[other] ~= wantGroup[name] then
                    fallback = fallback or slot
                    if wantGroup[other] == fromGroup then best = best or slot end
                end
            end
            local to = best or fallback
            if to ~= nil then return slotOf[name], to end
        end
    end

    -- 2. close gaps: the bottom-most member that has a free slot above them moves to the topmost one.
    -- In an anchored group the bottom slot is left alone (its member belongs there); anyone else
    -- standing in it moves up, and the rest is compacted within the slots above it.
    for group = 1, groups do
        local last = group * size
        local top = last
        if anchored[group] then
            if current[last] ~= nil and current[last] ~= desired[last] then
                local free = topFreeSlot(current, group, size)
                if free ~= nil then return last, free end
            end
            top = last - 1
        end
        local free
        for slot = (group - 1) * size + 1, top do
            if current[slot] == nil then free = slot; break end
        end
        if free ~= nil then
            for slot = top, free + 1, -1 do
                if current[slot] ~= nil then return slot, free end
            end
        end
    end

    -- 3. order within each group: first wrong position gets the member that belongs there
    for slot = 1, maxSlot do
        local want = desired[slot]
        -- an empty bottom slot of an anchored group is filled by phase 0 (or left empty when no helpers exist)
        local group = groupOf(slot, size)
        local leaveEmpty = current[slot] == nil and anchored[group] and slot == group * size
        if want ~= nil and current[slot] ~= want and slotOf[want] ~= nil and not leaveEmpty then
            return slotOf[want], slot
        end
    end
    return nil
end

return SortPlan
