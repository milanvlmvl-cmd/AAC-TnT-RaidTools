local constants = require("AAC-TnT-RaidTools/core/constants")

-- Name and chat-phrase matching for the invites and the lead pass (pure, no game calls).
local Matching = {}

local function clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Matching.normalizeName(value)
    return clean(value):lower()
end

function Matching.splitNames(value)
    local result, seen = {}, {}
    for item in (tostring(value or "") .. ","):gmatch("([^,]*),") do
        local name = clean(item)
        local key = Matching.normalizeName(name)
        if name ~= "" and not seen[key] then
            result[#result + 1], seen[key] = name, true
        end
    end
    return result
end

function Matching.lookup(names)
    local result = {}
    for _, name in ipairs(names or {}) do
        local key = Matching.normalizeName(name)
        if key ~= "" then result[key] = true end
    end
    return result
end

function Matching.matchesPhrase(message, phrase, mode)
    message, phrase = Matching.normalizeName(message), Matching.normalizeName(phrase)
    if phrase == "" then return false end
    if mode == "equals" then return message == phrase end
    if mode == "starts" then return message:sub(1, #phrase) == phrase end
    return message:find(phrase, 1, true) ~= nil
end

-- selection is a key of constants.channels. "all" ("*") matches any channel id; the others
-- must equal the numeric channel id the chat event carries.
function Matching.channelAllowed(channelId, selection)
    local wanted = constants.channels[selection]
    if wanted == nil then return false end
    if wanted == "*" then return true end
    return wanted == tonumber(channelId)
end

-- Whether an invite config accepts a chat message: returns true, or false plus the reason it was rejected.
-- config: channel, match, phrase, blacklistEnabled, whitelistEnabled; blacklist / whitelist are
-- lookup tables from Matching.lookup.
function Matching.check(message, channelId, config, blacklist, whitelist)
    if not Matching.channelAllowed(channelId, config.channel) then
        return false, "channel mismatch (message channel " .. tostring(channelId) .. ", wanted " .. tostring(config.channel) .. ")"
    end
    local nameKey = Matching.normalizeName(message.name)
    if nameKey == "" then return false, "empty name" end
    if config.blacklistEnabled and blacklist[nameKey] then return false, "name is blacklisted" end
    if config.whitelistEnabled and not whitelist[nameKey] then return false, "name is not whitelisted" end
    if not Matching.matchesPhrase(message.text, config.phrase, config.match) then
        return false, "phrase mismatch (\"" .. tostring(message.text) .. "\" vs " .. tostring(config.match) .. " \"" .. tostring(config.phrase) .. "\")"
    end
    return true
end

return Matching
