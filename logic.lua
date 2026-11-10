local constants = require("AAC-TnT-RaidTools/core/constants")

local M = {}

local function clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.normalizeName(value)
    return clean(value):lower()
end

function M.splitNames(value)
    local result, seen = {}, {}
    for item in (tostring(value or "") .. ","):gmatch("([^,]*),") do
        local name = clean(item)
        local key = M.normalizeName(name)
        if name ~= "" and not seen[key] then
            result[#result + 1], seen[key] = name, true
        end
    end
    return result
end

function M.lookup(names)
    local result = {}
    for _, name in ipairs(names or {}) do
        local key = M.normalizeName(name)
        if key ~= "" then result[key] = true end
    end
    return result
end

function M.matchesPhrase(message, phrase, mode)
    message, phrase = M.normalizeName(message), M.normalizeName(phrase)
    if phrase == "" then return false end
    if mode == "equals" then return message == phrase end
    if mode == "starts" then return message:sub(1, #phrase) == phrase end
    return message:find(phrase, 1, true) ~= nil
end

-- selection is a key of constants.channels. "all" ("*") matches any channel id; the others
-- must equal the numeric channel id the chat event carries.
function M.channelAllowed(channelId, selection)
    local wanted = constants.channels[selection]
    if wanted == nil then return false end
    if wanted == "*" then return true end
    return wanted == tonumber(channelId)
end

-- Optional hook: set M.trace = function(text) to receive one line per check (hooked up in main.lua).
M.trace = nil

local function runCheck(message, channelId, config, blacklist, whitelist)
    if not config.enabled then return false, "invite disabled" end
    if not M.channelAllowed(channelId, config.channel) then
        return false, "channel mismatch (message channel " .. tostring(channelId) .. ", wanted " .. tostring(config.channel) .. ")"
    end
    local nameKey = M.normalizeName(message.name)
    if nameKey == "" then return false, "empty name" end
    if config.blacklistEnabled and blacklist[nameKey] then return false, "name is blacklisted" end
    if config.whitelistEnabled and not whitelist[nameKey] then return false, "name is not whitelisted" end
    if not M.matchesPhrase(message.text, config.phrase, config.match) then
        return false, "phrase mismatch (\"" .. tostring(message.text) .. "\" vs " .. tostring(config.match) .. " \"" .. tostring(config.phrase) .. "\")"
    end
    return true
end

-- Returns true, or false plus the reason the message was rejected.
function M.check(message, channelId, config, blacklist, whitelist)
    local ok, reason = runCheck(message, channelId, config, blacklist, whitelist)
    if M.trace then
        M.trace("check name=" .. tostring(message.name) .. " text=\"" .. tostring(message.text) .. "\" channel=" .. tostring(channelId)
            .. " | enabled=" .. tostring(config.enabled) .. " wantChannel=" .. tostring(config.channel)
            .. " phrase=\"" .. tostring(config.phrase) .. "\" match=" .. tostring(config.match)
            .. " blacklist=" .. tostring(config.blacklistEnabled) .. " whitelist=" .. tostring(config.whitelistEnabled)
            .. " => " .. (ok and "MATCH" or ("no: " .. reason)))
    end
    return ok, reason
end

function M.eligible(message, channelId, config, blacklist, whitelist)
    return (M.check(message, channelId, config, blacklist, whitelist))
end

return M
