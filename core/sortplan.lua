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

-- current: slot -> member name. Returns fromSlot, toSlot of the next single move, or nil when the
-- raid already matches `desired`. Planned in phases so the game's placement rules cannot trip it:
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

    -- 2. close gaps: the bottom-most member that has a free slot above them moves to the topmost one
    for group = 1, groups do
        local free = topFreeSlot(current, group, size)
        if free ~= nil then
            for slot = group * size, free + 1, -1 do
                if current[slot] ~= nil then return slot, free end
            end
        end
    end

    -- 3. order within each group: first wrong position gets the member that belongs there
    for slot = 1, maxSlot do
        local want = desired[slot]
        if want ~= nil and current[slot] ~= want and slotOf[want] ~= nil then
            return slotOf[want], slot
        end
    end
    return nil
end

return SortPlan
