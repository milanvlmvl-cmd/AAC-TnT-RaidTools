-- Plain-Lua tests for the parts of the addon that do not need the game: name / phrase matching,
-- invite ordering and the raid sort planner. Run from the addon folder:  luajit tests/run.lua
-- (any Lua 5.1 / LuaJIT works).

-- "AAC-TnT-RaidTools/x/y" resolves to ./x/y.lua whatever the folder is called
table.insert(package.loaders or package.searchers, 2, function(name)
    local rel = name:match("^AAC%-TnT%-RaidTools/(.+)$")
    if rel then
        local chunk = loadfile(rel .. ".lua")
        if chunk then return chunk end
    end
end)

-- stand-in for the game's `api` module: only what the tested modules touch while loading
local saved = {}
package.preload["api"] = function()
    return {
        baseDir = "addons",
        GetSettings = function() return saved end,
        SaveSettings = function() end,
    }
end

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function equal(actual, expected, message)
    check(actual == expected, message .. " (got " .. tostring(actual) .. ", expected " .. tostring(expected) .. ")")
end

local Matching = require("AAC-TnT-RaidTools/core/matching")
local settings = require("AAC-TnT-RaidTools/core/settings")
local constants = require("AAC-TnT-RaidTools/core/constants")
local SortPlan = require("AAC-TnT-RaidTools/core/sortplan")
local AfkWatch = require("AAC-TnT-RaidTools/features/afkwatch")

