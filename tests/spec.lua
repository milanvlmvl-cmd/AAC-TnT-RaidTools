local Logic = require(ADDON_ID .. "/logic")
local addon = require(ADDON_ID .. "/main")
local cases = 0
local function test(name, fn)
    local ok, why = pcall(fn)
    if not ok then error(name .. ": " .. tostring(why)) end
    cases = cases + 1
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end

test("phrase matching", function()
    equal(Logic.matchesPhrase("X-UP now", "x-up", "starts"), true)
    equal(Logic.matchesPhrase("please x-up", "x-up", "includes"), true)
    equal(Logic.matchesPhrase("x-up", "x-up", "equals"), true)
    equal(Logic.matchesPhrase("x-up now", "x-up", "equals"), false)
end)

test("channel and list handling", function()
    equal(Logic.channelAllowed(-3, "whisper"), true)
    equal(Logic.channelAllowed(7, "whisper"), false)
    local names = Logic.splitNames(" Alice,alice, Bob ")
    equal(#names, 2)
    equal(Logic.lookup(names).alice, true)
end)

test("invite eligibility", function()
    local config = {enabled = true, channel = "faction", match = "includes", phrase = "x-up", whitelistEnabled = true}
    local white = Logic.lookup({"Alice"})
    equal(Logic.eligible({name = "Alice", text = "x-up please"}, -1, config, {}, white), true)
    equal(Logic.eligible({name = "Bob", text = "x-up please"}, -1, config, {}, white), false)
    equal(Logic.eligible({name = "Alice", text = "x-up please"}, 7, config, {}, white), false)
end)

test("lead transfer uses team index", function()
    local called
    local team = {
        GetMemberIndexByName = function(_, name) return name == "Alice" and 3 or 0 end,
        MakeTeamOwner = function(_, id) called = id end
    }
    local ok = Logic.passLead(team, "Alice")
    equal(ok, true)
    equal(called, "team3")
end)

assert(addon.name == EXPECTED_NAME and addon.author == EXPECTED_AUTHOR and addon.version == EXPECTED_VERSION)
return cases