-- ---------------------------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------------------------
equal(Matching.normalizeName("  Ann  "), "ann", "normalizeName trims and lowercases")
equal(Matching.normalizeName(nil), "", "normalizeName of nil")
local names = Matching.splitNames("Ann, bob ,ANN,,Cy")
equal(#names, 3, "splitNames drops blanks and case-insensitive duplicates")
equal(names[1] .. names[2] .. names[3], "AnnbobCy", "splitNames keeps first spelling and order")
check(Matching.lookup({"Ann", "Bob"}).ann == true, "lookup is keyed by lowercase name")

check(Matching.matchesPhrase("X", "x", "equals"), "equals ignores case")
check(not Matching.matchesPhrase("x please", "x", "equals"), "equals needs the whole message")
check(Matching.matchesPhrase("x please", "x", "starts"), "starts matches the beginning")
check(not Matching.matchesPhrase("please x", "x", "starts"), "starts does not match the middle")
check(Matching.matchesPhrase("please x now", "x", "includes"), "includes matches anywhere")
check(not Matching.matchesPhrase("anything", "", "includes"), "an empty phrase never matches")
check(Matching.matchesPhrase("a.b", ".", "includes"), "phrase is plain text, not a pattern")

check(Matching.channelAllowed(7, "guild"), "guild id matches guild")
check(not Matching.channelAllowed(6, "guild"), "nation id does not match guild")
check(Matching.channelAllowed(99, "all"), "all matches any channel id")
check(not Matching.channelAllowed(7, "nonsense"), "unknown channel selection never matches")

local invite = {channel = "all", match = "equals", phrase = "x", blacklistEnabled = true, whitelistEnabled = true}
local black, white = Matching.lookup({"Bad"}), Matching.lookup({"Good", "Bad"})
check(Matching.check({name = "Good", text = "x"}, 1, invite, black, white), "listed name with the phrase passes")
local ok, reason = Matching.check({name = "Bad", text = "x"}, 1, invite, black, white)
check(not ok and reason == "name is blacklisted", "blacklisted name is rejected")
ok, reason = Matching.check({name = "Other", text = "x"}, 1, invite, black, white)
check(not ok and reason == "name is not whitelisted", "unlisted name is rejected when the whitelist is on")
ok = Matching.check({name = "Good", text = "y"}, 1, invite, black, white)
check(not ok, "wrong phrase is rejected")

-- ---------------------------------------------------------------------------------------------
-- Settings: invite ordering and normalising
-- ---------------------------------------------------------------------------------------------
local list = {{Phrase = "a", Active = false}, {Phrase = "b"}, {Phrase = "c", Active = false}, {Phrase = "d"}}
local activeCount, moved = settings.SortInvites(list)
equal(activeCount, 2, "SortInvites counts active invites")
check(moved, "SortInvites reports a move")
equal(list[1].Phrase .. list[2].Phrase .. list[3].Phrase .. list[4].Phrase, "bdac", "active first, order kept inside each group")
check(select(2, settings.SortInvites(list)) == false, "a sorted list does not move again")

saved = {Invites = {{Phrase = 5, Channel = "bogus", Match = "starts"}}, LeadChannel = "all", AfkMinutes = 7, RaidSortStyle = 9}
settings.Reset()
local invites = settings.GetInvites()
equal(invites[1].Phrase, "x", "invalid phrase falls back to the default")
equal(invites[1].Channel, "all", "invalid channel falls back to the default")
equal(invites[1].Match, "starts", "valid match is kept")
equal(settings.Get("LeadChannel"), "whisper", "lead channel 'all' is no longer valid")
equal(settings.Get("AfkMinutes"), 2, "unknown AFK minutes fall back")
equal(settings.Get("RaidSortStyle"), constants.sortStyle.party, "unknown sort style falls back")
equal(settings.ActiveListKey("Blacklist", "private"), "BlacklistPrivate", "ActiveListKey private")
equal(settings.ActiveListKey("Whitelist", "disabled"), nil, "ActiveListKey disabled")
saved = {}
settings.Reset()

-- ---------------------------------------------------------------------------------------------
-- AFK watch
-- ---------------------------------------------------------------------------------------------
do
    local limit = AfkWatch.Limit() -- default 2 minutes
    equal(limit, math.floor(2 * 60000 / constants.afk.intervalMs), "AFK limit from the default minutes")
    local state, event = AfkWatch.Step(nil, 0, 0, 0)
    equal(event, nil, "first reading gives no event")
    for _ = 1, limit - 1 do state, event = AfkWatch.Step(state, 0.5, 0, 0) end
    equal(event, nil, "no event before the limit")
    state, event = AfkWatch.Step(state, 0, 0, 0)
    equal(event, "afk", "event when the limit is reached")
    state, event = AfkWatch.Step(state, 0, 0, 0)
    equal(event, nil, "no second afk event while staying put")
    equal(state.points, limit, "points stay at the limit")
    state, event = AfkWatch.Step(state, 50, 0, 0)
    equal(event, "back", "moving ends AFK")
    equal(state.points, 0, "moving resets the points")
end

-- ---------------------------------------------------------------------------------------------
-- Raid sort planner
-- ---------------------------------------------------------------------------------------------
local cfg = constants.raidSort

local function member(name, role, gs) return {name = name, role = role, gs = gs} end

-- Plays NextMove against the game's placement rules (SortPlan.Apply) until it has nothing to do.
-- Returns the final layout, the number of moves, and an error text when something went wrong.
local function settle(current, desired)
    local moves = 0
    while true do
        local from, to = SortPlan.NextMove(current, desired, cfg.maxMembers, cfg.groupSize)
        if from == nil then return current, moves end
        moves = moves + 1
        if moves > 400 then return current, moves, "did not finish in 400 moves" end
        if current[from] == nil then return current, moves, "moved from empty slot " .. from end
        if SortPlan.Apply(current, from, to, cfg.groupSize) == false then
            return current, moves, "move " .. from .. " -> " .. to .. " has no effect in the game"
        end
    end
end

local function scatter(members, seed)
    math.randomseed(seed)
    local slots = {}
    for slot = 1, cfg.maxMembers do slots[slot] = slot end
    for i = #slots, 2, -1 do
        local j = math.random(i)
        slots[i], slots[j] = slots[j], slots[i]
    end
    local current = {}
    for i, m in ipairs(members) do current[slots[i]] = m.name end
    return current
end

local function randomRaid(size, seed)
    math.randomseed(seed)
    local roles = {"tank", "healer", "other", "other", "other"}
    local members = {}
    for i = 1, size do
        members[i] = member("P" .. i, roles[math.random(#roles)], math.random(1000, 4000))
    end
    return members
end

local function groupOf(slot) return math.ceil(slot / cfg.groupSize) end
local function slotOf(layout, name)
    for slot, who in pairs(layout) do if who == name then return slot end end
end

-- Class style: roles land in their own groups, best gear score first
do
    local members = {
        member("T1", "tank", 3000), member("T2", "tank", 3500), member("H1", "healer", 2000),
        member("H2", "healer", 2500), member("D1", "other", 1000), member("D2", "other", 4000),
    }
    local desired = SortPlan.Build(members, cfg)
    equal(desired[1], "T2", "class style: best tank in the first tank slot")
    equal(desired[2], "T1", "class style: next tank after")
    equal(desired[21], "H2", "class style: best healer first in group 5")
    equal(desired[22], "H1", "class style: next healer")
    equal(desired[3], "D2", "class style: short tank group 1 backfilled with the others")
    equal(desired[4], "D1", "class style: backfilled others keep their order")
    equal(desired[6], nil, "class style: group 2 emptied by the backfill")
end

local function others(count, from)
    local list = {}
    for i = 1, count do list[i] = member("D" .. (from + i - 1), "other", 2000 - (from + i - 1)) end
    return list
end
local function with(list, extra)
    for _, m in ipairs(extra) do list[#list + 1] = m end
    return list
end

-- Class style: group 1 backfilled with the best others; tankless group 6 comes after groups 2-4
do
    local desired = SortPlan.Build(with({member("T1", "tank", 3000)}, others(25, 1)), cfg)
    equal(desired[1], "T1", "class: tank on top of group 1")
    equal(desired[2], "D1", "class: best other backfills group 1")
    equal(desired[5], "D4", "class: group 1 full")
    equal(desired[6], "D5", "class: next other starts group 2")
    equal(desired[20], "D19", "class: groups 2-4 full")
    equal(desired[26], "D20", "class: tankless group 6 filled after group 4")
    equal(desired[30], "D24", "class: group 6 full")
    equal(desired[31], "D25", "class: then group 7")
end

-- Tankless group 6 stays empty while groups 2-4 have room
do
    local desired = SortPlan.Build(with({member("T1", "tank", 3000)}, others(10, 1)), cfg)
    equal(desired[26], nil, "class: group 6 untouched while groups 2-4 have room")
    equal(desired[11], "D10", "class: others still in group 3")
end

-- Group 6 with a tank is backfilled right after group 1
do
    local members = {}
    for i = 1, 6 do members[i] = member("T" .. i, "tank", 3000 - i) end
    local desired = SortPlan.Build(with(members, others(12, 1)), cfg)
    equal(desired[26], "T6", "class: sixth tank in group 6")
    equal(desired[27], "D1", "class: group 6 backfilled with the best others")
    equal(desired[30], "D4", "class: group 6 full")
    equal(desired[6], "D5", "class: rest of the others start in group 2")
end

-- Healer overflow joins the bottom of the tanks
do
    local members = {member("T1", "tank", 100)}
    for i = 1, 11 do members[#members + 1] = member("H" .. i, "healer", 3000 - i) end
    local desired = SortPlan.Build(members, cfg)
    equal(desired[21], "H1", "class: best healer in group 5")
    equal(desired[46], "H6", "class: sixth healer in group 10")
    equal(desired[1], "T1", "class: real tank first")
    equal(desired[2], "H11", "class: overflow healer after the tanks")
end

-- Tank overflow goes to the top of the others
do
    local members = {}
    for i = 1, 11 do members[i] = member("T" .. i, "tank", 3000 - i) end
    local desired = SortPlan.Build(with(members, {member("D1", "other", 9999)}), cfg)
    equal(desired[30], "T10", "class: tank groups full")
    equal(desired[6], "T11", "class: overflow tank before the others")
    equal(desired[7], "D1", "class: others after the overflow tank")
end

-- Others beyond the other groups (and tankless group 6) go to group 10
do
    local desired = SortPlan.Build(with({member("T1", "tank", 3000)}, others(41, 1)), cfg)
    equal(desired[26], "D20", "class: tankless group 6 after group 4")
    equal(desired[45], "D39", "class: other groups full")
    equal(desired[46], "D40", "class: then group 10")
    equal(desired[47], "D41", "class: group 10 packed from the top")
end

-- Party style: each group is tank, others, healer
do
    local members = {}
    for i = 1, 4 do members[#members + 1] = member("T" .. i, "tank", 3000 - i) end
    for i = 1, 4 do members[#members + 1] = member("H" .. i, "healer", 2000 - i) end
    for i = 1, 12 do members[#members + 1] = member("D" .. i, "other", 1000 - i) end
    local desired = SortPlan.BuildStyle2(members, cfg)
    equal(desired[1], "T1", "party style: group 1 starts with the best tank")
    equal(desired[5], "H1", "party style: group 1 ends with the best healer")
    equal(desired[6], "T2", "party style: group 2 starts with the next tank")
    equal(desired[2], "D1", "party style: best other fills group 1")
    local seen = 0
    for _ in pairs(desired) do seen = seen + 1 end
    equal(seen, #members, "party style: everybody is placed exactly once")
end

-- Tanks beyond the tank groups are not lost
do
    local members = {}
    for i = 1, 3 do members[#members + 1] = member("T" .. i, "tank", 3000 - i) end
    local desired = SortPlan.Build(members, {tankGroups = {1}, healerGroups = {2}, otherGroups = {3}, groupSize = 1, maxMembers = 3})
    local placed = {}
    for _, name in pairs(desired) do placed[name] = true end
    check(placed.T1 and placed.T2 and placed.T3, "overflow tanks are placed in other slots")
end

-- NextMove always finishes, never wastes a move on something the game ignores, and every member ends
-- up in the group the plan wants
for seed = 1, 60 do
    local size = 1 + (seed * 7) % cfg.maxMembers
    local members = randomRaid(size, seed)
    for style = 1, 2 do
        local desired = style == 1 and SortPlan.Build(members, cfg) or SortPlan.BuildStyle2(members, cfg)
        local final, moves, problem = settle(scatter(members, seed * 31 + style), desired)
        local label = "seed " .. seed .. " style " .. style .. " (" .. size .. " members)"
        check(problem == nil, label .. ": " .. tostring(problem))
        local misplaced = 0
        for slot, name in pairs(desired) do
            local at = slotOf(final, name)
            if at == nil or groupOf(at) ~= groupOf(slot) then misplaced = misplaced + 1 end
        end
        equal(misplaced, 0, label .. ": members outside their planned group after " .. moves .. " moves")
        if style == 1 then
            -- class style has no anchored groups: the whole layout must match exactly
            local different = 0
            for slot, name in pairs(desired) do if final[slot] ~= name then different = different + 1 end end
            equal(different, 0, label .. ": slots differing from the plan")
        end
    end
end

-- A raid that already matches the plan needs no move
do
    local members = randomRaid(20, 5)
    local desired = SortPlan.Build(members, cfg)
    local from = SortPlan.NextMove(desired, desired, cfg.maxMembers, cfg.groupSize)
    equal(from, nil, "a sorted raid needs no move")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
